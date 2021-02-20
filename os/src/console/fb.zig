const std = @import("std");
const font = @import("font.zig");
const arch = @import("../arch.zig");
const hw_uart = @import("../hw/uart.zig");

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
    fb = in_fb;
    fb_vert = in_vert;
    fb_horiz = in_horiz;

    console_height = @truncate(CONSOLE_DIMENSION, fb_vert / font.FONT_HEIGHT);
    console_width = @truncate(CONSOLE_DIMENSION, fb_horiz / font.FONT_WIDTH);
    if (console_height * console_width > console_buf.len) {
        @panic("can't fit console");
    }
    std.mem.set(u16, console_buf[0 .. console_width * console_height], 0);
    std.mem.set(u32, fb.?[0 .. fb_horiz * fb_vert], 0);

    arch.sleep(500);
    drawEnergyStar(false);
    arch.sleep(50);
    drawEnergyStar(true);
    arch.sleep(50);
    drawEnergyStar(false);
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
            var s = DATA[(WIDTH * y + x) * 3 .. (WIDTH * y + x + 1) * 3];
            const c = (@as(u32, s[0]) << 16) | (@as(u32, s[1]) << 8) | @as(u32, s[2]);
            if (allWhite) {
                plot(left + x, y, if (c != 0) 0xffffff else 0);
            } else {
                plot(left + x, y, c);
            }
        }
    }
}

pub fn plot(x: u32, y: u32, c: u32) callconv(.Inline) void {
    fb.?[fb_horiz * y + x] = c;
}

pub fn colour(bgfg: u8) callconv(.Inline) void {
    console_colour = bgfg;
}

pub fn locate(row: CONSOLE_DIMENSION, col: CONSOLE_DIMENSION) callconv(.Inline) void {
    console_row = row;
    console_col = col;
}

pub fn print(msg: []const u8) void {
    var state: enum { NORMAL, ESCAPE } = .NORMAL;

    loop: for (msg) |c, i| {
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
                        hw_uart.write("\r\n") catch {};
                    },
                    else => {
                        hw_uart.write(&[_]u8{c}) catch {};
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
        std.mem.copy(u16, console_buf[row * console_width .. (row + 1) * console_width], console_buf[(row + 1) * console_width .. (row + 2) * console_width]);
    }
    std.mem.set(u16, console_buf[(console_height - 1) * console_width .. console_height * console_width], 0);
    refresh();
}

fn refresh() void {
    var row: CONSOLE_DIMENSION = 0;
    while (row < console_height) : (row += 1) {
        var col: CONSOLE_DIMENSION = 0;
        while (col < console_width) : (col += 1) {
            const pair = console_buf[row * console_width + col];
            font.putChar(row, col, @truncate(u8, pair), @truncate(u8, pair >> 8));
        }
    }
}

var printf_buf: [1024]u8 = undefined;
pub fn printf(comptime format: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(printf_buf[0..], format, args) catch @panic("bufPrint failure");
    print(slice);
}

pub fn putchar(c: u8) void {
    font.putChar(console_row, console_col, c, console_colour);
    console_buf[console_row * console_width + console_col] = (@as(u16, console_colour) << 8) | c;
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
