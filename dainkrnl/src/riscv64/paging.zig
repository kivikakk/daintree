const std = @import("std");
const paging = @import("../paging.zig");
const dcommon = @import("../common/dcommon.zig");

pub var PT_L1: *[PAGING.index_size]u64 = undefined;
pub var PTS_L2: *[PAGING.index_size]u64 = undefined;
pub var PTS_L3_1: *[PAGING.index_size]u64 = undefined;
pub var PTS_L3_2: *[PAGING.index_size]u64 = undefined;
pub var PTS_L3_3: *[PAGING.index_size]u64 = undefined;

pub fn tableSet(table: []u64, ix: usize, pte: PageTableEntry) void {
    table[ix] = pte.toU64();
}

pub const PAGING = paging.configuration(.{
    .vaddress_mask = 0x0000003f_fffff000,
});
comptime {
    std.debug.assert(dcommon.daintree_kernel_start == PAGING.kernel_base);
}

pub const STACK_PAGES = 16;

pub const SATP = struct {
    pub fn toU64(satp: SATP) callconv(.Inline) u64 {
        return @as(u64, satp.ppn) |
            (@as(u64, satp.asid) << 44) |
            (@as(u64, @enumToInt(satp.mode)) << 60);
    }

    ppn: u44,
    asid: u16,
    mode: enum(u4) {
        bare = 0,
        sv39 = 8,
        sv48 = 9,
    },
};

pub const RWX = enum(u3) {
    non_leaf = 0b000,
    ro = 0b001,
    rw = 0b011,
    rx = 0b101,
    rwx = 0b111,
};

pub const PageTableEntry = struct {
    pub fn toU64(pte: PageTableEntry) callconv(.Inline) u64 {
        return @as(u64, pte.v) |
            (@as(u64, @enumToInt(pte.rwx)) << 1) |
            (@as(u64, pte.u) << 4) |
            (@as(u64, pte.g) << 5) |
            (@as(u64, pte.a) << 6) |
            (@as(u64, pte.d) << 7) |
            (@as(u64, pte.ppn) << 10);
    }

    // Set rwx=000 to indicate a non-leaf PTE.

    v: u1 = 1,
    rwx: RWX,
    u: u1, // Accessible to usermode.
    g: u1, // Global mapping (exists in all address spaces).
    a: u1, // Access bit.
    d: u1, // Dirty bit.
    // _res_rsw: u2,  // Reserved; ignore.
    ppn: u44,
    // _res: u10,
};
