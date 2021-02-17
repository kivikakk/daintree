const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const build_options = @import("build_options");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const putchar = fb.putchar;
const halt = @import("arch.zig").halt;
const Shell = @import("shell.zig").Shell;
const ddtb = @import("common/ddtb.zig");
const uart = @import("uart.zig");

usingnamespace @import("hacks.zig");

// From daintree_mmu_start.
export fn daintree_main(entry_data: *dcommon.EntryData) void {
    uart_global = @intToPtr(*volatile u8, entry_data.uart_base);
    HACK_uart(.{ "trying thru uart_global @ ", @ptrToInt(&uart_global), "\r\n" });

    fb.init(entry_data.fb, entry_data.fb_vert, entry_data.fb_horiz);

    HACK_uart(.{"init success!\r\n"});

    printf("\x1b\x0adaintree \x1b\x07{s} on {s}\n\n", .{ build_options.version, build_options.board });

    printf("dtb at {*:0>16} (0x{x} bytes)\n", .{ (entry_data.dtb_ptr), entry_data.dtb_len });

    if (ddtb.searchForUart(entry_data.dtb_ptr[0..entry_data.dtb_len])) |ua| {
        printf("got UART: {} @ 0x{x:0>16}\n", .{ ua.kind, ua.base });
        // We patched this through in the MMU, so be extremely hacky:
        uart.init(.{
            .base = entry_data.uart_base,
            .kind = ua.kind,
        });
    } else |err| {
        printf("got err: {}\n", .{err});
    }

    Shell.run();

    printf("\nshell returned\n", .{});

    halt();
}
