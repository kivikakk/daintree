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
        if (boot_services.allocatePool(
            uefi.tables.MemoryType.BootServicesData,
            handle_list_size,
            @ptrCast(*[*]align(8) u8, &handle_list),
        ) != .Success) {
            puts("failed to allocatePool\r\n");
            end();
        }
    }

    if (handle_list_size == 0) {
        puts("no simple file system protocols found\r\n");
        end();
    }

    const handle_count = handle_list_size / @sizeOf(uefi.Handle);

    printf(buf[0..], "searching for DAINKRNL on {} volume(s) ", .{handle_count});

    for (handle_list[0..handle_count]) |handle| {
        var sfs_proto: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;

        if (boot_services.openProtocol(
            handle,
            &uefi.protocols.SimpleFileSystemProtocol.guid,
            @ptrCast(*?*c_void, &sfs_proto),
            uefi.handle,
            null,
            .{ .get_protocol = true },
        ) != .Success) {
            puts("\r\nerror calling openProtocol\r\n");
            end();
        }

        puts(".");

        var f_proto: *uefi.protocols.FileProtocol = undefined;
        if (sfs_proto.?.openVolume(&f_proto) != .Success) {
            puts("\r\nerror calling openVolume\r\n");
            end();
        }

        var dainkrnl_proto: *uefi.protocols.FileProtocol = undefined;
        if (f_proto.open(&dainkrnl_proto, &[_:0]u16{ 'd', 'a', 'i', 'n', 'k', 'r', 'n', 'l' }, uefi.protocols.FileProtocol.efi_file_mode_read, 0) == .Success) {
            _ = dainkrnl_proto.setPosition(uefi.protocols.FileProtocol.efi_file_position_end_of_file);
            var position: u64 = undefined;
            if (dainkrnl_proto.getPosition(&position) != .Success) {
                puts("\r\ngetPosition failed\r\n");
                end();
            }
            printf(buf[0..], " {} bytes\r\n", .{position});
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
