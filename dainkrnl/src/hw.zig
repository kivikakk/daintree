pub const uart = @import("hw/uart.zig");
pub const psci = @import("hw/psci.zig");
pub const entry_uart = @import("hw/entry_uart.zig");
pub const syscon = @import("hw/syscon.zig");

const std = @import("std");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const dtblib = @import("dtb");

const SysconConf = struct {
    regmap: void = {}, // XXX we need to use the full DTB parser here folks. phandle. assume 0x100000 (~+0x1000) for now
    value: ?u32 = null,
    offset: ?u32 = null,
};

pub fn init(dtb: []const u8) !void {
    printf("dtb at {*:0>16} (0x{x} bytes)\n", .{ dtb.ptr, dtb.len });

    var traverser: dtblib.Traverser = undefined;
    try traverser.init(dtb);

    var depth: usize = 1;
    var compatible: enum { Unknown, Psci, SysconReboot, SysconPoweroff } = .Unknown;

    var psci_method: ?[]const u8 = null;
    var syscon_conf: SysconConf = .{};

    var ev = try traverser.next();
    while (ev != .End) : (ev = try traverser.next()) {
        switch (ev) {
            .BeginNode => {
                depth += 1;
            },
            .EndNode => {
                depth -= 1;

                defer {
                    compatible = .Unknown;
                    psci_method = null;
                    syscon_conf = .{};
                }

                if (compatible == .Psci and psci_method != null) {
                    if (std.mem.eql(u8, psci_method.?, "hvc\x00")) {
                        psci.method = .Hvc;
                        continue;
                    } else if (std.mem.eql(u8, psci_method.?, "smc\x00")) {
                        psci.method = .Smc;
                        continue;
                    } else {
                        printf("unknown psci method: {s}\n", .{psci_method.?});
                        continue;
                    }
                }

                if (compatible == .SysconReboot) {
                    const value = syscon_conf.value orelse continue;
                    const offset = syscon_conf.offset orelse continue;
                    syscon.initReboot(0x100000, offset, value);
                    continue;
                }

                if (compatible == .SysconPoweroff) {
                    const value = syscon_conf.value orelse continue;
                    const offset = syscon_conf.offset orelse continue;
                    syscon.initPoweroff(0x100000, offset, value);
                    continue;
                }
            },
            .Prop => |prop| {
                if (compatible == .Unknown and std.mem.eql(u8, prop.name, "compatible")) {
                    if (std.mem.indexOf(u8, prop.value, "arm,psci") != null) {
                        compatible = .Psci;
                    } else if (std.mem.indexOf(u8, prop.value, "syscon-poweroff") != null) {
                        compatible = .SysconPoweroff;
                    } else if (std.mem.indexOf(u8, prop.value, "syscon-reboot") != null) {
                        compatible = .SysconReboot;
                    }
                } else if (std.mem.eql(u8, prop.name, "method")) {
                    psci_method = prop.value;
                } else if (std.mem.eql(u8, prop.name, "value")) {
                    syscon_conf.value = readU32(prop.value);
                } else if (std.mem.eql(u8, prop.name, "offset")) {
                    syscon_conf.offset = readU32(prop.value);
                }
            },

            .End => {},
        }
    }
}

// XXX this is copied everywhere lol
fn readU32(value: []const u8) u32 {
    return std.mem.bigToNative(u32, @ptrCast(*const u32, @alignCast(@alignOf(u32), value.ptr)).*);
}
