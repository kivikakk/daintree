const std = @import("std");
const font = @import("font.zig");
const arch = @import("../arch.zig");
const hw = @import("../hw.zig");
const paging = @import("../paging.zig");

pub const CONSOLE_DIMENSION = u16;

var fb: ?[*]u32 = null;
var fb_vert: u32 = undefined;
var fb_horiz: u32 = undefined;

pub var console_height: CONSOLE_DIMENSION = undefined;
pub var console_width: CONSOLE_DIMENSION = undefined;

// These are only used in calculating the size of console_buf we should allocate.
// Feel free to increase for a larger HDMI screen.
const MAX_CONSOLE_WIDTH = 1024;
const MAX_CONSOLE_HEIGHT = 600;
var console_buf: [(MAX_CONSOLE_WIDTH / font.FONT_WIDTH) * (MAX_CONSOLE_HEIGHT / font.FONT_HEIGHT)]u16 = undefined;

var console_col: CONSOLE_DIMENSION = 0;
var console_row: CONSOLE_DIMENSION = 0;
var console_colour: u8 = 0x07;

pub fn init(in_fb: [*]u32, in_vert: u32, in_horiz: u32) void {
    fb = mapFb(in_fb, in_vert * in_horiz);
    fb_vert = in_vert;
    fb_horiz = in_horiz;

    console_height = @as(CONSOLE_DIMENSION, @truncate(fb_vert / font.FONT_HEIGHT));
    console_width = @as(CONSOLE_DIMENSION, @truncate(fb_horiz / font.FONT_WIDTH));
    if (console_height * console_width > console_buf.len) {
        @panic("can't fit console");
    }
    @memset(console_buf[0 .. console_width * console_height], 0);
    @memset(fb.?[0 .. fb_horiz * fb_vert], 0);

    arch.sleep(500);
    drawEnergyStar(false);
    arch.sleep(50);
    drawEnergyStar(true);
    arch.sleep(50);
    drawEnergyStar(false);
}

fn mapFb(base: [*]u32, pixels: usize) [*]u32 {
    const page_count = (pixels * 4 + paging.PAGING.page_size - 1) / paging.PAGING.page_size;
    const virt = paging.mapPagesConsecutive(@intFromPtr(base), page_count, .peripheral) catch @panic("oom");
    hw.entry_uart.carefully(.{ "MAP: FB at     ", virt, "~\r\n" });
    return @as([*]u32, @ptrFromInt(virt));
}

pub inline fn present() bool {
    return fb != null;
}

pub fn panicMessage(msg: []const u8) void {
    const msg_len: CONSOLE_DIMENSION = @as(CONSOLE_DIMENSION, @truncate("kernel panic: ".len + msg.len));
    const left: CONSOLE_DIMENSION = console_width - msg_len - 2;

    colour(0x4f);
    locate(0, left);
    var x: CONSOLE_DIMENSION = 0;
    while (x < msg_len + 2) : (x += 1) {
        print(" ");
    }
    locate(1, left);
    printf(" kernel panic: {s} ", .{msg});
    locate(2, left);
    x = 0;
    while (x < msg_len + 2) : (x += 1) {
        print(" ");
    }
}

fn drawEnergyStar(comptime allWhite: bool) void {
    const WIDTH = 138;
    const HEIGHT = 103;
    const DATA = @embedFile("../assets/energystar.vga");
    const left = fb_horiz - WIDTH;
    var y: u32 = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: u32 = 0;
        while (x < WIDTH) : (x += 1) {
            const s = DATA[(WIDTH * y + x) * 3 .. (WIDTH * y + x + 1) * 3];
            const c = (@as(u32, s[0]) << 16) | (@as(u32, s[1]) << 8) | @as(u32, s[2]);
            if (allWhite) {
                plot(left + x, y, if (c != 0) 0xffffff else 0);
            } else {
                plot(left + x, y, c);
            }
        }
    }
}

pub inline fn plot(x: u32, y: u32, c: u32) void {
    fb.?[fb_horiz * y + x] = c;
}

pub inline fn colour(bgfg: u8) void {
    console_colour = bgfg;
}

pub inline fn locate(row: CONSOLE_DIMENSION, col: CONSOLE_DIMENSION) void {
    console_row = row;
    console_col = col;
}

pub fn print(msg: []const u8) void {
    var state: enum { NORMAL, ESCAPE } = .NORMAL;

    loop: for (msg) |c| {
        switch (state) {
            .NORMAL => {
                switch (c) {
                    '\x1b' => {
                        state = .ESCAPE;
                        continue :loop;
                    },
                    '\n' => {
                        if (fb != null) {
                            console_col = 0;
                            console_row += 1;
                        }
                        hw.uart.write("\r\n") catch {};
                    },
                    '\x08' => {
                        hw.uart.write("\x08") catch {};
                        if (console_col > 0) {
                            console_col -= 1;
                        } else if (console_row > 0) {
                            console_row -= 1;
                            console_col = console_width - 1;
                        }
                    },
                    else => {
                        hw.uart.write(&[_]u8{c}) catch {};
                        if (fb != null) {
                            font.putChar(console_row, console_col, c, console_colour);
                            console_buf[console_row * console_width + console_col] = (@as(u16, console_colour) << 8) | c;
                            console_col += 1;
                        }
                    },
                }
                if (fb != null) {
                    if (console_col >= console_width) {
                        console_row += 1;
                        console_col = 0;
                    }
                    if (console_row >= console_height) {
                        scroll();
                        console_row -= 1;
                    }
                }
            },
            .ESCAPE => {
                colour(c);
                state = .NORMAL;
            },
        }
    }
}

fn scroll() void {
    var row: CONSOLE_DIMENSION = 0;
    while (row < console_height - 1) : (row += 1) {
        @memcpy(console_buf[row * console_width .. (row + 1) * console_width], console_buf[(row + 1) * console_width .. (row + 2) * console_width]);
    }
    @memset(console_buf[(console_height - 1) * console_width .. console_height * console_width], 0);
    refresh();
}

fn refresh() void {
    if (fb == null) {
        return;
    }
    var row: CONSOLE_DIMENSION = 0;
    while (row < console_height) : (row += 1) {
        var col: CONSOLE_DIMENSION = 0;
        while (col < console_width) : (col += 1) {
            const pair = console_buf[row * console_width + col];
            font.putChar(row, col, @as(u8, @truncate(pair)), @as(u8, @truncate(pair >> 8)));
        }
    }
}

var printf_buf: [1024]u8 = undefined;
pub fn printf(comptime format: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(printf_buf[0..], format, args) catch @panic("bufPrint failure");
    print(slice);
}

pub fn placechar(c: u8) void {
    if (fb != null) {
        font.putChar(console_row, console_col, c, console_colour);
    }
    console_buf[console_row * console_width + console_col] = (@as(u16, console_colour) << 8) | c;
}

pub fn putchar(c: u8) void {
    placechar(c);
    console_col += 1;
    if (console_col >= console_width) {
        console_row += 1;
        console_col = 0;
    }
    if (console_row >= console_height) {
        scroll();
        console_row -= 1;
    }
}
