const ddtb = @import("common/ddtb.zig");
const hw_pl011 = @import("hw/arm,pl011.zig");
const hw_dw_apb_uart = @import("hw/snps,dw-apb-uart.zig");

pub const Error = error{NoUart};

pub fn init(uart: ddtb.Uart) void {
    // In future: actually use reg-shift etc. from the DTB!
    switch (uart.kind) {
        .Pl011 => UART = UartImpl{
            .base = uart.base,
            .write = hw_pl011.write,
            .readBlock = hw_pl011.readBlock,
        },
        .Serial8250 => UART = UartImpl{
            .base = uart.base,
            .write = hw_dw_apb_uart.write,
            .readBlock = hw_dw_apb_uart.readBlock,
        },
    }
    write("uart.init()\r\n") catch {};
}

pub fn write(data: []const u8) Error!void {
    const uart = UART orelse return error.NoUart;
    uart.write(uart.base, data);
}

pub fn readBlock(buf: []u8) Error!usize {
    const uart = UART orelse return error.NoUart;
    return uart.readBlock(uart.base, buf);
}

// ---

const UartImpl = struct {
    base: u64,

    write: fn (base: u64, data: []const u8) void,
    readBlock: fn (base: u64, buf: []u8) usize,
};

var UART: ?UartImpl = null;
