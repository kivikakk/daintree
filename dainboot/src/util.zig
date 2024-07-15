const std = @import("std");
const uefi = std.os.uefi;
const arch = @import("arch.zig");

pub var con_out: *uefi.protocol.SimpleTextOutput = undefined;

pub fn puts(msg: []const u8) void {
    for (msg) |c| {
        // https://github.com/ziglang/zig/issues/4372
        _ = con_out.outputString(&[2:0]u16{ c, 0 });
    }
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    puts(std.fmt.bufPrint(buf[0..], format, args) catch @panic("printf"));
}

pub fn haltMsg(comptime msg: []const u8) noreturn {
    puts("halted: " ++ msg ++ "\r\n");
    arch.halt();
}

pub fn check(comptime method: []const u8, result: uefi.Status) void {
    if (result != .Success) {
        puts(method ++ " failed: ");
        puts(@tagName(result));
        puts("\r\nhalted");
        arch.halt();
    }
}
