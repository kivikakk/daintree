const std = @import("std");
const build_options = @import("build_options");
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
                    '\t' => {
                        const maybe_rest = self.autocomplete(buf[0..len]) catch |err| switch (err) {
                            error.PromptNeedsRedraw => {
                                printf("> {s}", .{buf[0..len]});
                                continue;
                            },
                        };
                        if (maybe_rest) |rest| {
                            std.mem.copy(u8, buf[len..], rest);
                            printf("{s}", .{rest});
                            len += @truncate(u8, rest.len);
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

    const AUTOCOMPLETES: []const []const u8 = &.{
        "echo ",
        "help ",
        "paging ",
        "paging dump ",
        "poweroff ",
        "reset ",
    };

    const AutocompleteError = error{PromptNeedsRedraw};

    fn autocomplete(self: *Shell, buf: []const u8) AutocompleteError!?[]const u8 {
        var maybe_match: ?[]const u8 = null;
        var ambiguous = false;
        for (AUTOCOMPLETES) |candidate| {
            if (std.mem.startsWith(u8, candidate, buf)) {
                if (ambiguous) {
                    printf("{s}", .{candidate});
                    continue;
                }
                if (maybe_match) |match| {
                    // Multiple matches.  If the existing match is a strict prefix, ignore this
                    // to allow prefix completion.
                    // Otherwise we can't continue due to multiple possible matches; start dumping
                    // all potential matches.
                    if (std.mem.startsWith(u8, candidate, match)) {
                        continue;
                    }
                    printf("\n{s}{s}", .{ match, candidate });
                    ambiguous = true;
                    continue;
                }
                maybe_match = candidate;
            }
        }
        if (ambiguous) {
            printf("\n", .{});
            return error.PromptNeedsRedraw;
        }
        if (maybe_match) |match| {
            return match[buf.len..];
        }
        return null;
    }

    fn process(self: *Shell, cmd: []const u8) void {
        const trimmed = std.mem.trim(u8, cmd, " \t");
        if (std.mem.eql(u8, trimmed, "reset")) {
            arch.reset();
        } else if (std.mem.eql(u8, trimmed, "poweroff")) {
            arch.poweroff();
        } else if (std.mem.eql(u8, trimmed, "echo")) {
            printf("\n", .{});
        } else if (std.mem.startsWith(u8, trimmed, "echo ")) {
            printf("{s}\n", .{trimmed["echo ".len..]});
        } else if (std.mem.eql(u8, trimmed, "help")) {
            self.help();
        } else if (std.mem.eql(u8, trimmed, "paging")) {
            self.paging("");
        } else if (std.mem.eql(u8, trimmed, "paging ")) {
            self.paging(std.mem.trim(u8, trimmed["paging ".len..], " \t"));
        } else if (trimmed.len == 0) {
            // nop
        } else {
            printf("unknown command: {s}\n", .{trimmed});
        }
    }

    fn help(self: *Shell) void {
        printf(
            \\daintree kernel shell ({s} on {s})
            \\
            \\echo         Print a blank line.
            \\echo STRING  Print a given string.
            \\help         Show this help.
            \\paging       Paging commands.
            \\poweroff     Power the board off.
            \\reset        Reset the system.
            \\
        ,
            .{ build_options.version, build_options.board },
        );
    }

    fn paging(self: *Shell, cmd: []const u8) void {
        if (cmd.len == 0) {
            printf(
                \\Paging commands.
                \\
                \\paging       Show this help.
                \\paging dump  Dump the page table trees.
                \\
            ,
                .{},
            );
        } else if (std.mem.eql(u8, cmd, "dump")) {
            // TODO -- need to unify arm/riscv entry files first.
        } else {
            printf("unknown paging command: {s}\n", .{cmd});
        }
    }
};
