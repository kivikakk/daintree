const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");
const elf = @import("elf.zig");

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var boot_services: *uefi.tables.BootServices = undefined;

fn puts(msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2]u16{ c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

fn printf(buf: []u8, comptime format: []const u8, args: anytype) void {
    puts(std.fmt.bufPrint(buf, format, args) catch unreachable);
}

fn end() noreturn {
    puts("halted\r\n");
    halt();
}

fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}

fn check(comptime method: []const u8, result: uefi.Status) void {
    if (result != .Success) {
        puts(method ++ " failed\r\n");
        end();
    }
}

pub fn main() void {
    con_out = uefi.system_table.con_out.?;
    boot_services = uefi.system_table.boot_services.?;
    var buf: [256]u8 = undefined;

    printf(buf[0..], "daintree bootloader ({s})\r\n", .{build_options.version});

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
        puts("no simple file system protocols found\r\n");
        end();
    }

    const handle_count = handle_list_size / @sizeOf(uefi.Handle);

    printf(buf[0..], "searching for DAINKRNL on {} volume(s) ", .{handle_count});
    var dainkrnl: [*]u8 = undefined;
    var dainkrnl_size: u64 = undefined;
    var dainkrnl_elf: ?elf.Header = null;

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

        puts(".");

        var f_proto: *uefi.protocols.FileProtocol = undefined;
        check("openVolume", sfs_proto.?.openVolume(&f_proto));

        var dainkrnl_proto: *uefi.protocols.FileProtocol = undefined;
        if (f_proto.open(&dainkrnl_proto, &[_:0]u16{ 'd', 'a', 'i', 'n', 'k', 'r', 'n', 'l' }, uefi.protocols.FileProtocol.efi_file_mode_read, 0) == .Success) {
            check("setPosition", dainkrnl_proto.setPosition(uefi.protocols.FileProtocol.efi_file_position_end_of_file));
            check("getPosition", dainkrnl_proto.getPosition(&dainkrnl_size));
            printf(buf[0..], " {} bytes\r\n", .{dainkrnl_size});

            check("setPosition", dainkrnl_proto.setPosition(0));

            check("allocatePool", boot_services.allocatePool(
                .BootServicesData,
                dainkrnl_size,
                @ptrCast(*[*]align(8) u8, &dainkrnl),
            ));
            check("read", dainkrnl_proto.read(&dainkrnl_size, dainkrnl));

            if (dainkrnl_size < @sizeOf(elf.Elf64_Ehdr)) {
                printf(buf[0..], "found {} byte(s), too small for ELF header ({} bytes)\r\n", .{ dainkrnl_size, @sizeOf(elf.Elf64_Ehdr) });
                end();
            }

            var elf_buffer = std.io.fixedBufferStream(dainkrnl[0..dainkrnl_size]);
            dainkrnl_elf = elf.Header.read(&elf_buffer) catch |err| {
                printf(buf[0..], "failed to parse ELF: {}\r\n", .{err});
                end();
            };

            printf(buf[0..], "ELF entrypoint: {x:0>16}\r\n", .{dainkrnl_elf.?.entry});
            printf(buf[0..], "{}-bit ({c}E)\r\n", .{
                @as(u8, if (dainkrnl_elf.?.is_64) 64 else 32),
                @as(u8, if (dainkrnl_elf.?.endian == .Big) 'B' else 'L'),
            });
            var it = dainkrnl_elf.?.program_header_iterator(&elf_buffer);
            while (it.next() catch {
                end();
            }) |phdr| {
                printf(buf[0..], " * type={x:0>8} off={x:0>16} vad={x:0>16} pad={x:0>16} fsz={x:0>16} msz={x:0>16}\r\n", .{ phdr.p_type, phdr.p_offset, phdr.p_vaddr, phdr.p_paddr, phdr.p_filesz, phdr.p_memsz });
            }
        }

        _ = boot_services.closeProtocol(handle, &uefi.protocols.SimpleFileSystemProtocol.guid, uefi.handle, null);
        if (dainkrnl_elf != null) {
            break;
        }
    }

    if (dainkrnl_elf) |found| {
        exitBootServices(dainkrnl, dainkrnl_size, found);
    }

    puts("\r\nDAINKRNL not found\r\n");
    _ = boot_services.stall(5 * 1000 * 1000);
}

// ref Figure D5-15
fn PageTableEntry_u64(pte: PageTableEntry) u64 {
    return @as(u64, pte.valid) |
        (@as(u64, @enumToInt(pte.type)) << 1) |
        (@as(u64, pte.lba.attr_indx) << 2) |
        (@as(u64, pte.lba.ns) << 5) |
        (@as(u64, pte.lba.ap) << 6) |
        (@as(u64, pte.lba.sh) << 8) |
        (@as(u64, pte.lba.af) << 10) |
        (@as(u64, pte.oa) << 29) |
        (@as(u64, pte.uba.pxn) << 53) |
        (@as(u64, pte.uba.uxn) << 54);
}

