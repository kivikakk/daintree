const std = @import("std");
const printf = @import("console/fb.zig").printf;
const arch = @import("arch.zig");
const hw = @import("hw.zig");

pub const Shell = struct {
    pub fn run() void {
        var sh = Shell{};
        sh.exec();
    }

    fn exec(self: *Shell) void {
        printf("> ", .{});

        var buf: [256]u8 = [_]u8{undefined} ** 256;
        var len: u8 = 0;

        var uart_buf: [16]u8 = [_]u8{undefined} ** 16;

        while (true) {
            var recv = hw.uart.readBlock(&uart_buf) catch return;

            for (uart_buf[0..recv]) |c| {
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
    }

    fn process(self: *Shell, cmd: []const u8) void {
        if (std.mem.eql(u8, cmd, "reset")) {
            self.reset();
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            printf("{s}\n", .{cmd[5..]});
        }
    }

    fn reset(self: *Shell) void {
        switch (hw.psci.method) {
            .Hvc => {
                while (true) {
                    asm volatile (
                        \\msr daifset, #15
                        \\mov w0, #0x0009
                        \\movk w0, #0x8400, lsl 16
                        \\hvc 0
                        :
                        :
                        : "memory"
                    );
                }
            },
            .Smc => {
                while (true) {
                    asm volatile (
                        \\msr daifset, #15
                        \\mov w0, #0x0009
                        \\movk w0, #0x8400, lsl 16
                        \\smc 0
                        :
                        :
                        : "memory"
                    );
                }
            },
            else => printf("unknown psci method, can't reset\n", .{}),
        }
    }
};
