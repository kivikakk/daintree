const std = @import("std");
const font = @import("font.zig");

pub const CONSOLE_DIMENSION = u16;

var fb: [*]u32 = undefined;
var fb_vert: u32 = undefined;
var fb_horiz: u32 = undefined;

pub var console_height: CONSOLE_DIMENSION = undefined;
pub var console_width: CONSOLE_DIMENSION = undefined;
var console_buf: [3700]u16 = undefined;

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

    var y: u32 = 0;
    while (y < fb_vert) : (y += 1) {
        var x: u32 = 0;
        while (x < fb_horiz) : (x += 1) {
            plot(x, y, 0x00000000);
        }
    }
}

pub fn plot(x: u32, y: u32, c: u32) void {
    fb[fb_horiz * y + x] = c;
}

pub fn colour(bgfg: u8) void {
    console_colour = bgfg;
}

pub fn locate(row: CONSOLE_DIMENSION, col: CONSOLE_DIMENSION) void {
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
                        console_col = 0;
                        console_row += 1;
                    },
                    else => {
                        font.putChar(console_row, console_col, c, console_colour);
                        console_buf[console_row * console_width + console_col] = (@as(u16, console_colour) << 8) | c;
                        console_col += 1;
                    },
                }
                if (console_col >= console_width) {
                    console_row += 1;
                    console_col = 0;
                }
                if (console_row >= console_height) {
                    scroll();
                    console_row -= 1;
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
    print(std.fmt.bufPrint(printf_buf[0..], format, args) catch unreachable);
}
