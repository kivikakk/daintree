const std = @import("std");
const build_options = @import("build_options");
const fb = @import("console/fb.zig");
const halt = @import("halt.zig").halt;
const arch = @import("arch.zig");

usingnamespace @import("hacks.zig");

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    HACK_uart(.{"\r\n!!!!!!!!!!!!\r\nkernel panic\r\n!!!!!!!!!!!!\r\n"});
    const current_el = arch.readRegister(.CurrentEL) >> 2;
    const sctlr_el1 = arch.readRegister(.SCTLR_EL1);
    HACK_uart(.{ "CurrentEL: ", current_el, "\r\n" });
    HACK_uart(.{ "SCTLR_EL1: ", sctlr_el1, "\r\n" });
    if (error_return_trace) |ert| {
        HACK_uart(.{"trying to print stack ... \r\n"});
        var frame_index: usize = 0;
        var frames_left: usize = std.math.min(ert.index, ert.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % ert.instruction_addresses.len;
        }) {
            const return_address = ert.instruction_addresses[frame_index];
            HACK_uart(.{ return_address, "\r\n" });
        }
    } else {
        HACK_uart(.{"no ert\r\n"});
    }

    HACK_uart(.{ "panic message ptr: ", @ptrToInt(msg.ptr), "\r\n<" });
    HACK_uart(.{ HACK.UART_Runtime, msg, ">\r\n" });

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
    halt();
}
