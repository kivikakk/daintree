const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const build_options = @import("build_options");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const putchar = fb.putchar;
const halt = @import("arch.zig").halt;
const Shell = @import("shell.zig").Shell;
const ddtb = @import("common/ddtb.zig");
const hw_uart = @import("hw/uart.zig");

const entry_uart = @import("entry/uart.zig");

// From daintree_mmu_start.
export fn daintree_main(entry_data: *dcommon.EntryData) void {
    entry_uart.base = @intToPtr(*volatile u8, entry_data.uart_base);
    entry_uart.carefully(.{ "daintree_main using uart_base ", entry_data.uart_base, "\r\n" });

    fb.init(entry_data.fb, entry_data.fb_vert, entry_data.fb_horiz);

    if (ddtb.searchForUart(entry_data.dtb_ptr[0..entry_data.dtb_len])) |uart| {
        entry_uart.carefully(.{ "got UART: ", entry_uart.Escape.Runtime, @tagName(uart.kind), " @ 0", uart.base, "\r\n" });
        // We patched this through in the MMU, so be extremely hacky:
        hw_uart.init(.{
            .base = entry_data.uart_base,
            .kind = uart.kind,
        });
    } else |err| {
        entry_uart.carefully(.{ "got err: ", entry_uart.Escape.Runtime, @errorName(err), "\r\n" });
    }

    printf("\x1b\x0adaintree \x1b\x07{s} on {s}\n\n", .{ build_options.version, build_options.board });
    printf("dtb at {*:0>16} (0x{x} bytes)\n", .{ (entry_data.dtb_ptr), entry_data.dtb_len });

    Shell.run();

    printf("\nshell returned\n", .{});

    halt();
}
