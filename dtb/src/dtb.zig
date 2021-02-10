const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const FDTHeader = packed struct {
    magic: u32,
    totalsize: u32,
    off_dt_struct: u32,
    off_dt_strings: u32,
    off_mem_rsvmap: u32,
    version: u32,
    last_comp_version: u32,
    boot_cpuid_phys: u32,
    size_dt_strings: u32,
    size_dt_struct: u32,
};

const FDTReserveEntry = packed struct {
    address: u64,
    size: u64,
};

const FDTToken = packed enum(u32) {
    BeginNode = 0x00000001,
    EndNode = 0x00000002,
    Prop = 0x00000003,
    Nop = 0x00000004,
    End = 0x00000009,
};

const FDTProp = packed struct {
    len: u32,
    nameoff: u32,
};

pub const Error = mem.Allocator.Error || error{
    Truncated,
    BadMagic,
    UnsupportedVersion,
    BadStructure,
    MissingCells,
    UnsupportedCells,
};

const PropertyTypeMapping = struct {
    property_name: []const u8,
    property_type: type,
};
const PROPERTY_TYPE_MAPPINGS: [2]PropertyTypeMapping = .{
    .{ .property_name = "#address-cells", .property_type = u32 },
    .{ .property_name = "#size-cells", .property_type = u32 },
};

fn PropertyType(comptime property_name: []const u8) type {
    inline for (PROPERTY_TYPE_MAPPINGS) |mapping| {
        if (comptime std.mem.eql(u8, property_name, mapping.property_name)) {
            return mapping.property_type;
        }
    }
    @compileError("unknown property \"" ++ property_name ++ "\"");
}

fn propertyValue(comptime property_name: []const u8, value: []const u8) PropertyType(property_name) {
    const t = PropertyType(property_name);
    return @ptrCast(*const t, @alignCast(@alignOf(t), value.ptr)).*;
}

fn bigToNative(comptime T: type, s: T) T {
    var r = s;
    inline for (std.meta.fields(T)) |field| {
        @field(r, field.name) = std.mem.bigToNative(field.field_type, @field(r, field.name));
    }
    return r;
}

pub const Node = struct {
    name: []const u8,
    props: []Prop,
    children: []Node,

    pub fn deinit(node: Node, allocator: *mem.Allocator) void {
        for (node.props) |prop| {
            prop.deinit(allocator);
        }
        allocator.free(node.props);
        for (node.children) |child| {
            child.deinit(allocator);
        }
        allocator.free(node.children);
    }

    pub fn format(node: Node, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try node.formatNode(writer, 0);
    }

    fn formatNode(node: Node, writer: anytype, depth: usize) std.os.WriteError!void {
        try indent(writer, depth);
        try std.fmt.format(writer, "Node <{s}> ({} props, {} children)\n", .{ node.name, node.props.len, node.children.len });
        for (node.props) |prop| {
            try indent(writer, depth);
            try std.fmt.format(writer, " {}\n", .{prop});
        }
        for (node.children) |child| {
            try child.formatNode(writer, depth + 1);
        }
    }

    fn indent(writer: anytype, depth: usize) !void {
        var i: usize = 0;
        while (i < depth) : (i += 1) {
            try writer.writeAll("  ");
        }
    }
};

pub const Prop = union(enum) {
    AddressCells: u32,
    SizeCells: u32,
    Reg: [][2]u64,
    Unknown: PropUnknown,

    pub fn format(prop: Prop, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (prop) {
            .AddressCells => |v| try std.fmt.format(writer, "#address-cells: 0x{x:0>8}", .{v}),
            .SizeCells => |v| try std.fmt.format(writer, "#size-cells: 0x{x:0>8}", .{v}),
            .Reg => |v| {
                try writer.writeAll("reg: <");
                for (v) |pair, i| {
                    if (i != 0) {
                        try writer.writeByte(' ');
                    }
                    try std.fmt.format(writer, "0x{x} 0x{x}", .{ pair[0], pair[1] });
                }
                try writer.writeByte('>');
            },
            .Unknown => |v| try std.fmt.format(writer, "{s}: {}", .{ v.name, v.value }),
        }
    }

    pub fn deinit(prop: Prop, allocator: *mem.Allocator) void {
        switch (prop) {
            .Reg => |v| allocator.free(v),
            else => {},
        }
    }
};

pub const PropUnknown = struct {
    name: []const u8,
    value: []const u8,
};

const Parser = struct {
    fdt: []const u8,
    header: FDTHeader,
    offset: usize,

    fn aligned(parser: *@This(), comptime T: type) T {
        const size = @sizeOf(T);
        const value = @ptrCast(*const T, @alignCast(@alignOf(T), parser.fdt[parser.offset .. parser.offset + size])).*;
        parser.offset += size;
        return value;
    }

    fn buffer(parser: *@This(), length: usize) []const u8 {
        const value = parser.fdt[parser.offset .. parser.offset + length];
        parser.offset += length;
        return value;
    }

    fn token(parser: *@This()) FDTToken {
        return @intToEnum(FDTToken, std.mem.bigToNative(u32, parser.aligned(u32)));
    }

    fn object(parser: *@This(), comptime T: type) T {
        return bigToNative(T, parser.aligned(T));
    }

    fn cstring(parser: *@This()) []const u8 {
        const length = std.mem.lenZ(@ptrCast([*c]const u8, parser.fdt[parser.offset..]));
        const value = parser.fdt[parser.offset .. parser.offset + length];
        parser.offset += length + 1;
        return value;
    }

    fn cstringFromSectionOffset(parser: @This(), offset: usize) []const u8 {
        const length = std.mem.lenZ(@ptrCast([*c]const u8, parser.fdt[parser.header.off_dt_strings + offset ..]));
        return parser.fdt[parser.header.off_dt_strings + offset ..][0..length];
    }

    fn alignTo(parser: *@This(), comptime T: type) void {
        parser.offset += @sizeOf(T) - 1;
        parser.offset &= ~@as(usize, @sizeOf(T) - 1);
    }
};

