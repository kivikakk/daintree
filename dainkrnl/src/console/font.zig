const fb = @import("fb.zig");
const CONSOLE_DIMENSION = fb.CONSOLE_DIMENSION;

// most of this shamelessly cribbed from myself years ago:
// https://git.src.kameliya.ee/~kameliya/kyuubey/tree/52d318234f4ea7657d41ae493155cdf77038b217/item/sfont.c

const CP437VGA = @embedFile("../assets/cp437.vga");
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

pub fn putChar(row: CONSOLE_DIMENSION, col: CONSOLE_DIMENSION, ch: u8, bgfg: u8) void {
    const y_origin = @as(u32, row) * FONT_HEIGHT;
    const x_origin = @as(u32, col) * FONT_WIDTH;

    const char = CP437VGA[@as(usize, FONT_HEIGHT) * ch ..][0..FONT_HEIGHT];

    var y: u32 = 0;
    while (y < FONT_HEIGHT) : (y += 1) {
        var x: u32 = 0;
        var mask: u32 = 0x80;
        while (x < FONT_WIDTH) : (x += 1) {
            const colour = if (char[y] & mask != 0) CGA_COLORS[bgfg & 0xf] else CGA_COLORS[(bgfg >> 4) & 0x7];
            fb.plot(x_origin + x, y_origin + y, colour);
            mask /= 2;
        }
    }
}
