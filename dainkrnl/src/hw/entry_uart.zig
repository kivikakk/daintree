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
//
// Note we need to permit both u8 and u32 writes.  The sifive,uart0 MMIO
// causes a CPU fault if you try to do a byte-sized write to it.  Boo.
const std = @import("std");
const build_options = @import("build_options");
const dcommon = @import("../common/dcommon.zig");

pub var base: ?u64 = null;
pub var width: ?u3 = null;

pub fn init(entry_data: *dcommon.EntryData) void {
    base = entry_data.uart_base;
    width = entry_data.uart_width;

    carefully(.{ "\r\n\r\ndainkrnl ", build_options.version, " pre-MMU stage on ", build_options.board, "\r\n" });

    carefully(.{ "entry_data (", @ptrToInt(entry_data), ")\r\n" });
    carefully(.{ "memory_map:         ", @ptrToInt(entry_data.memory_map), "\r\n" });
    carefully(.{ "memory_map_size:    ", entry_data.memory_map_size, "\r\n" });
    carefully(.{ "descriptor_size:    ", entry_data.descriptor_size, "\r\n" });
    carefully(.{ "dtb_ptr:            ", @ptrToInt(entry_data.dtb_ptr), "\r\n" });
    carefully(.{ "dtb_len:            ", entry_data.dtb_len, "\r\n" });
    carefully(.{ "conventional_start: ", entry_data.conventional_start, "\r\n" });
    carefully(.{ "conventional_bytes: ", entry_data.conventional_bytes, "\r\n" });
    carefully(.{ "fb:                 ", @ptrToInt(entry_data.fb), "\r\n" });
    carefully(.{ "fb_vert:            ", entry_data.fb_vert, "\r\n" });
    carefully(.{ "fb_horiz:           ", entry_data.fb_horiz, "\r\n" });
    carefully(.{ "uart_base:          ", entry_data.uart_base, "\r\n" });
}

const Writer = struct {
    base: u64,
    width: u3,

    fn w(self: Writer, c: u8) void {
        switch (self.width) {
            1 => @intToPtr(*volatile u8, self.base).* = c,
            4 => @intToPtr(*volatile u32, self.base).* = c,
            else => unreachable,
        }
    }
};

fn writerFor(b: u64, w: u3) Writer {
    return .{ .base = b, .width = w };
}

fn busyLoop() void {
    var i: usize = 0;
    const loop_count: usize = 100;
    while (i < loop_count) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn carefully(parts: anytype) void {
    carefullyAt(writerFor(base.?, width.?), parts);
}

pub fn hex(n: u64) void {
    const writer = writerFor(base.?, width.?);
    writer.w('<');
    busyLoop();

    if (n == 0) {
        writer.w('0');
        busyLoop();
        writer.w('>');
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
            writer.w('0' + @truncate(u8, digit));
        } else if (digit >= 10 and digit <= 16) {
            writer.w('a' + @truncate(u8, digit) - 10);
        } else {
            writer.w('?');
        }
        busyLoop();
        c -= (digit * pow);
    }
    writer.w('>');
    busyLoop();
}

pub const Escape = enum {
    Runtime,
    Char,
};

fn carefullyAt(writer: Writer, parts: anytype) void {
    comptime var next_escape: ?Escape = null;
    inline for (std.meta.fields(@TypeOf(parts)), 0..) |info, i| {
        if (info.type == Escape) {
            next_escape = parts[i];
        } else if (next_escape) |escape| {
            next_escape = null;
            switch (escape) {
                .Runtime => writeRuntime(writer, parts[i]),
                .Char => {
                    writer.w(parts[i]);
                    busyLoop();
                },
            }
        } else if (comptime std.meta.trait.isPtrTo(.Array)(info.type) or std.meta.trait.isSliceOf(.Int)(info.type)) {
            writeCarefully(writer, parts[i]);
        } else if (comptime std.meta.trait.isUnsignedInt(info.type)) {
            writeCarefully(writer, "0x");
            writeCarefullyHex(writer, parts[i]);
        } else if (comptime std.meta.trait.is(.Optional)(info.type)) {
            writeCarefully(writer, "OPTIONAL THING");
        } else {
            @compileError("what do I do with this? " ++ @typeName(info.type));
        }
    }
}

fn writeRuntime(writer: Writer, msg: []const u8) void {
    for (msg) |c| {
        writer.w(c);
        busyLoop();
    }
}

fn writeCarefully(writer: Writer, comptime msg: []const u8) void {
    inline for (msg) |c| {
        writer.w(c);
        busyLoop();
    }
}

fn writeCarefullyHex(writer: Writer, n: u64) void {
    if (n == 0) {
        writer.w('0');
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
            writer.w('0' + @truncate(u8, digit));
        } else if (digit >= 10 and digit <= 16) {
            writer.w('a' + @truncate(u8, digit) - 10);
        } else {
            writer.w('?');
        }
        busyLoop();
        c -= (digit * pow);
    }
}
