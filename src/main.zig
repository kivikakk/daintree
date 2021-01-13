const std = @import("std");
const uefi = std.os.uefi;

pub fn main() void {
    const con_out = uefi.system_table.con_out.?;
    _ = con_out.reset(false);
    _ = con_out.outputString(&[_:0]u16{ 'd', 'a', 'i', 'n', 't', 'r', 'e', 'e', '\r', '\n' });
    _ = uefi.system_table.boot_services.?.stall(5 * 1000 * 1000);
}
