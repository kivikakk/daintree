const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");
const elf = @import("elf.zig");
const dtblib = @import("dtb");
const searchDtbForUartBase = @import("dtb.zig").searchDtbForUartBase;

usingnamespace @import("util.zig");

var boot_services: *uefi.tables.BootServices = undefined;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    printf("panic: {s}\r\n", .{msg});
    asm volatile ("b .");
    unreachable;
}

pub fn main() void {
    con_out = uefi.system_table.con_out.?;
    boot_services = uefi.system_table.boot_services.?;

    printf("daintree bootloader {s} on {s}\r\n", .{ build_options.version, build_options.board });

    var load_context = LoadContext{};

    var options_buffer: [256]u8 = [_]u8{undefined} ** 256;
    if (getLoadOptions(&options_buffer)) |options| {
        printf("load options: \"{s}\"\r\n", .{options});
        load_context.handleOptions(options);
    }

    if (load_context.dtb == null or load_context.dainkrnl == null) {
        load_context.searchFileSystems();
    }

    const dtb = load_context.dtb orelse {
        printf("\r\nDTB not found\r\n", .{});
        _ = boot_services.stall(5 * 1000 * 1000);
        return;
    };
    const dainkrnl = load_context.dainkrnl orelse {
        printf("\r\nDAINKRNL not found\r\n", .{});
        _ = boot_services.stall(5 * 1000 * 1000);
        return;
    };

    exitBootServices(dainkrnl, dtb);
}

const LoadContext = struct {
    const Self = @This();

    dtb: ?[]const u8 = null,
    dainkrnl: ?[]const u8 = null,

    fn handleOptions(self: *Self, options: []const u8) void {
        var it = std.mem.tokenize(options, " ");

        loop: while (it.next()) |opt_name| {
            if (std.mem.eql(u8, opt_name, "dtb")) {
                const loc = handleOptionsLoc("dtb", &it) orelse continue :loop;
                printf("using dtb in ramdisk at 0x{x:0>16} ({} bytes)\r\n", .{ loc.offset, loc.len });
                self.dtb = @intToPtr([*]u8, loc.offset)[0..loc.len];
            } else if (std.mem.eql(u8, opt_name, "kernel")) {
                const loc = handleOptionsLoc("kernel", &it) orelse continue :loop;
                printf("using kernel in ramdisk at 0x{x:0>16} ({} bytes)\r\n", .{ loc.offset, loc.len });
                self.dainkrnl = @intToPtr([*]u8, loc.offset)[0..loc.len];
            } else {
                printf("unknown option '{s}'\r\n", .{opt_name});
            }
        }
    }

    fn searchFileSystems(self: *Self) void {
        var handle_list_size: usize = 0;
        var handle_list: [*]uefi.Handle = undefined;
        while (boot_services.locateHandle(
            .ByProtocol,
            &uefi.protocols.SimpleFileSystemProtocol.guid,
            null,
            &handle_list_size,
            handle_list,
        ) == .BufferTooSmall) {
            check("allocatePool", boot_services.allocatePool(
                uefi.tables.MemoryType.BootServicesData,
                handle_list_size,
                @ptrCast(*[*]align(8) u8, &handle_list),
            ));
        }

        if (handle_list_size == 0) {
            printf("no simple file system protocols found\r\n", .{});
            return;
        }

        const handle_count = handle_list_size / @sizeOf(uefi.Handle);

        printf("searching for <", .{});
        if (self.dtb == null) {
            printf("DTB", .{});
            if (self.dainkrnl == null) printf(" ", .{});
        }
        if (self.dainkrnl == null) printf("DAINKRNL", .{});
        printf("> on {} volume(s) ", .{handle_count});

        for (handle_list[0..handle_count]) |handle| {
            var sfs_proto: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;

            check("openProtocol", boot_services.openProtocol(
                handle,
                &uefi.protocols.SimpleFileSystemProtocol.guid,
                @ptrCast(*?*c_void, &sfs_proto),
                uefi.handle,
                null,
                .{ .get_protocol = true },
            ));

            printf(".", .{});

            var f_proto: *uefi.protocols.FileProtocol = undefined;
            check("openVolume", sfs_proto.?.openVolume(&f_proto));

            if (self.dainkrnl == null) {
                self.dainkrnl = tryLoadFromFileProtocol(f_proto, "dainkrnl");
            }
            if (self.dtb == null) {
                self.dtb = tryLoadFromFileProtocol(f_proto, "dtb");
            }

            _ = boot_services.closeProtocol(handle, &uefi.protocols.SimpleFileSystemProtocol.guid, uefi.handle, null);

            if (self.dainkrnl != null and self.dtb != null) {
                break;
            }
        }
    }

    // ---

    const Loc = struct {
        offset: u64,
        len: u64,
    };

    fn handleOptionsLoc(comptime opt_name: []const u8, it: *std.mem.TokenIterator) ?Loc {
        const offset_s = it.next() orelse {
            printf(opt_name ++ ": missing offset argument\r\n", .{});
            return null;
        };
        const len_s = it.next() orelse {
            printf(opt_name ++ ": missing length argument\r\n", .{});
            return null;
        };

        const offset = std.fmt.parseInt(u64, offset_s, 0) catch |err| {
            printf(opt_name ++ ": parse offset '{s}' error: {}\r\n", .{ offset_s, err });
            return null;
        };
        const len = std.fmt.parseInt(u64, len_s, 0) catch |err| {
            printf(opt_name ++ ": parse len '{s}' error: {}\r\n", .{ len_s, err });
            return null;
        };
        return Loc{ .offset = offset, .len = len };
    }
};

