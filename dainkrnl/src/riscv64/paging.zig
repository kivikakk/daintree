const std = @import("std");
pub const paging = @import("../paging.zig");
const dcommon = @import("../common/dcommon.zig");
const hw = @import("../hw.zig");

pub var K_DIRECTORY: *PageTable = undefined;

pub const PAGING = paging.configuration(.{
    .vaddress_mask = 0x0000003f_fffff000,
});
comptime {
    std.debug.assert(dcommon.daintree_kernel_start == PAGING.kernel_base);
}

inline fn flagsToRWX(flags: paging.MapFlags) RWX {
    // switch here caused absolute jumps ...
    if (flags == .non_leaf) return RWX.non_leaf;
    if (flags == .kernel_promisc) return RWX.rwx;
    if (flags == .kernel_data) return RWX.rw;
    if (flags == .kernel_rodata) return RWX.ro;
    if (flags == .kernel_code) return RWX.rx;
    if (flags == .peripheral) return RWX.rw;
    unreachable;
}

pub fn flushTLB() void {
    asm volatile ("sfence.vma" ::: "memory");
}

pub fn mapPage(phys_address: usize, flags: paging.MapFlags) paging.Error!usize {
    return K_DIRECTORY.pageAt(256).mapFreePage(2, PAGING.kernel_base, phys_address, flags) orelse error.OutOfMemory;
}

pub const PageTable = extern struct {
    entries: [PAGING.index_size]u64,

    pub inline fn map(self: *PageTable, index: usize, phys_address: usize, flags: paging.MapFlags) void {
        // hw.entry_uart.carefully(.{
        //     "mapping self ", @intFromPtr(self),
        //     " index ", index,
        //     " phys ", phys_address,
        //     " flags ", @enumToInt(flagsToRWX(flags)),
        //     "\r\n",
        // });

        // A/D must not be set on non-leaf.
        // https://github.com/qemu/qemu/commit/b6ecc63c569bb88c0fcadf79fb92bf4b88aefea8
        const ad: u1 = if (flags != .non_leaf) 1 else 0;
        self.entries[index] = (ArchPte{
            .rwx = flagsToRWX(flags),
            .u = 0,
            .g = 0,
            .a = ad,
            .d = ad,
            .ppn = @as(u44, @truncate(phys_address >> PAGING.page_bits)),
        }).toU64();
    }

    pub fn mapFreePage(self: *PageTable, comptime level: u2, base_address: usize, phys_address: usize, flags: paging.MapFlags) ?usize {
        var i: usize = 0;
        if (level < 3) {
            // Recurse into subtables.
            while (i < self.entries.len) : (i += 1) {
                if ((self.entries[i] & 0x1) == 0x0) {
                    const new_phys = paging.bump.alloc(PageTable);
                    self.map(i, @intFromPtr(new_phys), .non_leaf);
                }

                if ((self.entries[i] & 0xf) == 0x1) {
                    // Valid non-leaf entry
                    if (self.pageAt(i).mapFreePage(
                        level + 1,
                        base_address + (i << (PAGING.page_bits + PAGING.index_bits * (3 - level))),
                        phys_address,
                        flags,
                    )) |addr| {
                        return addr;
                    }
                }
            }
        } else {
            while (i < self.entries.len) : (i += 1) {
                if ((self.entries[i] & 0x1) == 0) {
                    // Empty page -- allocate.
                    self.map(i, phys_address, flags);
                    return base_address + (i << PAGING.page_bits);
                }
            }
        }
        return null;
    }

    fn pageAt(self: *const PageTable, index: usize) *PageTable {
        const entry = self.entries[index];
        if ((entry & 0xf) != 0x1) @panic("pageAt on non-page");
        return @as(*PageTable, @ptrFromInt(((entry & ArchPte.PPN_MASK) >> ArchPte.PPN_OFFSET) << PAGING.page_bits));
    }
};

comptime {
    std.debug.assert(@sizeOf(PageTable) == 4096);
}

pub const STACK_PAGES = 16;

pub const SATP = struct {
    pub inline fn toU64(satp: SATP) u64 {
        return @as(u64, satp.ppn) |
            (@as(u64, satp.asid) << 44) |
            (@as(u64, @intFromEnum(satp.mode)) << 60);
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

pub const ArchPte = struct {
    pub const PPN_MASK: u64 = 0x003fffff_fffffc00;
    pub const PPN_OFFSET = 10;
    pub inline fn toU64(pte: ArchPte) u64 {
        return @as(u64, pte.v) |
            (@as(u64, @intFromEnum(pte.rwx)) << 1) |
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
