const std = @import("std");
const uefi = std.os.uefi;

pub var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;

pub fn puts(msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2]u16{ c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    puts(std.fmt.bufPrint(buf[0..], format, args) catch @panic("printf"));
}

pub fn haltMsg(comptime msg: []const u8) noreturn {
    puts("halted: " ++ msg ++ "\r\n");
    halt();
}

pub fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}

pub fn check(comptime method: []const u8, result: uefi.Status) void {
    if (result != .Success) {
        puts(method ++ " failed: ");
        puts(@tagName(result));
        puts("\r\nhalted");
        halt();
    }
}
