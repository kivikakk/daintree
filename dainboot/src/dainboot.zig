const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const uefi = std.os.uefi;
const build_options = @import("build_options");
const dtblib = @import("dtb");
const ddtb = @import("common/ddtb.zig");
const arch = @import("arch.zig");

usingnamespace @import("util.zig");

var boot_services: *uefi.tables.BootServices = undefined;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    printf("panic: {s}\r\n", .{msg});
    arch.halt();
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

    if (load_context.dtb == null) {
        load_context.searchEfiFdt();
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

    var fdt_table_guid align(8) = std.os.uefi.Guid{
        .time_low = 0xb1b621d5,
        .time_mid = 0xf19c,
        .time_high_and_version = 0x41a5,
        .clock_seq_high_and_reserved = 0x83,
        .clock_seq_low = 0x0b,
        .node = [_]u8{ 0xd9, 0x15, 0x2c, 0x69, 0xaa, 0xe0 },
    };

    fn searchEfiFdt(self: *Self) void {
        for (uefi.system_table.configuration_table[0..uefi.system_table.number_of_table_entries]) |table| {
            if (table.vendor_guid.eql(fdt_table_guid)) {
                if (dtblib.totalSize(table.vendor_table)) |size| {
                    printf("found FDT in UEFI\n", .{});
                    self.dtb = @ptrCast([*]const u8, table.vendor_table)[0..size];
                    return;
                } else |err| {}
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

fn parseElf(bytes: []const u8) std.elf.Header {
    if (bytes.len < @sizeOf(std.elf.Elf64_Ehdr)) {
        printf("found {} byte(s), too small for ELF header ({} bytes)\r\n", .{ bytes.len, @sizeOf(std.elf.Elf64_Ehdr) });
        arch.halt();
    }

    var buffer = std.io.fixedBufferStream(bytes);
    var elf_header = std.elf.Header.read(&buffer) catch |err| {
        printf("failed to parse ELF: {}\r\n", .{err});
        arch.halt();
    };

    const bits: u8 = if (elf_header.is_64) 64 else 32;
    const endian_ch = if (elf_header.endian == .Big) @as(u8, 'B') else @as(u8, 'L');
    printf("ELF entrypoint: {x:0>16} ({}-bit {c}E)\r\n", .{
        elf_header.entry,
        bits,
        endian_ch,
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
            if (phdr.p_type == std.elf.PT_LOAD) {
                const target = phdr.p_vaddr - dcommon.daintree_kernel_start;
                const load_bytes = std.math.min(phdr.p_filesz, phdr.p_memsz);
                printf("will load 0x{x:0>16} bytes at 0x{x:0>16} into offset+0x{x:0>16}\r\n", .{ load_bytes, phdr.p_vaddr, target });
                if (phdr.p_memsz > phdr.p_filesz) {
                    printf("  and zeroing {} bytes at end\r\n", .{phdr.p_memsz - phdr.p_filesz});
                }
                kernel_size = std.math.max(kernel_size, target + phdr.p_memsz);
            }
        }
    }

    var fb: ?[*]u32 = null;
    var fb_vert: u32 = 0;
    var fb_horiz: u32 = 0;
    {
        var graphics: *uefi.protocols.GraphicsOutputProtocol = undefined;
        const result = boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics));
        if (result == .Success) {
            fb = @intToPtr([*]u32, graphics.mode.frame_buffer_base);
            fb_vert = graphics.mode.info.vertical_resolution;
            fb_horiz = graphics.mode.info.horizontal_resolution;
            printf("{}x{} framebuffer located at {*}\n", .{ fb_horiz, fb_vert, fb });
        } else {
            printf("no framebuffer found: {}\n", .{result});
        }
    }

    var dtb_scratch_ptr: [*]u8 = undefined;
    check("allocatePool", boot_services.allocatePool(uefi.tables.MemoryType.BootServicesData, 128 * 1024, @ptrCast(*[*]align(8) u8, &dtb_scratch_ptr)));
    var dtb_scratch = dtb_scratch_ptr[0 .. 128 * 1024];

    printf("looking up serial base in DTB ... ", .{});
    var uart_base: u64 = 0;
    if (ddtb.searchForUart(dtb)) |uart| {
        uart_base = uart.base;
    } else |err| {
        printf("failed to parse dtb: {}", .{err});
    }
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
    ) == .BufferTooSmall) {
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

    // The kernel's text section begins at dcommon.daintree_kernel_start. Adjust those down
    // to conventional_start now.

    var it = dainkrnl_elf.program_header_iterator(&elf_source);
    while (it.next() catch haltMsg("iterating phdrs (2)")) |phdr| {
        if (phdr.p_type == std.elf.PT_LOAD) {
            const target = phdr.p_vaddr - dcommon.daintree_kernel_start + conventional_start;
            std.mem.copy(u8, @intToPtr([*]u8, target)[0..phdr.p_filesz], dainkrnl[phdr.p_offset .. phdr.p_offset + phdr.p_filesz]);
            if (phdr.p_memsz > phdr.p_filesz) {
                std.mem.set(u8, @intToPtr([*]u8, target)[phdr.p_filesz..phdr.p_memsz], 0);
            }
        }
    }

    entry_data = .{
        .memory_map = memory_map,
        .memory_map_size = memory_map_size,
        .descriptor_size = descriptor_size,
        .dtb_ptr = dtb.ptr,
        .dtb_len = dtb.len,
        .conventional_start = conventional_start,
        .conventional_bytes = conventional_bytes,
        .fb = fb,
        .fb_vert = fb_vert,
        .fb_horiz = fb_horiz,
        .uart_base = uart_base,
    };

    arch.cleanInvalidateDCacheICache(@ptrToInt(&entry_data), @sizeOf(@TypeOf(entry_data)));
    // I'd love to change this back to "..., kernel_size);" at some point.
    arch.cleanInvalidateDCacheICache(conventional_start, conventional_bytes);

    printf("{x} {x} ", .{ conventional_start, @ptrToInt(&entry_data) });

    const adjusted_entry = dainkrnl_elf.entry - dcommon.daintree_kernel_start + conventional_start;

    check("exitBootServices", boot_services.exitBootServices(uefi.handle, memory_map_key));

    if (fb) |base| {
        var x: usize = 0;
        while (x < 16) : (x += 1) {
            var y: usize = 0;
            while (y < 16) : (y += 1) {
                base[y * fb_horiz + x] = 0x0000ff00;
            }
        }
    }

    arch.transfer(&entry_data, uart_base, adjusted_entry);
}

var entry_data: dcommon.EntryData align(16) = undefined;
