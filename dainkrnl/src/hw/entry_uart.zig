// Minimal UART (write-only) for use during entry phase, before the MMU
// is setup, and main, before we've checked the DTB for details on the
// UART available to us.  The two UARTS we work with both work by just
// writing bytes to their MMIO base address with zero offset.
//
// Because the MMU may be not or partially set up when called, the
// "carefully" variants only work on register values or comptime-known
// strings by default, as loads may fail.  You can use the Escape enum
// to say you really want to do a runtime load of a string.
//
// These are also called from `exception.zig' to report ESR/ELR and regs,
// but it might fail if we've actually set things up correctly. Watch out.
// If `exceptions.zig' is failing, consider inlining `hex' to start with.
const std = @import("std");
const build_options = @import("build_options");

pub var base: ?*volatile u8 = null;

fn busyLoop() void {
    var i: usize = 0;
    const loop_count: usize = if (comptime std.mem.eql(u8, build_options.board, "maixduino")) 200_000 else 100;
    while (i < loop_count) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn carefully(parts: anytype) void {
    carefullyAt(base.?, parts);
}

pub fn hex(n: u64) void {
    const ptr: *volatile u8 = base.?;
    ptr.* = '<';
    busyLoop();

    if (n == 0) {
        ptr.* = '0';
        busyLoop();
        ptr.* = '>';
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
            ptr.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            ptr.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            ptr.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
    ptr.* = '>';
    busyLoop();
}

pub const Escape = enum {
    Runtime,
    Char,
};

pub fn carefullyAt(ptr: *volatile u8, parts: anytype) void {
    comptime var next_escape: ?Escape = null;
    inline for (std.meta.fields(@TypeOf(parts))) |info, i| {
        if (info.field_type == Escape) {
            next_escape = parts[i];
        } else if (next_escape) |escape| {
            next_escape = null;
            switch (escape) {
                .Runtime => writeRuntime(ptr, parts[i]),
                .Char => {
                    ptr.* = parts[i];
                    busyLoop();
                },
            }
        } else if (comptime std.meta.trait.isPtrTo(.Array)(info.field_type) or comptime std.meta.trait.isSliceOf(.Int)(info.field_type)) {
            writeCarefully(ptr, parts[i]);
        } else if (comptime std.meta.trait.isUnsignedInt(info.field_type)) {
            writeCarefully(ptr, "0x");
            writeCarefullyHex(ptr, parts[i]);
        } else {
            @compileError("what do I do with this? " ++ @typeName(info.field_type));
        }
    }
}

fn writeRuntime(ptr: *volatile u8, msg: []const u8) void {
    for (msg) |c| {
        ptr.* = c;
        busyLoop();
    }
}

fn writeCarefully(ptr: *volatile u8, comptime msg: []const u8) void {
    inline for (msg) |c| {
        ptr.* = c;
        busyLoop();
    }
}

fn writeCarefullyHex(ptr: *volatile u8, n: u64) void {
    if (n == 0) {
        ptr.* = '0';
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
