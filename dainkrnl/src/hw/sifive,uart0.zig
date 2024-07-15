// Based on https://source.denx.de/u-boot/u-boot/-/blob/eed127dbd4082ba21fd420449e68d1ad177cdc4b/drivers/serial/serial_sifive.c.

const REGOFF_TXFIFO = 0 << 2;
const REGOFF_RXFIFO = 1 << 2;
const REGOFF_TXCTRL = 2 << 2;
const REGOFF_RXCTRL = 3 << 2;
const REGOFF_IE = 4 << 2;
const REGMASK_TXFIFO_FULL = 0x80000000;
const REGMASK_RXFIFO_EMPTY = 0x80000000;

pub fn init(base: u64) void {
    @as(*volatile u32, @ptrFromInt(base + REGOFF_TXCTRL)).* = 1;
    @as(*volatile u32, @ptrFromInt(base + REGOFF_RXCTRL)).* = 1;
    @as(*volatile u32, @ptrFromInt(base + REGOFF_IE)).* = 0;
}

pub fn write(base: u64, reg_shift: u4, data: []const u8) void {
    _ = reg_shift;

    const txfifo = @as(*volatile u32, @ptrFromInt(base + REGOFF_TXFIFO));
    for (data) |c| {
        while (txfifo.* & REGMASK_TXFIFO_FULL == REGMASK_TXFIFO_FULL) {
            asm volatile ("nop");
        }
        txfifo.* = c;
    }
}

pub fn readBlock(base: u64, reg_shift: u4, buf: []u8) usize {
    _ = reg_shift;

    const rxfifo = @as(*volatile u32, @ptrFromInt(base + REGOFF_RXFIFO));

    var i: usize = 0;
    while (true) {
        const d = rxfifo.*;
        if (d & REGMASK_RXFIFO_EMPTY == REGMASK_RXFIFO_EMPTY) {
            if (i == 0) {
                continue;
            } else {
                break;
            }
        }

        buf[i] = @as(u8, @truncate(d & 0xff));
        i += 1;

        if (i == buf.len) {
            break;
        }
    }

    return i;
}
