const std = @import("std");
const printf = @import("framebuffer.zig").printf;
const paging = @import("paging.zig");

pub fn init(
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
) void {
    for (memory_map[0 .. memory_map_size / descriptor_size]) |ptr, i| {
        if (ptr.type == .ConventionalMemory) {
            printf("{:2} {s:23} p=0x{x:0>16} size={:16}\n", .{ i, @tagName(ptr.type), ptr.physical_start, ptr.number_of_pages << 12 });
        }
    }

    var i: u19 = 0;
    while (i < 8192) : (i += 1) {
        PAGE_TABLE_0[i] = (paging.PageTableEntry{ .oa = i }).toU64();
        PAGE_TABLE_1[i] = (paging.PageTableEntry{ .oa = i }).toU64();

        if (i < 2) {
            printf("PTE{}: {x:0>16}\n", .{ i, PAGE_TABLE_0[i] });
        }
    }

    const tcr_el1 = (paging.TCR_EL1{}).toU64();
    printf("TCR_EL: {x:0>16}\n", .{tcr_el1});
}

pub var PAGE_TABLE_0: [8192]u64 align(8192) = undefined;
pub var PAGE_TABLE_1: [8192]u64 align(8192) = undefined;
