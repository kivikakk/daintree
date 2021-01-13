const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");

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
    while (true) {}
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
            var size: u64 = undefined;
            check("getPosition", dainkrnl_proto.getPosition(&size));
            printf(buf[0..], " {} bytes\r\n", .{size});

            check("setPosition", dainkrnl_proto.setPosition(0));

            var dainkrnl: [*]u8 = undefined;
            check("allocatePool", boot_services.allocatePool(
                .BootServicesData,
                size,
                @ptrCast(*[*]align(8) u8, &dainkrnl),
            ));
            check("read", dainkrnl_proto.read(&size, dainkrnl));

            if (size < @sizeOf(std.elf.Elf64_Ehdr)) {
                printf(buf[0..], "found {} byte(s), too small for ELF header ({} bytes)\r\n", .{ size, @sizeOf(std.elf.Elf64_Ehdr) });
                end();
            }

            var hdr_buf: [@sizeOf(std.elf.Elf64_Ehdr)]u8 align(@alignOf(std.elf.Elf64_Ehdr)) = undefined;
            std.mem.copy(u8, &hdr_buf, dainkrnl[0..@sizeOf(std.elf.Elf64_Ehdr)]);

            const elf_header = std.elf.parseHeader(&hdr_buf) catch |err| {
                printf(buf[0..], "failed to parse ELF: {}\r\n", .{err});
                end();
            };

            printf(buf[0..], "ELF entry: {x:0>16}", .{elf_header.entry});
        }

        _ = boot_services.closeProtocol(handle, &uefi.protocols.SimpleFileSystemProtocol.guid, uefi.handle, null);
    }

    exitBootServices();
}

fn exitBootServices() void {
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
        if (boot_services.allocatePool(
            uefi.tables.MemoryType.BootServicesData,
            memory_map_size,
            @ptrCast(*[*]align(8) u8, &memory_map),
        ) != .Success) {
            puts("failed to allocatePool\r\n");
            return;
        }
    }

    if (boot_services.exitBootServices(uefi.handle, memory_map_key) != .Success) {
        puts("failed to exitBootServices\r\n");
        return;
    }

    while (true) {}
}
