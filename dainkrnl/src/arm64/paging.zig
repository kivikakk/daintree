const std = @import("std");
pub const paging = @import("../paging.zig");
const dcommon = @import("../common/dcommon.zig");
const hw = @import("../hw.zig");

pub var TTBR0_IDENTITY: *PageTable = undefined;
pub var K_DIRECTORY: *PageTable = undefined;

pub const PAGING = paging.configuration(.{
    .vaddress_mask = 0x0000007f_fffff000,
});
comptime {
    std.debug.assert(dcommon.daintree_kernel_start == PAGING.kernel_base);
}

fn flagsToU64(size: paging.MapSize, flags: paging.MapFlags) u64 {
    return @as(u64, switch (size) {
        .block => 0 << 1,
        .table => 1 << 1,
    }) | switch (flags) {
        .non_leaf => KERNEL_DATA_FLAGS.toU64(),

        .kernel_promisc => KERNEL_PROMISC_FLAGS.toU64(),

        .kernel_data => KERNEL_DATA_FLAGS.toU64(),
        .kernel_rodata => KERNEL_RODATA_FLAGS.toU64(),
        .kernel_code => KERNEL_CODE_FLAGS.toU64(),
        .peripheral => PERIPHERAL_FLAGS.toU64(),
    };
}

pub fn flushTLB() void {
    asm volatile (
        \\tlbi vmalle1
        \\dsb ish
        \\isb
        ::: "memory");
}

pub fn mapPage(phys_address: usize, flags: paging.MapFlags) paging.Error!usize {
    return K_DIRECTORY.mapFreePage(1, PAGING.kernel_base, phys_address, flags) orelse error.OutOfMemory;
}

