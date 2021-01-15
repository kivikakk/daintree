const framebuffer = @import("framebuffer.zig");
const CONSOLE_DIMENSION = framebuffer.CONSOLE_DIMENSION;

// most of this shamelessly cribbed from myself years ago:
// https://git.kameliya.ee/kyuubey/tree/sfont.c?id=52d318234f4ea7657d41ae493155cdf77038b217

const CP437VGA = @embedFile("cp437.vga");
pub const FONT_HEIGHT = 16;
pub const FONT_WIDTH = 8; // this can't really change due to Maths™ -- we rely on FONT_WIDTH=@sizeOf(u8)

// adorable CGA: https://en.wikipedia.org/wiki/Color_Graphics_Adapter#Color_palette
const CGA_COLORS: [16]u24 = [16]u24{
    0x000000,
    0x0000AA,
    0x00AA00,
    0x00AAAA,
    0xAA0000,
    0xAA00AA,
    0xAA5500,
    0xAAAAAA,
    0x555555,
    0x5555FF,
    0x55FF55,
    0x55FFFF,
    0xFF5555,
    0xFF55FF,
    0xFFFF55,
    0xFFFFFF,
};

pub fn putChar(col: CONSOLE_DIMENSION, row: CONSOLE_DIMENSION, ch: u8, bgfg: u8) void {
    const x_origin = @as(u32, col) * FONT_WIDTH;
    const y_origin = @as(u32, row) * FONT_HEIGHT;

    var char = CP437VGA[@as(usize, FONT_HEIGHT) * ch .. @as(usize, FONT_HEIGHT) * (ch + 1)];

    var y: u32 = 0;
    while (y < FONT_HEIGHT) : (y += 1) {
        var x: u32 = 0;
        var mask: u32 = 0x80;
        while (x < FONT_WIDTH) : (x += 1) {
            const colour = if (char[y] & mask != 0) CGA_COLORS[bgfg & 0xf] else CGA_COLORS[(bgfg >> 4) & 0x7];
            framebuffer.plot(x_origin + x, y_origin + y, colour);
            mask /= 2;
        }
    }
}