const PageTableEntry = struct {
    valid: u1 = 1,
    type: enum(u1) {
        block = 0,
        table = 1,
    } = .block,
    lba: struct {
        attr_indx: u3 = 0,
        ns: u1 = 0,
        ap: u2 = 0b00, // R/W, EL0 access denied
        sh: u2 = 0b11, // inner shareable
        af: u1 = 0b1, // access flag (?)
        // ng: u1 = 0, // ??
    } = .{},
    // _res0a: u4 = 0, // OA[51:48]
    // _res0b: u1 = 0, // nT
    // _res0c: u12 = 0,
    oa: u19, // OA[47:29]
    // _res0d: u4 = 0,
    uba: struct {
        // contiguous: u1 = 0,
        pxn: u1 = 0,
        uxn: u1 = 1,
        // _resa: u4 = 0,
        // _res0b: u4 = 0,
        // _resb: u1 = 0,
    } = .{},
};

fn TCR_EL1_u64(tcr: TCR_EL1) u64 {
    return @as(u64, tcr.t0sz) |
        (@as(u64, tcr.epd0) << 7) |
        (@as(u64, tcr.irgn0) << 8) |
        (@as(u64, tcr.orgn0) << 10) |
        (@as(u64, tcr.sh0) << 12) |
        (@as(u64, @enumToInt(tcr.tg0)) << 14) |
        (@as(u64, tcr.t1sz) << 16) |
        (@as(u64, tcr.a1) << 22) |
        (@as(u64, tcr.epd1) << 23) |
        (@as(u64, tcr.irgn1) << 24) |
        (@as(u64, tcr.orgn1) << 26) |
        (@as(u64, tcr.sh1) << 28) |
        (@as(u64, @enumToInt(tcr.tg1)) << 30) |
        (@as(u64, @enumToInt(tcr.ips)) << 32);
}

const TCR_EL1 = struct {
    t0sz: u6 = 25, // TTBR0_EL1 addresses 2**(64-25)
    // _res0a: u1 = 0,
    epd0: u1 = 0, // enable TTBR0_EL1 walks (set = 1 to *disable*)
    irgn0: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn0: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh0: u2 = 0b11, // inner-shareable
    tg0: enum(u2) {
        K4 = 0b00,
        K16 = 0b10,
        K64 = 0b01,
    } = .K4,
    t1sz: u6 = 25, // TTBR1_EL1 addresses 2**(64-25): 0xffffff80_00000000
    a1: u1 = 0, // TTBR0_EL1.ASID defines the ASID
    epd1: u1 = 0, // enable TTBR1_EL1 walks (set = 1 to *disable*)
    irgn1: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn1: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh1: u2 = 0b11, // inner-shareable
    tg1: enum(u2) { // granule size for TTBR1_EL1
        K4 = 0b10,
        K16 = 0b01,
        K64 = 0b11,
    } = .K4,
    ips: enum(u3) {
        B32 = 0b000,
        B36 = 0b001,
        B48 = 0b101,
    } = .B36,
    // _res0b: u1 = 0,
    // _as: u1 = 0,
    // tbi0: u1 = 0, // top byte ignored
    // tbi1: u1 = 0,
    // _ha: u1 = 0,
    // _hd: u1 = 0,
    // _hpd0: u1 = 0,
    // _hpd1: u1 = 0,
    // _hwu: u8 = 0,
    // _tbid0: u1 = 0,
    // _tbid1: u1 = 0,
    // _nfd0: u1 = 0,
    // _nfd1: u1 = 0,
    // _res0c: u9 = 0,
};

comptime {
    if (@bitSizeOf(PageTableEntry) != 64) {
        // @compileLog("PageTableEntry misshapen; ", @bitSizeOf(PageTableEntry));
    }
    if (@sizeOf(PageTableEntry) != 8) {
        // @compileLog("PageTableEntry misshapen; ", @sizeOf(PageTableEntry));
    }

    if (@bitSizeOf(TCR_EL1) != 64) {
        // @compileLog("TCR_EL1 misshapen; ", @bitSizeOf(TCR_EL1));
    }
}

