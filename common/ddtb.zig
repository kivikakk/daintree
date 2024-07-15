const std = @import("std");
const dtblib = @import("dtb");

pub const Error = dtblib.Error || error{UartNotFound};

pub const Uart = struct {
    base: u64,
    reg_shift: u4,
    kind: UartKind,
};

pub const UartKind = enum {
    ArmPl011, //      "arm,pl011"        -- QEMU ARM
    SnpsDwApbUart, // "snps,dw-apb-uart" -- ROCKPro64
    Ns16550a, //      "ns16550a"         -- QEMU RISC-V
    SifiveUart0, //   "sifive,uart0"     -- Maixduino
};

pub fn searchForUart(dtb: []const u8) Error!Uart {
    var traverser: dtblib.Traverser = undefined;
    try traverser.init(dtb);

    var in_node = false;
    var state: struct {
        compatible: ?[]const u8 = null,
        reg_shift: ?u4 = null,
        reg: ?u64 = null,
    } = undefined;

    var address_cells: ?u32 = null;
    var size_cells: ?u32 = null;

    var ev = try traverser.event();
    while (ev != .End) : (ev = try traverser.event()) {
        if (!in_node) {
            switch (ev) {
                .BeginNode => |name| {
                    if (std.mem.startsWith(u8, name, "pl011@") or
                        std.mem.startsWith(u8, name, "serial@") or
                        std.mem.startsWith(u8, name, "uart@"))
                    {
                        in_node = true;
                        state = .{};
                    }
                },
                .Prop => |prop| {
                    if (std.mem.eql(u8, prop.name, "#address-cells") and address_cells == null) {
                        address_cells = readU32(prop.value);
                    } else if (std.mem.eql(u8, prop.name, "#size-cells") and size_cells == null) {
                        size_cells = readU32(prop.value);
                    }
                },
                else => {},
            }
        } else switch (ev) {
            .Prop => |prop| {
                if (std.mem.eql(u8, prop.name, "reg") and address_cells != null and size_cells != null) {
                    state.reg = try firstReg(address_cells.?, prop.value);
                } else if (std.mem.eql(u8, prop.name, "status")) {
                    if (!std.mem.eql(u8, prop.value, "okay\x00")) {
                        in_node = false;
                    }
                } else if (std.mem.eql(u8, prop.name, "compatible")) {
                    state.compatible = prop.value;
                } else if (std.mem.eql(u8, prop.name, "reg-shift")) {
                    state.reg_shift = @as(u4, @truncate(readU32(prop.value)));
                }
            },
            .BeginNode => in_node = false,
            .EndNode => {
                in_node = false;
                const reg = state.reg orelse continue;
                const compatible = state.compatible orelse continue;
                const kind = if (std.mem.indexOf(u8, compatible, "arm,pl011\x00") != null)
                    UartKind.ArmPl011
                else if (std.mem.indexOf(u8, compatible, "snps,dw-apb-uart\x00") != null)
                    UartKind.SnpsDwApbUart
                else if (std.mem.indexOf(u8, compatible, "ns16550a\x00") != null)
                    UartKind.Ns16550a
                else if (std.mem.indexOf(u8, compatible, "sifive,uart0\x00") != null)
                    UartKind.SifiveUart0
                else
                    continue;
                return Uart{
                    .base = reg,
                    .reg_shift = state.reg_shift orelse 0,
                    .kind = kind,
                };
            },
            else => {},
        }
    }

    return error.UartNotFound;
}

fn readU32(value: []const u8) u32 {
    // align to: @alignOf(u32)
    return std.mem.bigToNative(u32, @as(*const u32, @ptrCast(@alignCast(value.ptr))).*);
}

fn firstReg(address_cells: u32, value: []const u8) !u64 {
    if (value.len % @sizeOf(u32) != 0) {
        return error.BadStructure;
    }
    // align to: @alignOf(u32)
    const big_endian_cells: []const u32 = @as([*]const u32, @ptrCast(@alignCast(value.ptr)))[0 .. value.len / @sizeOf(u32)];
    if (address_cells == 1) {
        return std.mem.bigToNative(u32, big_endian_cells[0]);
    } else if (address_cells == 2) {
        return @as(u64, std.mem.bigToNative(u32, big_endian_cells[0])) << 32 | std.mem.bigToNative(u32, big_endian_cells[1]);
    }
    return error.UnsupportedCells;
}
