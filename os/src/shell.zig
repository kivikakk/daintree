const std = @import("std");
const printf = @import("console/fb.zig").printf;
usingnamespace @import("hacks.zig");

pub const Shell = struct {
    pub fn run() void {
        const uart = uart_global.?;
        const uart_lsr =
            if (uart == @intToPtr(*volatile u8, 0x0900_0000))
            @intToPtr(*volatile u8, @ptrToInt(uart) + 0x18)
        else
            @intToPtr(*volatile u8, @ptrToInt(uart) + (5 << 2)); // reg-shift = <2>
        const uart_mask: u8 = if (uart == @intToPtr(*volatile u8, 0x0900_0000))
            0x10
        else
            1;
        const uart_cmp: u8 = if (uart == @intToPtr(*volatile u8, 0x0900_0000))
            0x0
        else
            1;

        var sh = Shell{
            .uart = uart,
            .uart_lsr = uart_lsr,
            .uart_mask = uart_mask,
            .uart_cmp = uart_cmp,
        };
        sh.exec();
    }

    uart: *volatile u8,
    uart_lsr: *volatile u8,
    uart_mask: u8,
    uart_cmp: u8,

    fn exec(self: *Shell) void {
        printf("> ", .{});

        var buf: [256]u8 = [_]u8{undefined} ** 256;
        var len: u8 = 0;

        while (true) {
            while (self.uart_lsr.* & self.uart_mask != self.uart_cmp) {}
            const c = self.uart.*;

            switch (c) {
                '\r' => {
                    printf("\n", .{});
                    self.process(buf[0..len]);
                    printf("> ", .{});
                    len = 0;
                },
                else => {
                    buf[len] = c;
                    len += 1;
                    printf("{c}", .{c});
                },
            }
        }
    }

    fn process(self: *Shell, cmd: []const u8) void {
        if (std.mem.eql(u8, cmd, "reset")) {
            self.reset();
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            printf("{s}\n", .{cmd[5..]});
        }
    }

    fn reset(self: *Shell) void {
        // This works on rockpro64 if you wait long enough.
        asm volatile (
            \\msr daifset, #15
            \\ldr w0, =0x84000009
            \\hvc 0
            :
            :
            : "memory"
        );
    }
};
