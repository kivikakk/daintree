// https://developer.arm.com/documentation/ddi0183/g/programmers-model/summary-of-registers

// hack!
fn busyLoop() void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        asm volatile ("nop");
    }
}

const REGOFF_UARTDR = 0x00;
const REGOFF_UARTFR = 0x18;
const REGMASK_UARTFR_RXFE = 1 << 4;

pub fn write(base: u64, data: []const u8) void {
    const uartdr = @intToPtr(*volatile u8, base + REGOFF_UARTDR);
    for (data) |c| {
        uartdr.* = c;
        busyLoop();
    }
}

// Works the 'opposite' to 8250-style UART; instead of waiting for a "data
// available" bit to set, we wait for the "receive FIFO empty" bit to clear.
pub fn readBlock(base: u64, buf: []u8) usize {
    const uartdr = @intToPtr(*volatile u8, base + REGOFF_UARTDR);
    const uartfr = @intToPtr(*volatile u8, base + REGOFF_UARTFR);
    while (uartfr.* & REGMASK_UARTFR_RXFE == REGMASK_UARTFR_RXFE) {
        // receive FIFO empty ...
        asm volatile ("nop");
    }
    var i: usize = 0;
    while (true) {
        buf[i] = uartdr.*;
        i += 1;

        if (i == buf.len) {
            break;
        }

        if (uartfr.* & REGMASK_UARTFR_RXFE == REGMASK_UARTFR_RXFE) {
            break;
        }
    }

    return i;
}
