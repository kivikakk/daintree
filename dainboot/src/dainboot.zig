const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;

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
    const boot_services = uefi.system_table.boot_services.?;
    var buf: [256]u8 = undefined;

    printf(buf[0..], "daintree bootloader ({s})\r\n", .{build_options.version});

    var graphics: *uefi.protocols.GraphicsOutputProtocol = undefined;
    if (uefi.Status.Success != boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics))) {
        return;
    }
    var fb: [*]u8 = @intToPtr([*]u8, graphics.mode.frame_buffer_base);

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
        ) != uefi.Status.Success) {
            puts("failed to allocatePool\r\n");
            return;
        }
    }

    if (uefi.Status.Success != boot_services.exitBootServices(uefi.handle, memory_map_key)) {
        puts("failed to exitBootServices\r\n");
        return;
    }

    // We may still use the frame buffer!

    // draw some colors
    var j: u32 = 0;
    while (j < 640 * 480 * 4) : (j += 4) {
        fb[j] = @truncate(u8, @divTrunc(j, 256));
        fb[j + 1] = @truncate(u8, @divTrunc(j, 1536));
        fb[j + 2] = @truncate(u8, @divTrunc(j, 2560));
    }

    while (true) {}
}