fn getLoadOptions(buffer: *[256]u8) ?[]const u8 {
    var li_proto: ?*uefi.protocols.LoadedImageProtocol = undefined;
    if (boot_services.openProtocol(
        uefi.handle,
        &uefi.protocols.LoadedImageProtocol.guid,
        @ptrCast(*?*c_void, &li_proto),
        uefi.handle,
        null,
        .{ .get_protocol = true },
    ) != .Success) {
        return null;
    }

    const options_size = li_proto.?.load_options_size;
    if (options_size == 0) {
        return null;
    }

    var ptr: [*]u16 = @ptrCast([*]u16, @alignCast(@alignOf([*]u16), li_proto.?.load_options.?));
    if (std.unicode.utf16leToUtf8(buffer[0..], ptr[0 .. options_size / 2])) |sz| {
        var options = buffer[0..sz];
        if (options.len > 0 and options[options.len - 1] == 0) {
            options = options[0 .. options.len - 1];
        }
        return options;
    } else |err| {
        printf("failed utf16leToUtf8: {}\r\n", .{err});
        return null;
    }
}

fn tryLoadFromFileProtocol(f_proto: *uefi.protocols.FileProtocol, comptime file_name: []const u8) ?[]const u8 {
    var proto: *uefi.protocols.FileProtocol = undefined;
    var size: u64 = undefined;
    var mem: [*]u8 = undefined;

    const file_name_u16: [:0]const u16 = comptime blk: {
        var n: [:0]const u16 = &[_:0]u16{};
        for (file_name) |c| {
            n = n ++ [_]u16{c};
        }
        break :blk n;
    };

    if (f_proto.open(&proto, file_name_u16, uefi.protocols.FileProtocol.efi_file_mode_read, 0) != .Success) {
        return null;
    }

    check("setPosition", proto.setPosition(uefi.protocols.FileProtocol.efi_file_position_end_of_file));
    check("getPosition", proto.getPosition(&size));
    printf(" \"{s}\" {} bytes ", .{ file_name, size });

    check("setPosition", proto.setPosition(0));

    check("allocatePool", boot_services.allocatePool(
        .BootServicesData,
        size,
        @ptrCast(*[*]align(8) u8, &mem),
    ));
    check("read", proto.read(&size, mem));
    return mem[0..size];
}

