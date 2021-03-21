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
                    8, 127 => {
                        if (len > 0) {
                            printf("\x08 \x08", .{});
                            len -= 1;
                        }
                    },
                    '\r' => {
                        printf("\n", .{});
                        self.process(buf[0..len]);
                        printf("> ", .{});
                        len = 0;
                    },
                    'a'...'z', 'A'...'Z', '0'...'9', '=', '\\', '^', '+', ':', '%', '@', '&', '!', '(', '[', '{', '<', ' ', '#', '$', '"', '\'', ',', '.', '_', '~', '`', '-', '/', '*', '>', '}', ']', ')', '?' => {
                        buf[len] = c;
                        len += 1;
                        printf("{c}", .{c});
                    },
                    else => {
                        printf("?{}?", .{c});
                    },
                }
            }
        }
    }

    fn process(self: *Shell, cmd: []const u8) void {
        if (std.mem.eql(u8, cmd, "reset")) {
            arch.reset();
        } else if (std.mem.eql(u8, cmd, "poweroff")) {
            arch.poweroff();
        } else if (std.mem.startsWith(u8, cmd, "echo ")) {
            printf("{s}\n", .{cmd[5..]});
        } else if (std.mem.trim(u8, cmd, " \t").len == 0) {
            // nop
        } else {
            printf("unknown command: {s}\n", .{cmd});
        }
    }
};
