pub const uart = @import("hw/uart.zig");
pub const psci = @import("hw/psci.zig");

const std = @import("std");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const dtblib = @import("dtb");

pub fn init(dtb: []const u8) !void {
    printf("dtb at {*:0>16} (0x{x} bytes)\n", .{ dtb.ptr, dtb.len });

    var traverser: dtblib.Traverser = undefined;
    try traverser.init(dtb);

    var state: union(enum) { Root, Node: u8 } = .Root;
    var compatible: enum { Unknown, Psci } = .Unknown;
    var psci_method: ?[]const u8 = undefined;

    var ev = try traverser.next();
    while (ev != .End) : (ev = try traverser.next()) {
        switch (state) {
            .Root => switch (ev) {
                .BeginNode => |name| {
                    state = .{ .Node = 0 };
                    compatible = .Unknown;
                    psci_method = null;
                },
                else => {},
            },
            .Node => |*depth| switch (ev) {
                .BeginNode => {
                    depth.* += 1;
                },
                .EndNode => {
                    if (depth.* == 0) {
                        state = .Root;

                        if (compatible == .Psci and psci_method != null) {
                            if (std.mem.eql(u8, psci_method.?, "hvc\x00")) {
                                psci.method = .Hvc;
                                return;
                            } else if (std.mem.eql(u8, psci_method.?, "smc\x00")) {
                                psci.method = .Smc;
                                return;
                            } else {
                                printf("unknown psci method: {s}\n", .{psci_method.?});
                            }
                        }
                    } else {
                        depth.* -= 1;
                    }
                },
                .Prop => |prop| {
                    if (depth.* != 0) {
                        continue;
                    }
                    if (compatible == .Unknown and std.mem.eql(u8, prop.name, "compatible")) {
                        if (std.mem.indexOf(u8, prop.value, "arm,psci") != null) {
                            compatible = .Psci;
                        }
                    } else if (std.mem.eql(u8, prop.name, "method")) {
                        psci_method = prop.value;
                    }
                },

                .End => {},
            },
        }
    }
}
