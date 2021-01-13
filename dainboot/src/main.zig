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

pub fn main() void {
    con_out = uefi.system_table.con_out.?;

    puts("daintree bootloader (");
    puts(build_options.version);
    puts(")\r\n");
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
}