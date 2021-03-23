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

fn flagsToRWX(flags: paging.MapFlags) RWX {
    return switch (flags) {
        .non_leaf => RWX.non_leaf,

        .kernel_promisc => RWX.rwx,

        .kernel_data => RWX.rw,
        .kernel_rodata => RWX.ro,
        .kernel_code => RWX.rx,
        .peripheral => RWX.rw,
    };
}

pub fn flushTLB() void {
    asm volatile ("sfence.vma" ::: "memory");
}

pub fn mapPage(phys_address: usize, flags: paging.MapFlags) paging.Error!usize {
    // XXX yikes
    return @intToPtr(*PageTable, K_DIRECTORY.virts[256]).mapFreePage(2, PAGING.kernel_base, phys_address, flags) orelse error.OutOfMemory;
}

pub const PageTable = packed struct {
    entries: [PAGING.index_size]u64,
    virts: [PAGING.index_size]usize,

    pub fn map(self: *PageTable, index: usize, phys_address: usize, flags: paging.MapFlags) void {
        self.entries[index] = (ArchPte{
            .rwx = flagsToRWX(flags),
            .u = 0,
            .g = 0,
            .a = 1, // XXX ???
            .d = 1, // XXX ???
            .ppn = @truncate(u44, phys_address >> PAGING.page_bits),
        }).toU64();
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
                    hw.entry_uart.carefully(.{ "mapFreePage(", @ptrToInt(self), "): level ", level, " base ", base_address, " phys ", phys_address, "\r\n" });
                    hw.entry_uart.carefully(.{ "  empty table at i = ", i, " (entry is ", self.entries[i], ")\r\n" });
                    @panic("empty table");
                }

                if ((self.entries[i] & 0x3) == 0x3) {
                    // Valid table

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
                    // Empty page -- allocate.
                    self.map(i, phys_address, flags);
                    return base_address + (i << PAGING.page_bits);
                }
            }
        }
        return null;
    }
};

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

pub const ArchPte = struct {
    pub fn toU64(pte: ArchPte) callconv(.Inline) u64 {
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
