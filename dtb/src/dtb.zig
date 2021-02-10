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

pub const Error = error{
    Truncated,
    BadMagic,
    UnsupportedVersion,
    BadStructure,
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
    name: []u8,
    props: []Prop,
    children: []Node,
};

pub fn parse(allocator: *mem.Allocator, fdt: []const u8) Error!u64 {
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

    // iterate memory reservations
    // XXX These appear unused? Maybe past versions of DTBs relied on them more.
    const memRsvBlock = @ptrCast([*]const FDTReserveEntry, fdt[header.off_mem_rsvmap..].ptr);
    var i: usize = 0;
    while (memRsvBlock[i].address != 0 or memRsvBlock[i].size != 0) : (i += 1) {
        const block = bigToNative(FDTReserveEntry, memRsvBlock[i]);
        std.debug.print("mem rsv {}: 0x{x:0>16} sz 0x{x:0>16}\n", .{ i, block.address, block.size });
    }

    var memoryOffset: ?usize = null;
    var memorySize: ?usize = null;

    var addressCells: ?u32 = null;
    var sizeCells: ?u32 = null;

    var index = fdt[header.off_dt_struct..];
    var depth: usize = 0;
    loop: while (true) {
        var token = @intToEnum(FDTToken, std.mem.bigToNative(u32, @ptrCast(*const u32, @alignCast(@alignOf(u32), index.ptr)).*));
        index = index[@sizeOf(u32)..];
        switch (token) {
            .BeginNode => {
                depth += 1;
                var name_end: usize = 0;
                while (index[name_end] != 0) : (name_end += 1) {}
                const name = index[0..name_end];
                var j: usize = 0;
                while (j < depth) : (j += 1) {
                    std.debug.print("*", .{});
                }
                std.debug.print(" {s}\n", .{name});
                name_end += 1; // NUL byte
                index = index[(name_end + 3) & ~@as(usize, 3) ..];
            },
            .EndNode => {
                if (depth == 0) {
                    return error.BadStructure;
                }
                depth -= 1;
            },
            .Prop => {
                const prop = bigToNative(FDTProp, @ptrCast(*const FDTProp, index.ptr).*);
                var j: usize = 0;
                while (j < depth) : (j += 1) {
                    std.debug.print(" ", .{});
                }
                const name_len = std.mem.lenZ(@ptrCast([*c]const u8, fdt[header.off_dt_strings + prop.nameoff ..]));
                const name = fdt[header.off_dt_strings + prop.nameoff ..][0..name_len];
                std.debug.print("  - {s}: {} bytes\n", .{ name, prop.len });
                index = index[@sizeOf(FDTProp)..];
                const prop_value = index[0..prop.len];
                j = 0;
                while (j < depth) : (j += 1) {
                    std.debug.print(" ", .{});
                }
                std.debug.print("    ", .{});
                if (std.mem.eql(u8, name, "#address-cells")) {
                    // only paying attention to root #address/#size-cells for now
                    if (addressCells == null) {
                        addressCells = std.mem.bigToNative(u32, propertyValue("#address-cells", prop_value));
                        std.debug.print("{} x u32 ({} bits)\n", .{ addressCells.?, addressCells.? * 32 });
                    }
                } else if (std.mem.eql(u8, name, "#size-cells")) {
                    if (sizeCells == null) {
                        sizeCells = std.mem.bigToNative(u32, propertyValue("#size-cells", prop_value));
                        std.debug.print("{} x u32 ({} bits)\n", .{ sizeCells.?, sizeCells.? * 32 });
                    }
                } else if (std.mem.eql(u8, name, "reg")) {
                    var off: usize = 0;
                } else {
                    std.debug.print("\"{s}\"\n", .{prop_value});
                }
                index = index[(prop.len + 3) & ~@as(usize, 3) ..];
            },
            .Nop => {},
            .End => {
                if (depth != 0 or index.ptr != fdt[header.off_dt_struct + header.size_dt_struct ..].ptr) {
                    return error.BadStructure;
                }
                break :loop;
            },
        }
    }

    return 7;
}

const qemu_dtb = @embedFile("../qemu.dtb");
const rockpro64_dtb = @embedFile("../rk3399-rockpro64.dtb");

test "basic add functionality" {
    // QEMU places memory at 1GiB.
    testing.expectEqual(@as(u64, 0x40000000), try parseAndGetMemoryOffset(qemu_dtb));
    // Rockpro64 at ?
    testing.expectEqual(@as(u64, 123), try parseAndGetMemoryOffset(rockpro64_dtb));
}
