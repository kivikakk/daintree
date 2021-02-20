const std = @import("std");
const build_options = @import("build_options");
const fb = @import("console/fb.zig");
const arch = @import("arch.zig");
const entry_uart = @import("entry/uart.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    entry_uart.carefully(.{"\r\n!!!!!!!!!!!!\r\nkernel panic\r\n!!!!!!!!!!!!\r\n"});
    const current_el = arch.readRegister(.CurrentEL) >> 2;
    const sctlr_el1 = arch.readRegister(.SCTLR_EL1);
    entry_uart.carefully(.{ "CurrentEL: ", current_el, "\r\n" });
    entry_uart.carefully(.{ "SCTLR_EL1: ", sctlr_el1, "\r\n" });
    if (error_return_trace) |ert| {
        entry_uart.carefully(.{"trying to print stack ... \r\n"});
        var frame_index: usize = 0;
        var frames_left: usize = std.math.min(ert.index, ert.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % ert.instruction_addresses.len;
        }) {
            const return_address = ert.instruction_addresses[frame_index];
            entry_uart.carefully(.{ return_address, "\r\n" });
        }
    } else {
        entry_uart.carefully(.{"no ert\r\n"});
    }
    entry_uart.carefully(.{ "@returnAddress: ", @returnAddress(), "\r\n" });

    entry_uart.carefully(.{ "panic message ptr: ", @ptrToInt(msg.ptr), "\r\n<" });
    entry_uart.carefully(.{ entry_uart.Escape.Runtime, msg, ">\r\n" });

    if (fb.present()) {
        const msg_len: fb.CONSOLE_DIMENSION = @truncate(fb.CONSOLE_DIMENSION, "kernel panic: ".len + msg.len);
        const left: fb.CONSOLE_DIMENSION = fb.console_width - msg_len - 2;

        fb.colour(0x4f);
        fb.locate(0, left);
        var x: fb.CONSOLE_DIMENSION = 0;
        while (x < msg_len + 2) : (x += 1) {
            fb.print(" ");
        }
        fb.locate(1, left);
        fb.printf(" kernel panic: {s} ", .{msg});
        fb.locate(2, left);
        x = 0;
        while (x < msg_len + 2) : (x += 1) {
            fb.print(" ");
        }
    }

    arch.halt();
}
