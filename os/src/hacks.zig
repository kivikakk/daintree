const std = @import("std");
const build_options = @import("build_options");

const uart: *volatile u8 = @intToPtr(*volatile u8, if (comptime std.mem.eql(u8, build_options.board, "qemu"))
    0x0900_0000
else if (comptime std.mem.eql(u8, build_options.board, "rockpro64"))
    0xff1a_0000
else
    @compileError("hacks: unknown board"));

fn busyLoop() callconv(.Inline) void {
    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn HACK_uartWriteCarefully(comptime msg: []const u8) callconv(.Inline) void {
    inline for (msg) |c| {
        uart.* = c;
        busyLoop();
    }
}

pub fn HACK_uartWriteCarefullyHex(n: u64) callconv(.Inline) void {
    var digits: usize = 0;
    var c = n;
    while (c > 0) : (c /= 16) {
        digits += 1;
    }
    c = n;
    var pow: usize = std.math.powi(u64, 16, digits - 1) catch 0;
    while (pow > 0) : (pow /= 16) {
        var digit = c / pow;
        if (digit >= 0 and digit <= 9) {
            uart.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            uart.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            uart.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
}
