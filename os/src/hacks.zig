const std = @import("std");
const build_options = @import("build_options");

pub var uart_global: ?*volatile u8 = null;

const hack_uart_base: *volatile u8 = @intToPtr(*volatile u8, if (comptime std.mem.eql(u8, build_options.board, "qemu"))
    0x0900_0000
else if (comptime std.mem.eql(u8, build_options.board, "rockpro64"))
    0xff1a_0000
else
    @compileError("hacks: unknown board"));

fn busyLoop() callconv(.Inline) void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn HACK_uart(parts: anytype) callconv(.Inline) void {
    HACK_uartAt(uart_global orelse hack_uart_base, parts);
}

pub fn HACK_uart2(n: u64) void {
    const base: *volatile u8 = uart_global orelse hack_uart_base;
    base.* = '<';
    busyLoop();

    if (n == 0) {
        base.* = '0';
        busyLoop();
        base.* = '>';
        busyLoop();
        return;
    }

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
            base.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            base.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            base.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
    base.* = '>';
    busyLoop();
}

pub const HACK = enum {
    UART_Runtime,
    UART_Char,
};

pub fn HACK_uartAt(base: *volatile u8, parts: anytype) callconv(.Inline) void {
    comptime const parts_info = std.meta.fields(@TypeOf(parts));
    comptime var i = 0;
    comptime var next_hack: ?HACK = null;
    inline while (i < parts_info.len) : (i += 1) {
        if (parts_info[i].field_type == HACK) {
            next_hack = parts[i];
        } else if (next_hack) |hack| {
            next_hack = null;
            switch (hack) {
                .UART_Runtime => HACK_uartWrite(base, parts[i]),
                .UART_Char => {
                    base.* = parts[i];
                    busyLoop();
                },
            }
        } else if (comptime std.meta.trait.isPtrTo(.Array)(parts_info[i].field_type) or comptime std.meta.trait.isSliceOf(.Int)(parts_info[i].field_type)) {
            HACK_uartWriteCarefully(base, parts[i]);
        } else if (comptime std.meta.trait.isUnsignedInt(parts_info[i].field_type)) {
            HACK_uartWriteCarefully(base, "0x");
            HACK_uartWriteCarefullyHex(base, parts[i]);
        } else {
            @compileError("what do I do with this? " ++ @typeName(parts_info[i].field_type));
        }
    }
}

fn HACK_uartWrite(base: *volatile u8, msg: []const u8) callconv(.Inline) void {
    for (msg) |c| {
        base.* = c;
        busyLoop();
    }
}

fn HACK_uartWriteCarefully(base: *volatile u8, comptime msg: []const u8) callconv(.Inline) void {
    inline for (msg) |c| {
        base.* = c;
        busyLoop();
    }
}

fn HACK_uartWriteCarefullyHex(base: *volatile u8, n: u64) callconv(.Inline) void {
    if (n == 0) {
        base.* = '0';
        busyLoop();
        return;
    }

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
            base.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            base.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            base.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
}