pub const PageTable = packed struct {
    entries: [PAGING.index_size]u64,
    virts: [PAGING.index_size]usize,

    pub fn map(self: *PageTable, index: usize, phys_address: usize, size: paging.MapSize, flags: paging.MapFlags) void {
        self.entries[index] = phys_address | flagsToU64(size, flags);
    }

    pub fn setVirt(self: *PageTable, index: usize, virt_address: usize) void {
        self.virts[index] = virt_address;
    }

    pub fn mapFreePage(self: *PageTable, comptime level: u2, base_address: usize, phys_address: usize, flags: paging.MapFlags) ?usize {
        var i: usize = 0;
        if (level < 3) {
            // Recurse into subtables.
            while (i < self.entries.len) : (i += 1) {
                if ((self.entries[i] & 0x1) == 0x0) {
                    var new_phys = paging.bump.alloc(PageTable);
                    self.map(i, @ptrToInt(new_phys), .table, .non_leaf);
                    self.setVirt(i, @ptrToInt(new_phys)); // XXX let's try relying on lower identity mapping
                    flushTLB();
                }

                if ((self.entries[i] & 0x3) == 0x3) {
                    // Valid non-leaf entry
                    if (@intToPtr(*PageTable, self.virts[i]).mapFreePage(
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
                    // Empty page -- allocate to them.
                    self.map(i, phys_address, .table, flags);
                    return base_address + (i << PAGING.page_bits);
                }
            }
        }
        return null;
    }
};

pub const DEVICE_MAIR_INDEX = 1;
pub const MEMORY_MAIR_INDEX = 0;

pub const STACK_PAGES = 16;

pub const KERNEL_PROMISC_FLAGS = ArchPte{ .uxn = 1, .pxn = 0, .af = 1, .sh = .inner_shareable, .ap = .readwrite_no_el0, .attr_index = MEMORY_MAIR_INDEX, .type = .block, .oa = 0 };

comptime {
    std.debug.assert(0x0040000000000701 == KERNEL_PROMISC_FLAGS.toU64());
}

pub const KERNEL_DATA_FLAGS = ArchPte{ .uxn = 1, .pxn = 1, .af = 1, .sh = .inner_shareable, .ap = .readwrite_no_el0, .attr_index = MEMORY_MAIR_INDEX, .type = .block, .oa = 0 };

comptime {
    std.debug.assert(0x00600000_00000701 == KERNEL_DATA_FLAGS.toU64());
}

pub const KERNEL_RODATA_FLAGS = ArchPte{ .uxn = 1, .pxn = 1, .af = 1, .sh = .inner_shareable, .ap = .readonly_no_el0, .attr_index = MEMORY_MAIR_INDEX, .type = .block, .oa = 0 };

comptime {
    std.debug.assert(0x00600000_00000781 == KERNEL_RODATA_FLAGS.toU64());
}

pub const KERNEL_CODE_FLAGS = ArchPte{ .uxn = 1, .pxn = 0, .af = 1, .sh = .inner_shareable, .ap = .readonly_no_el0, .attr_index = MEMORY_MAIR_INDEX, .type = .block, .oa = 0 };

comptime {
    std.debug.assert(0x00400000_00000781 == KERNEL_CODE_FLAGS.toU64());
}

pub const PERIPHERAL_FLAGS = ArchPte{ .uxn = 1, .pxn = 1, .af = 1, .sh = .outer_shareable, .ap = .readwrite_no_el0, .attr_index = DEVICE_MAIR_INDEX, .type = .block, .oa = 0 };

comptime {
    std.debug.assert(0x00600000_00000605 == PERIPHERAL_FLAGS.toU64());
}

// Avoiding packed structs since they're simply broken right now.
// (was getting @bitSizeOf(x) == 64 but @sizeOf(x) == 9 (!!) --
// wisdom is to avoid for now.)

// ref Figure D5-15
pub const ArchPte = struct {
    pub const OA_MASK: u64 = 0x7ffff << 29;
    pub fn toU64(pte: ArchPte) callconv(.Inline) u64 {
        return @as(u64, pte.valid) |
            (@as(u64, @enumToInt(pte.type)) << 1) |
            (@as(u64, pte.attr_index) << 2) |
            (@as(u64, pte.ns) << 5) |
            (@as(u64, @enumToInt(pte.ap)) << 6) |
            (@as(u64, @enumToInt(pte.sh)) << 8) |
            (@as(u64, pte.af) << 10) |
            (@as(u64, pte.oa) << 29) |
            (@as(u64, pte.pxn) << 53) |
            (@as(u64, pte.uxn) << 54);
    }

    valid: u1 = 1,
    type: enum(u1) {
        block = 0,
        table = 1,
    },

    attr_index: u3,
    ns: u1 = 0,
    ap: enum(u2) {
        readwrite_no_el0 = 0b00,
        readwrite_el0_readwrite = 0b01,
        readonly_no_el0 = 0b10,
        readonly_el0_readonly = 0b11,
    },
    sh: enum(u2) {
        inner_shareable = 0b11,
        outer_shareable = 0b10,
    },
    af: u1, // access flag
    // ng: u1 = 0, // ??

    // _res0a: u4 = 0, // OA[51:48]
    // _res0b: u1 = 0, // nT
    // _res0c: u12 = 0,
    oa: u19, // OA[47:29]
    // _res0d: u4 = 0,

    // contiguous: u1 = 0,
    pxn: u1,
    uxn: u1,
    // _resa: u4 = 0,
    // _res0b: u4 = 0,
    // _resb: u1 = 0,
};

pub const TCR_EL1 = struct {
    pub fn toU64(tcr: TCR_EL1) callconv(.Inline) u64 {
        return @as(u64, tcr.t0sz) |
            (@as(u64, tcr.epd0) << 7) |
            (@as(u64, tcr.irgn0) << 8) |
            (@as(u64, tcr.orgn0) << 10) |
            (@as(u64, tcr.sh0) << 12) |
            (@as(u64, @enumToInt(tcr.tg0)) << 14) |
            (@as(u64, tcr.t1sz) << 16) |
            (@as(u64, tcr.a1) << 22) |
            (@as(u64, tcr.epd1) << 23) |
            (@as(u64, tcr.irgn1) << 24) |
            (@as(u64, tcr.orgn1) << 26) |
            (@as(u64, tcr.sh1) << 28) |
            (@as(u64, @enumToInt(tcr.tg1)) << 30) |
            (@as(u64, @enumToInt(tcr.ips)) << 32);
    }

    t0sz: u6, // TTBR0_EL1 addresses 2**(64-25)
    // _res0a: u1 = 0,
    epd0: u1 = 0, // enable TTBR0_EL1 walks (set = 1 to *disable*)
    irgn0: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn0: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh0: u2 = 0b11, // inner-shareable
    tg0: enum(u2) {
        K4 = 0b00,
        K16 = 0b10,
        K64 = 0b01,
    },
    t1sz: u6, // TTBR1_EL1 addresses 2**(64-25): 0xffffff80_00000000
    a1: u1 = 0, // TTBR0_EL1.ASID defines the ASID
    epd1: u1 = 0, // enable TTBR1_EL1 walks (set = 1 to *disable*)
    irgn1: u2 = 0b01, // "Normal, Inner Wr.Back Rd.alloc Wr.alloc Cacheble"
    orgn1: u2 = 0b01, // "Normal, Outer Wr.Back Rd.alloc Wr.alloc Cacheble"
    sh1: u2 = 0b11, // inner-shareable
    tg1: enum(u2) { // granule size for TTBR1_EL1
        K4 = 0b10,
        K16 = 0b01,
        K64 = 0b11,
    },
    ips: enum(u3) {
        B32 = 0b000,
        B36 = 0b001,
        B48 = 0b101,
    },
    // _res0b: u1 = 0,
    // _as: u1 = 0,
    // tbi0: u1 = 0, // top byte ignored
    // tbi1: u1 = 0,
    // _ha: u1 = 0,
    // _hd: u1 = 0,
    // _hpd0: u1 = 0,
    // _hpd1: u1 = 0,
    // _hwu: u8 = 0,
    // _tbid0: u1 = 0,
    // _tbid1: u1 = 0,
    // _nfd0: u1 = 0,
    // _nfd1: u1 = 0,
    // _res0c: u9 = 0,
};

pub const MAIR_EL1 = struct {
    index: u3,
    attrs: u8,

    pub fn toU64(mair_el1: MAIR_EL1) callconv(.Inline) u64 {
        return @as(u64, mair_el1.attrs) << (@as(u6, mair_el1.index) * 8);
    }
};

comptime {
    if (@bitSizeOf(ArchPte) != 64) {
        // @compileLog("ArchPte misshapen; ", @bitSizeOf(ArchPte));
    }
    if (@sizeOf(ArchPte) != 8) {
        // @compileLog("ArchPte misshapen; ", @sizeOf(ArchPte));
    }

    if (@bitSizeOf(TCR_EL1) != 64) {
        // @compileLog("TCR_EL1 misshapen; ", @bitSizeOf(TCR_EL1));
    }
}