fn parseElf(bytes: []const u8) elf.Header {
    if (bytes.len < @sizeOf(elf.Elf64_Ehdr)) {
        printf("found {} byte(s), too small for ELF header ({} bytes)\r\n", .{ bytes.len, @sizeOf(elf.Elf64_Ehdr) });
        halt();
    }

    var buffer = std.io.fixedBufferStream(bytes);
    var elf_header = elf.Header.read(&buffer) catch |err| {
        printf("failed to parse ELF: {}\r\n", .{err});
        halt();
    };

    printf("ELF entrypoint: {x:0>16} ({}-bit {c}E)\r\n", .{
        elf_header.entry,
        @as(u8, if (elf_header.is_64) 64 else 32),
        @as(u8, if (elf_header.endian == .Big) 'B' else 'L'),
    });

    var it = elf_header.program_header_iterator(&buffer);
    while (it.next() catch haltMsg("iterating phdr")) |phdr| {
        printf(" * type={x:0>8} off={x:0>16} vad={x:0>16} pad={x:0>16} fsz={x:0>16} msz={x:0>16}\r\n", .{ phdr.p_type, phdr.p_offset, phdr.p_vaddr, phdr.p_paddr, phdr.p_filesz, phdr.p_memsz });
    }

    return elf_header;
}

