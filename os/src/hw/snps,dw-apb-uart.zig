// https://patchwork.ozlabs.org/project/devicetree-bindings/patch/20190114172930.7508-1-robh@kernel.org/
// http://www.macs.hw.ac.uk/~hwloidl/hackspace/linux/drivers/tty/serial/8250/8250_dw.c
// 8250 in the streets, 16750 in the sheets

// hack!
fn busyLoop() callconv(.Inline) void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        asm volatile ("nop");
    }
}

const REGOFF_RBR_THR = 0x00;
const REGOFF_LSR = 0x05 << 2; // reg-shift
const REGMASK_LSR_DATA_AVAIL = 1 << 0;

pub fn write(base: u64, data: []const u8) void {
    const thr = @intToPtr(*volatile u8, base + REGOFF_RBR_THR);
    for (data) |c| {
        thr.* = c;
        busyLoop();
    }
}

pub fn readBlock(base: u64, buf: []u8) usize {
    const rbr = @intToPtr(*volatile u8, base + REGOFF_RBR_THR);
    const lsr = @intToPtr(*volatile u8, base + REGOFF_LSR);
    while (lsr.* & REGMASK_LSR_DATA_AVAIL == 0) {
        // no data available ...
        asm volatile ("nop");
    }
    var i: usize = 0;
    while (true) {
        buf[i] = rbr.*;
        i += 1;

        if (i == buf.len) {
            break;
        }

        if (lsr.* & REGMASK_LSR_DATA_AVAIL == 0) {
            break;
        }
    }

    return i;
}
