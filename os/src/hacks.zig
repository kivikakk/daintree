const std = @import("std");
const build_options = @import("build_options");

const uart: u64 = if (comptime std.mem.eql(u8, build_options.board, "qemu"))
    0x0900_0000
else if (comptime std.mem.eql(u8, build_options.board, "rockpro64"))
    0xff1a_0000
else
    @compileError("hacks: unknown board");

fn busyLoop() callconv(.Inline) void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn HACK_uart(parts: anytype) callconv(.Inline) void {
    HACK_uartAt(uart, parts);
}

pub fn HACK_uartAt(addr: u64, parts: anytype) callconv(.Inline) void {
    const ptr = @intToPtr(*volatile u8, addr);
    const parts_info = std.meta.fields(@TypeOf(parts));
    comptime var i = 0;
    inline while (i < parts_info.len) : (i += 1) {
        if (comptime std.meta.trait.isPtrTo(.Array)(parts_info[i].field_type) or comptime std.meta.trait.isSliceOf(.Int)(parts_info[i].field_type)) {
            HACK_uartWriteCarefully(ptr, parts[i]);
        } else if (comptime std.meta.trait.isUnsignedInt(parts_info[i].field_type)) {
            HACK_uartWriteCarefully(ptr, "0x");
            HACK_uartWriteCarefullyHex(ptr, parts[i]);
        } else {
            @compileError("what do I do with this? " ++ @typeName(parts_info[i].field_type));
        }
    }
}

fn HACK_uartWriteCarefully(ptr: *volatile u8, comptime msg: []const u8) callconv(.Inline) void {
    inline for (msg) |c| {
        ptr.* = c;
        busyLoop();
    }
}

fn HACK_uartWriteCarefullyHex(ptr: *volatile u8, n: u64) callconv(.Inline) void {
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
            ptr.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            ptr.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            ptr.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
}
