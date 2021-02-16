const std = @import("std");
const build_options = @import("build_options");
const entry = @import("entry.zig");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const putchar = fb.putchar;
const halt = @import("halt.zig").halt;
const Shell = @import("shell.zig").Shell;

usingnamespace @import("hacks.zig");

// From daintree_mmu_start.
export fn daintree_main(entry_data: *entry.EntryData) void {
    HACK_uartAt(@intToPtr(*volatile u8, 0xffffff8000065000), .{ "daintree_main ", @ptrToInt(entry_data), "\r\n" });
    uart_global = @intToPtr(*volatile u8, entry_data.uart_base);
    HACK_uart(.{ "trying thru uart_global @ ", @ptrToInt(&uart_global), "\r\n" });

    fb.init(entry_data.fb, entry_data.fb_vert, entry_data.fb_horiz);

    HACK_uart(.{"init success!\r\n"});

    printf("\x1b\x0adaintree \x1b\x07{s} on {s}\n\n", .{ build_options.version, build_options.board });

    Shell.run();

    halt();
}