fn exitBootServices(dainkrnl: [*]u8, dainkrnl_size: u64, dainkrnl_elf: elf.Header) noreturn {
    var graphics: *uefi.protocols.GraphicsOutputProtocol = undefined;
    check("locateProtocol", boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics)));
    var fb: [*]u8 = @intToPtr([*]u8, graphics.mode.frame_buffer_base);

    var buf: [256]u8 = undefined;

    var page_table_0: [*]u64 align(0x1000) = undefined;
    var page_table_1: [*]u64 align(0x1000) = undefined;
    check("allocatePages", boot_services.allocatePages(.AllocateAnyPages, .LoaderData, 16, @ptrCast(*[*]align(4096) u8, &page_table_0)));
    printf(buf[0..], "allocated 16x4KiB pages at 0x{x:0>16} for page table 0\r\n", .{page_table_0});
    check("allocatePages", boot_services.allocatePages(.AllocateAnyPages, .LoaderData, 16, @ptrCast(*[*]align(4096) u8, &page_table_1)));
    printf(buf[0..], "allocated 16x4KiB pages at 0x{x:0>16} for page table 1\r\n", .{page_table_1});
    {
        var i: u14 = 0;
        while (i < 8192) : (i += 1) {
            page_table_0[0..8192][i] = PageTableEntry_u64(.{
                .oa = i, // 512MB increments
            });
            page_table_1[0..8192][i] = PageTableEntry_u64(.{ .oa = i });

            if (i < 2) {
                printf(buf[0..], "i{}: {x:0>16}\r\n", .{ i, page_table_0[0..8192][i] });
            }
        }
    }

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

    for (memory_map[0 .. memory_map_size / descriptor_size]) |ptr, i| {
        printf(buf[0..], "{:3} {s:23} p=0x{x:0>16} size={:16}\r\n", .{ i, @tagName(ptr.type), ptr.physical_start, ptr.number_of_pages << 12 });
    }

    // LET THE HACKS BEGIN

    // We ask the linker to put text at 0x40000000 (1GiB), which happens to be
    // where QEMU's situated physical memory.  Copy blindly all PT_LOAD sections:
    //
    // searching for DAINKRNL on 2 volume(s) .FSOpen: Open 'dainkrnl' Success
    //  86784 bytes
    // ELF entrypoint: 000000004000001c
    // 64-bit (BE)
    //  * type=00000001 off=0000000000010000 vad=0000000040000000 pad=0000000040000000 fsz=0000000000000270 msz=0000000000000270
    //  * type=00000001 off=0000000000011000 vad=0000000040001000 pad=0000000040001000 fsz=00000000000001d6 msz=00000000000001d6
    //  * type=6474e551 off=0000000000000000 vad=0000000000000000 pad=0000000000000000 fsz=0000000000000000 msz=0000000001000000

    var elf_source = std.io.fixedBufferStream(dainkrnl[0..dainkrnl_size]);
    var it = dainkrnl_elf.program_header_iterator(&elf_source);
    while (it.next() catch {
        puts("bad\r\n");
        halt();
    }) |phdr| {
        if (phdr.p_type == elf.PT_LOAD) {
            const target = phdr.p_vaddr; //- 0xffff000000000000 + 0x40000000;
            printf(buf[0..], "loading {} bytes at 0x{x:0>16} into 0x{x:0>16}\r\n", .{ phdr.p_filesz, phdr.p_vaddr, target });
            std.mem.copy(u8, @intToPtr([*]u8, target)[0..phdr.p_filesz], dainkrnl[phdr.p_offset .. phdr.p_offset + phdr.p_filesz]);
            // zero-extend up to p_memsz if needed
        }
    }

    const target = @intToPtr([*]u8, dainkrnl_elf.entry + 8)[0..4]; // - 0xffff000000000000 + 0x40000000)[0..4];
    printf(buf[0..], "we will execute: {x:0>2} {x:0>2} {x:0>2} {x:0>2}\r\n", .{ target[0], target[1], target[2], target[3] });

    const tcr_el1 = TCR_EL1_u64(.{});
    printf(buf[0..], "TCR_EL: {x:0>16}\r\n", .{tcr_el1});

    check("exitBootServices", boot_services.exitBootServices(uefi.handle, memory_map_key));

    // Looks like we're left in EL1. (mrs x2, CurrentEL => x2 = 0x4; PSTATE[3:2] = 0x4 -> EL1)

    asm volatile (
    // Reset these registers since EDK2 gets in a loop when dumping CPU on crash.
        \\mov x29, #0
        \\mov x30, #0
        \\.equ SCR_EL3_VALUE, 0x05B1
        \\.equ SPSR_EL3_VALUE, 0x03C9

        // Set up MMU.
        // XXX: screw it, just disable the MMU.
        \\mrs x0, sctlr_el1
        \\bic x0, x0, #1
        \\msr sctlr_el1, x0
        \\isb
        \\mov x0, x5
        \\br x4
        :
        : [ttbr0_el1] "{x0}" (@ptrToInt(page_table_0) | 1),
          [ttbr1_el1] "{x1}" (@ptrToInt(page_table_1) | 1),
          [tcr_el1] "{x2}" (tcr_el1),
          [mair_el1] "{x3}" (@as(u64, 0xFF)),
          [entry] "{x4}" (dainkrnl_elf.entry + 8),
          [fb] "{x5}" (fb)
        : "memory"
    );

    unreachable;
}
