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

pub fn main() void {
    con_out = uefi.system_table.con_out.?;
    boot_services = uefi.system_table.boot_services.?;
    var buf: [256]u8 = undefined;

    printf(buf[0..], "daintree bootloader ({s})\r\n", .{build_options.version});

    var sfs_proto: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;
    if (boot_services.locateProtocol(
        &uefi.protocols.SimpleFileSystemProtocol.guid,
        null,
        @ptrCast(*?*c_void, &sfs_proto),
    ) != .Success) {
        puts("couldn't load simple filesystem protocol\r\n");
        return;
    }

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
            return;
        }
    }

    //   sfs_proto.?.openVolume(root: **const FileProtocol)

    printf(buf[0..], "searching for DAINKRNL ({}) ", .{handle_list_size});

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
