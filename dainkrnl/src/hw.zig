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
    var compatible: enum { Unknown, Psci, Syscon, SysconReboot, SysconPoweroff } = .Unknown;

    var address_cells: ?u32 = null;

    var psci_method: ?[]const u8 = null;
    var reg: ?[]const u8 = null;
    var syscon_conf: SysconConf = .{};

    var ev = try traverser.event();
    while (ev != .End) : (ev = try traverser.event()) {
        switch (ev) {
            .BeginNode => {
                depth += 1;
            },
            .EndNode => {
                depth -= 1;

                defer {
                    compatible = .Unknown;
                    psci_method = null;
                    reg = null;
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

                switch (compatible) {
                    .Syscon => {
                        syscon.init(readCells(address_cells orelse continue, reg orelse continue));
                        continue;
                    },
                    .SysconReboot => {
                        const value = syscon_conf.value orelse continue;
                        const offset = syscon_conf.offset orelse continue;
                        syscon.initReboot(offset, value);
                        continue;
                    },
                    .SysconPoweroff => {
                        const value = syscon_conf.value orelse continue;
                        const offset = syscon_conf.offset orelse continue;
                        syscon.initPoweroff(offset, value);
                        continue;
                    },
                    else => {},
                }
            },
            .Prop => |prop| {
                if (compatible == .Unknown and std.mem.eql(u8, prop.name, "compatible")) {
                    if (std.mem.indexOf(u8, prop.value, "arm,psci") != null) {
                        compatible = .Psci;
                    } else if (std.mem.indexOf(u8, prop.value, "syscon\x00") != null) {
                        compatible = .Syscon;
                    } else if (std.mem.indexOf(u8, prop.value, "syscon-poweroff\x00") != null) {
                        compatible = .SysconPoweroff;
                    } else if (std.mem.indexOf(u8, prop.value, "syscon-reboot\x00") != null) {
                        compatible = .SysconReboot;
                    }
                } else if (std.mem.eql(u8, prop.name, "#address-cells")) {
                    if (address_cells == null) {
                        address_cells = readU32(prop.value);
                    }
                } else if (std.mem.eql(u8, prop.name, "reg")) {
                    reg = prop.value;
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

// XXX these things are copied everywhere lol
fn readU32(value: []const u8) u32 {
    return std.mem.bigToNative(u32, @as(*const u32, @ptrCast(@alignCast(value.ptr))).*);
}
fn readU64(value: []const u8) u64 {
    return (@as(u64, readU32(value[0..4])) << 32) | readU32(value[4..8]);
}
fn readCells(cell_count: u32, value: []const u8) u64 {
    if (cell_count == 1) {
        if (value.len < @sizeOf(u32))
            @panic("readCells: cell_count = 1, bad len");
        return readU32(value);
    }
    if (cell_count == 2) {
        if (value.len < @sizeOf(u64))
            @panic("readCells: cell_count = 2, bad len");
        return readU64(value);
    }
    @panic("readCells: cell_count unk");
}