pub fn parse(allocator: *mem.Allocator, fdt: []const u8) Error!Node {
    if (fdt.len < @sizeOf(FDTHeader)) {
        return error.Truncated;
    }
    const header = bigToNative(FDTHeader, @ptrCast(*const FDTHeader, fdt.ptr).*);
    if (header.magic != 0xd00dfeed) {
        return error.BadMagic;
    }
    if (fdt.len < header.totalsize) {
        return error.Truncated;
    }
    if (header.version != 17) {
        return error.UnsupportedVersion;
    }

    var parser = Parser{ .fdt = fdt, .header = header, .offset = header.off_dt_struct };
    if (parser.token() != .BeginNode) {
        return error.BadStructure;
    }

    var root = try parseBeginNode(allocator, &parser, null, null);

    if (parser.token() != .End) {
        return error.BadStructure;
    }
    if (parser.offset != header.off_dt_struct + header.size_dt_struct) {
        return error.BadStructure;
    }

    return root;
}

fn parseBeginNode(allocator: *mem.Allocator, parser: *Parser, address_cells_in: ?u32, size_cells_in: ?u32) Error!Node {
    const node_name = parser.cstring();
    parser.alignTo(u32);

    var address_cells = address_cells_in;
    var size_cells = size_cells_in;

    var props = std.ArrayList(Prop).init(allocator);
    var children = std.ArrayList(Node).init(allocator);

    loop: while (true) {
        switch (parser.token()) {
            .BeginNode => {
                var subnode = try parseBeginNode(allocator, parser, address_cells, size_cells);
                try children.append(subnode);
            },
            .EndNode => {
                break :loop;
            },
            .Prop => {
                const prop = parser.object(FDTProp);
                const prop_name = parser.cstringFromSectionOffset(prop.nameoff);
                const prop_value = parser.buffer(prop.len);
                if (std.mem.eql(u8, prop_name, "#address-cells")) {
                    address_cells = std.mem.bigToNative(u32, propertyValue("#address-cells", prop_value));
                    try props.append(Prop{ .AddressCells = address_cells.? });
                } else if (std.mem.eql(u8, prop_name, "#size-cells")) {
                    size_cells = std.mem.bigToNative(u32, propertyValue("#size-cells", prop_value));
                    try props.append(Prop{ .SizeCells = size_cells.? });
                } else if (std.mem.eql(u8, prop_name, "reg")) {
                    if (address_cells == null or size_cells == null) {
                        return error.MissingCells;
                    }
                    if (address_cells.? > 2 or size_cells.? > 2) {
                        return error.UnsupportedCells;
                    }
                    const pair_size = (address_cells.? + size_cells.?) * @sizeOf(u32);
                    if (prop_value.len % pair_size != 0) {
                        return error.BadStructure;
                    }

                    var pairs: [][2]u64 = try allocator.alloc([2]u64, prop_value.len / pair_size);
                    var off: usize = 0;
                    while (off < prop_value.len) {
                        off += address_cells.? * @sizeOf(u32);
                        off += size_cells.? * @sizeOf(u32);
                    }

                    try props.append(Prop{ .Reg = pairs });
                } else {
                    try props.append(Prop{ .Unknown = .{ .name = prop_name, .value = prop_value } });
                }
                parser.alignTo(u32);
            },
            .Nop => {},
            .End => {
                return error.BadStructure;
            },
        }
    }

    return Node{
        .name = node_name,
        .props = props.toOwnedSlice(),
        .children = children.toOwnedSlice(),
    };
}

const qemu_dtb = @embedFile("../qemu.dtb");
const rockpro64_dtb = @embedFile("../rk3399-rockpro64.dtb");

test "basic add functionality" {
    var dtb = try parse(std.testing.allocator, qemu_dtb);
    std.debug.print("====\nqemu\n====\n{}\n\n", .{dtb});
    dtb.deinit(std.testing.allocator);

    dtb = try parse(std.testing.allocator, rockpro64_dtb);
    std.debug.print("=========\nrockpro64\n=========\n{}\n\n", .{dtb});
    dtb.deinit(std.testing.allocator);
    // QEMU places memory at 1GiB.
    // testing.expectEqual(@as(u64, 0x40000000), try parseAndGetMemoryOffset(qemu_dtb));
    // Rockpro64 at ?
    // testing.expectEqual(@as(u64, 123), try parseAndGetMemoryOffset(rockpro64_dtb));
}
