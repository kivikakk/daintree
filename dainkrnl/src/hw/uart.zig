const ddtb = @import("../common/ddtb.zig");
const hw_pl011 = @import("arm,pl011.zig");
const hw_dw_apb_uart = @import("snps,dw-apb-uart.zig");
const hw_sifive_uart0 = @import("sifive,uart0.zig");

pub const Error = error{NoUart};

pub fn init(uart: ddtb.Uart) void {
    switch (uart.kind) {
        .ArmPl011 => UART = UartImpl{
            .base = uart.base,
            .reg_shift = uart.reg_shift,
            .write = hw_pl011.write,
            .readBlock = hw_pl011.readBlock,
        },
        .SnpsDwApbUart, .Ns16550a => UART = UartImpl{
            .base = uart.base,
            .reg_shift = uart.reg_shift,
            .write = hw_dw_apb_uart.write,
            .readBlock = hw_dw_apb_uart.readBlock,
        },
        .SifiveUart0 => {
            hw_sifive_uart0.init(uart.base);
            UART = UartImpl{
                .base = uart.base,
                .reg_shift = uart.reg_shift,
                .write = hw_sifive_uart0.write,
                .readBlock = hw_sifive_uart0.readBlock,
            };
        },
    }
    write("uart.init()\r\n") catch {};
}

pub fn write(data: []const u8) Error!void {
    const uart = UART orelse return error.NoUart;
    uart.write(uart.base, uart.reg_shift, data);
}

pub fn readBlock(buf: []u8) Error!usize {
    const uart = UART orelse return error.NoUart;
    return uart.readBlock(uart.base, uart.reg_shift, buf);
}

// ---

const UartImpl = struct {
    base: u64,
    reg_shift: u4,

    write: fn (base: u64, reg_shift: u4, data: []const u8) void,
    readBlock: fn (base: u64, reg_shift: u4, buf: []u8) usize,
};

var UART: ?UartImpl = null;