fn exitBootServices(dainkrnl: []const u8, dtb: []const u8) noreturn {
    const dainkrnl_elf = parseElf(dainkrnl);
    var elf_source = std.io.fixedBufferStream(dainkrnl);
    var kernel_size: u64 = 0;
    {
        var it = dainkrnl_elf.program_header_iterator(&elf_source);
        while (it.next() catch haltMsg("iterating phdrs (2)")) |phdr| {
            if (phdr.p_type == elf.PT_LOAD) {
                const target = phdr.p_vaddr - 0xffffff80_00000000;
                const load_bytes = std.math.min(phdr.p_filesz, phdr.p_memsz);
                printf("will load 0x{x:0>16} bytes at 0x{x:0>16} into offset+0x{x:0>16}\r\n", .{ load_bytes, phdr.p_vaddr, target });
                if (phdr.p_memsz > phdr.p_filesz) {
                    printf("  and zeroing {} bytes at end\r\n", .{phdr.p_memsz - phdr.p_filesz});
                }
                kernel_size = std.math.max(kernel_size, target + phdr.p_memsz);
            }
        }
    }
    var graphics: *uefi.protocols.GraphicsOutputProtocol = undefined;
    check("locateProtocol", boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics)));
    var fb: [*]u8 = @intToPtr([*]u8, graphics.mode.frame_buffer_base);

    var dtb_scratch_ptr: [*]u8 = undefined;
    check("allocatePool", boot_services.allocatePool(uefi.tables.MemoryType.BootServicesData, 128 * 1024, @ptrCast(*[*]align(8) u8, &dtb_scratch_ptr)));
    var dtb_scratch = dtb_scratch_ptr[0 .. 128 * 1024];

    printf("looking up serial base in DTB ... ", .{});
    var uart_base: u64 = searchDtbForUartBase(dtb) catch |err| dtb: {
        printf("failed to parse dtb: {}", .{err});
        break :dtb 0;
    };
    printf("0x{x:0>8}\r\n", .{uart_base});

    printf("we will clean d/i$ for 0x{x} bytes\r\n", .{kernel_size});

    printf("going quiet before obtaining memory map\r\n", .{});

    // *****************************************************************
    // * Minimise logging between here and boot services exit.         *
    // * Otherwise the chance a console log will cause our firmware to *
    // * allocate memory and invalidate the memory map will increase.  *
    // *****************************************************************

    var memory_map: [*]uefi.tables.MemoryDescriptor = undefined;
    var memory_map_size: usize = 0;
    var memory_map_key: usize = undefined;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;
    while (boot_services.getMemoryMap(
        &memory_map_size,
        memory_map,
        &memory_map_key,
        &descriptor_size,
        &descriptor_version,
    ) == uefi.Status.BufferTooSmall) {
        check("allocatePool", boot_services.allocatePool(
            uefi.tables.MemoryType.BootServicesData,
            memory_map_size,
            @ptrCast(*[*]align(8) u8, &memory_map),
        ));
    }

    var largest_conventional: ?*uefi.tables.MemoryDescriptor = null;

    {
        var offset: usize = 0;
        var i: usize = 0;
        while (offset < memory_map_size) : ({
            offset += descriptor_size;
            i += 1;
        }) {
            const ptr = @intToPtr(*uefi.tables.MemoryDescriptor, @ptrToInt(memory_map) + offset);
            if (ptr.type == .ConventionalMemory) {
                if (largest_conventional) |current_largest| {
                    if (ptr.number_of_pages > current_largest.number_of_pages) {
                        largest_conventional = ptr;
                    }
                } else {
                    largest_conventional = ptr;
                }
            }
        }
    }
    // Just take the single biggest bit of conventional memory.
    const conventional_start = largest_conventional.?.physical_start;
    const conventional_bytes = largest_conventional.?.number_of_pages << 12;

    // The kernel's text section begins at 0xffffff80_00000000. Adjust those down
    // to conventional_start now.

    var it = dainkrnl_elf.program_header_iterator(&elf_source);
    while (it.next() catch haltMsg("iterating phdrs (2)")) |phdr| {
        if (phdr.p_type == elf.PT_LOAD) {
            const target = phdr.p_vaddr - 0xffffff80_00000000 + conventional_start;
            std.mem.copy(u8, @intToPtr([*]u8, target)[0..phdr.p_filesz], dainkrnl[phdr.p_offset .. phdr.p_offset + phdr.p_filesz]);
            if (phdr.p_memsz > phdr.p_filesz) {
                std.mem.set(u8, @intToPtr([*]u8, target)[phdr.p_filesz..phdr.p_memsz], 0);
            }
        }
    }

    // Clean and invalidate D- and I-caches for loaded code.
    asm volatile (
        \\  ADD x1, x1, x0                // Base Address + Length
        \\  MRS X2, CTR_EL0               // Read Cache Type Register
        \\  // Get the minimun data cache line
        \\  //
        \\  UBFX X4, X2, #16, #4          // Extract DminLine (log2 of the cache line)
        \\  MOV X3, #4                    // Dminline iss the number of words (4 bytes)
        \\  LSL X3, X3, X4                // X3 should contain the cache line
        \\  SUB X4, X3, #1                // get the mask for the cache line
        \\
        \\  BIC X4, X0, X4                // Aligned the base address of the region
        \\clean_data_cache:
        \\  DC CVAU, X4                   // Clean data cache line by VA to PoU
        \\  ADD X4, X4, X3                // Next cache line
        \\  CMP X4, X1                    // Is X4 (current cache line) smaller than the end 
        \\                                // of the region
        \\  B.LT clean_data_cache         // while (address < end_address)
        \\
        \\  DSB ISH                       // Ensure visibility of the data cleaned from cache
        \\
        \\  //
        \\  //Clean the instruction cache by VA
        \\  //
        \\
        \\  // Get the minimum instruction cache line (X2 contains ctr_el0)
        \\  AND X2, X2, #0xF             // Extract IminLine (log2 of the cache line)
        \\  MOV X3, #4                   // IminLine is the number of words (4 bytes)
        \\  LSL X3, X3, X2               // X3 should contain the cache line
        \\  SUB x4, x3, #1               // Get the mask for the cache line
        \\
        \\  BIC X4, X0, X4               // Aligned the base address of the region
        \\clean_instruction_cache:
        \\  IC IVAU, X4                  // Clean instruction cache line by VA to PoU
        \\  ADD X4, X4, X3               // Next cache line
        \\  CMP X4, X1                   // Is X4 (current cache line) smaller than the end 
        \\                               // of the region
        \\  B.LT clean_instruction_cache // while (address < end_address)
        \\
        \\  DSB ISH                      // Ensure completion of the invalidations
        \\  ISB                          // Synchronize the fetched instruction stream
        :
        : [conventional_start] "{x0}" (conventional_start),
          [kernel_size] "{x1}" (kernel_size)
        : "memory", "x2", "x3", "x4"
    );

    if (graphics.mode.info.horizontal_resolution != graphics.mode.info.pixels_per_scan_line) {
        haltMsg("horizontal res != pixels per scan line");
    }

    printf("{x} ", .{conventional_start});

    check("exitBootServices", boot_services.exitBootServices(uefi.handle, memory_map_key));

    const adjusted_entry = dainkrnl_elf.entry - 0xffffff80_00000000 + conventional_start;

    const verthoriz: u64 = @as(u64, graphics.mode.info.vertical_resolution) << 32 | graphics.mode.info.horizontal_resolution;

    // Check for EL2: we get
    // and pass to DAINKRNL.
    asm volatile ((if (comptime std.mem.eql(u8, "qemu", build_options.board))
            // QEMU only: clear x29, x30. EDK2 trips over when generating stacks otherwise.
            \\mov x29, xzr
            \\mov x30, xzr
            \\
        else
            "") ++
            // Disable MMU, alignment checking, SP alignment checking;
            // set little endian in EL0 and EL1.
            \\mov x10, #0x0800
            \\movk x10, #0x30d0, lsl #16
            \\msr sctlr_el1, x10
            \\isb

            // Check if other cores are running.
            \\mrs x10, mpidr_el1
            \\and x10, x10, #3
            \\cbz x10, .cpu_zero

            // Non-zero core
            \\mov x10, #0x44       // XXX Record progress "D"
            \\strb w10, [x7]       // XXX
            \\1: wfe
            \\b 1b

            // Check if we're in EL1 (EDK2 does this for us).
            // If so, go straight to DAINKRNL.
            \\.cpu_zero:
            \\mrs x10, CurrentEL
            \\cmp x10, #0x4
            \\b.ne .not_el1
            \\mov x10, #0x45       // XXX Record progress "E"
            \\strb w10, [x7]       // XXX
            \\br x9

            // Assert we are in EL2.
            \\.not_el1:
            \\cmp x10, #0x8
            \\b.eq .el2
            \\brk #1

            // U-Boot leaves us in EL2. Prepare to eret down to EL1
            // to DAINKRNL.
            \\.el2:

            // Copy our stack.
            \\mov x10, sp
            \\msr sp_el1, x10

            // Don't trap EL0/EL1 accesses to the EL1 physical counter and timer registers.
            \\mrs x10, cnthctl_el2
            \\orr x10, x10, #3
            \\msr cnthctl_el2, x10

            // Reset virtual offset register.
            \\msr cntvoff_el2, xzr

            // Set EL1 execution state to AArch64, not AArch32.
            \\mov x10, #(1 << 31)
            // EL1 execution of DC ISW performs the same invalidation as DC CISW.
            \\orr x10, x10, #(1 << 1)
            \\msr hcr_el2, x10
            \\mrs x10, hcr_el2 // ?

            // Clear hypervisor system trap register.
            \\msr hstr_el2, xzr

            // I saw someone on StackOverflow set this this way.
            // "The CPTR_EL2 controls trapping to EL2 for accesses to CPACR, Trace functionality
            // and registers associated with Advanced SIMD and floating-point execution. It also
            // controls EL2 access to this functionality."
            // This sets TFP to 0, TCPAC to 0, and everything else to RES values.
            \\mov x10, #0x33ff
            \\msr cptr_el2, x10

            // Prepare the simulated exception.
            // Trying EL1t (0x3c4) didn't make a difference in practice.
            \\mov x10, #0x3c5            // DAIF+EL1+h (h = 0b1 = use SP_ELx, not SP0)
            \\msr spsr_el2, x10

            // Prepare the return address.
            \\adr x10, .eret_target
            \\msr elr_el2, x10
            \\mov x10, #0x46       // XXX Record progress "F"
            \\strb w10, [x7]       // XXX

            // Fire.
            \\eret
            \\brk #1               // Should not execute; if it did, U-Boot would say hi.

            // Are we in EL1 yet?
            \\.eret_target:
            \\msr spsel, #1        // Enable our own stack.
            \\br x9
        :
        : [memory_map] "{x0}" (memory_map),
          [memory_map_size] "{x1}" (memory_map_size),
          [descriptor_size] "{x2}" (descriptor_size),
          [conventional_start] "{x3}" (conventional_start),
          [conventional_bytes] "{x4}" (conventional_bytes),
          [fb] "{x5}" (fb),
          [verthoriz] "{x6}" (verthoriz),
          [uart_base] "{x7}" (uart_base),

          [entry] "{x9}" (adjusted_entry)
        : "memory"
    );

    unreachable;
}
