const std = @import("std");
const dtblib = @import("dtb");

const Error = dtblib.Error || error{UartNotFound};

pub fn searchDtbForUartBase(dtb: []const u8) Error!u64 {
    var traverser: dtblib.Traverser = undefined;
    try traverser.init(dtb);

    var state: union(enum) { Root, Irrelevant: u8, Pl011, Serial } = .Root;
    var address_cells: ?u32 = null;
    var size_cells: ?u32 = null;
    var serial_value: ?u64 = null;

    // try pl011, or a serial that doesn't have a 'bluetooth' node.

    // skip root node
    var ev = try traverser.next();
    while (ev != .End) : (ev = try traverser.next()) {
        switch (state) {
            .Root => switch (ev) {
                .BeginNode => |name| {
                    if (std.mem.startsWith(u8, name, "pl011@")) {
                        state = .Pl011;
                    } else if (std.mem.startsWith(u8, name, "serial@")) {
                        serial_value = null;
                        state = .Serial;
                    } else {
                        state = .{ .Irrelevant = 0 };
                    }
                },
                .Prop => |prop| {
                    if (std.mem.eql(u8, prop.name, "#address-cells")) {
                        address_cells = std.mem.bigToNative(u32, @ptrCast(*const u32, @alignCast(@alignOf(u32), prop.value.ptr)).*);
                    } else if (std.mem.eql(u8, prop.name, "#size-cells")) {
                        size_cells = std.mem.bigToNative(u32, @ptrCast(*const u32, @alignCast(@alignOf(u32), prop.value.ptr)).*);
                    }
                },
                else => {},
            },
            .Irrelevant => |*depth| switch (ev) {
                .BeginNode => {
                    depth.* += 1;
                },
                .EndNode => {
                    if (depth.* == 0) {
                        state = .Root;
                    } else {
                        depth.* -= 1;
                    }
                },
                else => {},
            },
            .Pl011 => switch (ev) {
                .Prop => |prop| {
                    if (std.mem.eql(u8, prop.name, "reg") and address_cells != null and size_cells != null) {
                        return try firstReg(address_cells.?, prop.value);
                    }
                },
                .BeginNode => state = .{ .Irrelevant = 1 },
                .EndNode => state = .Root,
                else => {},
            },
            .Serial => switch (ev) {
                .Prop => |prop| {
                    if (std.mem.eql(u8, prop.name, "reg") and address_cells != null and size_cells != null) {
                        serial_value = try firstReg(address_cells.?, prop.value);
                    } else if (std.mem.eql(u8, prop.name, "status")) {
                        if (!std.mem.eql(u8, "okay\x00", prop.value)) {
                            state = .{ .Irrelevant = 0 };
                        }
                    }
                },
                .BeginNode => {
                    // Don't want any serial with a subnode.
                    state = .{ .Irrelevant = 1 };
                },
                .EndNode => {
                    if (serial_value) |made_it| {
                        return made_it;
                    }
                    state = .Root;
                },
                else => {},
            },
        }
    }

    return error.UartNotFound;
}

fn firstReg(address_cells: u32, value: []const u8) !u64 {
    if (value.len % @sizeOf(u32) != 0) {
        return error.BadStructure;
    }
    var big_endian_cells: []const u32 = @ptrCast([*]const u32, @alignCast(@alignOf(u32), value.ptr))[0 .. value.len / @sizeOf(u32)];
    if (address_cells == 1) {
        return std.mem.bigToNative(u32, big_endian_cells[0]);
    } else if (address_cells == 2) {
        return @as(u64, std.mem.bigToNative(u32, big_endian_cells[0])) << 32 | std.mem.bigToNative(u32, big_endian_cells[1]);
    }
    return error.UnsupportedCells;
}
