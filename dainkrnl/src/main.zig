const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const build_options = @import("build_options");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const halt = @import("arch.zig").halt;
const Shell = @import("shell.zig").Shell;
const ddtb = @import("common/ddtb.zig");
const hw = @import("hw.zig");
const entry = @import("entry.zig");

// From daintree_mmu_start.
export fn daintree_main(entry_data: *dcommon.EntryData) void {
    entry.uart.base = @intToPtr(*volatile u8, entry_data.uart_base);
    entry.uart.carefully(.{ "daintree_main using uart_base ", entry_data.uart_base, "\r\n" });

    if (entry_data.fb) |fb_addr| {
        entry.uart.carefully(.{ "initting fb at ", @ptrToInt(fb_addr), "\r\n" });
        fb.init(fb_addr, entry_data.fb_vert, entry_data.fb_horiz);
    }

    entry.uart.carefully(.{ "searching dtb at ", @ptrToInt(entry_data.dtb_ptr), "\r\n" });
    if (ddtb.searchForUart(entry_data.dtb_ptr[0..entry_data.dtb_len])) |uart| {
        entry.uart.carefully(.{ "got UART: ", entry.uart.Escape.Runtime, @tagName(uart.kind), " @ ", uart.base, "\r\n" });
        // We patched this through in the MMU, so be extremely hacky:
        hw.uart.init(.{
            .base = entry_data.uart_base,
            .kind = uart.kind,
        });
    } else |err| {
        entry.uart.carefully(.{ "got err: ", entry.uart.Escape.Runtime, @errorName(err), "\r\n" });
    }

    printf("\x1b\x0adaintree \x1b\x07{s} on {s}\n\n", .{ build_options.version, build_options.board });

    hw.init(entry_data.dtb_ptr[0..entry_data.dtb_len]) catch |err| {
        printf("hw.init error: {}\n", .{err});
    };

    Shell.run();

    printf("\nshell returned\n", .{});

    halt();
}
