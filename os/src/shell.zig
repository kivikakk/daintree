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
        } else if (std.mem.eql(u8, cmd, "poweroff")) {
            self.poweroff();
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            printf("{s}\n", .{cmd[5..]});
        } else if (std.mem.trim(u8, cmd, " \t").len == 0) {
            // nop
        } else {
            printf("unknown command: {s}\n", .{cmd});
        }
    }

    fn reset(self: *Shell) void {
        self.psci(0x8400_0009);
    }

    fn poweroff(self: *Shell) void {
        self.psci(0x8400_0008);
    }

    fn psci(self: *Shell, val: u32) void {
        switch (hw.psci.method) {
            .Hvc => {
                asm volatile (
                    \\msr daifset, #15
                    \\hvc 0
                    :
                    : [val] "{x0}" (val)
                    : "memory"
                );
            },
            .Smc => {
                asm volatile (
                    \\msr daifset, #15
                    \\smc 0
                    :
                    : [val] "{x0}" (val)
                    : "memory"
                );
            },
            else => printf("unknown psci method\n", .{}),
        }
    }
};
