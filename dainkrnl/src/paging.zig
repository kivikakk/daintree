const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const arch_paging = switch (dcommon.daintree_arch) {
    .arm64 => @import("arm64/paging.zig"),
    .riscv64 => @import("riscv64/paging.zig"),
};
const hw = @import("hw.zig");

pub const Error = error{OutOfMemory};
pub const PAGING = arch_paging.PAGING;

pub const MapSize = enum {
    block,
    table,
};

pub const MapFlags = enum {
    non_leaf,
    kernel_promisc,
    kernel_data,
    kernel_rodata,
    kernel_code,
    peripheral,
};

pub const mapPage = arch_paging.mapPage;

pub var bump = BumpAllocator{ .next = 0 };

pub fn mapPagesConsecutive(base_in: usize, page_count_in: usize, flags: MapFlags) Error!usize {
    var base = base_in;
    var page_count = page_count_in - 1;

    const first = try mapPage(base, flags);
    var last = first;
    while (page_count > 0) : (page_count -= 1) {
        base += PAGING.page_size;
        const next = try mapPage(base, flags);
        if (next - last != PAGING.page_size) {
            @panic("mapPagesConsecutive wasn't consecutive");
        }
        last = next;
    }
    arch_paging.flushTLB();
    return first;
}

pub const BumpAllocator = struct {
    next: usize,

    pub inline fn allocSz(self: *BumpAllocator, comptime size: usize) usize {
        const next = self.next;
        self.next += size;
        // XXX this only works if physical addresses are mapped, i.e. MMU is off
        // or identity mapping is in place
        @memset(@as([*]u8, @ptrFromInt(next))[0..size], 0);
        return next;
    }

    pub inline fn allocPage(self: *BumpAllocator) usize {
        return self.allocSz(PAGING.page_size);
    }

    pub inline fn alloc(self: *BumpAllocator, comptime T: type) *T {
        return @as(*T, @ptrFromInt(self.allocSz(@sizeOf(T))));
    }
};

pub const PagingConfigurationInput = struct {
    translation_levels: u2 = 3,
    index_bits: u6 = 9,
    page_bits: u6 = 12,

    vaddress_mask: u64,
};

pub fn configuration(comptime config: PagingConfigurationInput) PagingConfiguration {
    const page_size = 1 << config.page_bits;
    const page_mask = page_size - 1;
    const block_l1_bits = config.page_bits + (config.translation_levels - 1) * config.index_bits;

    return .{
        .translation_levels = config.translation_levels,
        .index_bits = config.index_bits,
        .page_bits = config.page_bits,
        .vaddress_mask = config.vaddress_mask,

        .page_size = page_size,
        .page_mask = page_mask,
        .index_size = 1 << config.index_bits,
        .address_bits = config.page_bits + config.translation_levels * config.index_bits,
        .kernel_base = ~@as(u64, config.vaddress_mask | page_mask),

        .block_l1_bits = block_l1_bits,
        .block_l1_size = 1 << block_l1_bits,
    };
}

pub const PagingConfiguration = struct {
    translation_levels: u2 = 3,
    index_bits: u6 = 9,
    page_bits: u6 = 12,

    vaddress_mask: u64,

    // computed

    page_size: u64,
    page_mask: u64,
    index_size: u64,
    address_bits: u8,
    kernel_base: u64,

    block_l1_bits: u8,
    block_l1_size: u64,

    pub inline fn index(self: PagingConfiguration, comptime level: u2, va: u64) usize {
        if (level == 0) {
            @compileError("level must be 1, 2, 3");
        }

        return (va & self.vaddress_mask) >> (@as(u6, 3 - level) * self.index_bits + self.page_bits);
    }

    pub fn range(self: PagingConfiguration, comptime level: u2, start_va: u64, length: u64) RangeIterator {
        return .{
            .next_page = self.index(level, start_va),
            .last_page = self.index(level, start_va + length),
            .level_bits = @as(u6, 3 - level) * self.index_bits + self.page_bits,
        };
    }

    pub const RangeIterator = struct {
        next_page: usize,
        last_page: usize,
        level_bits: u6,

        pub fn next(self: *RangeIterator) ?Range {
            if (self.next_page > self.last_page) {
                return null;
            }
            const page = self.next_page;
            self.next_page += 1;
            return Range{
                .page = page,
                .address = page << self.level_bits,
            };
        }
    };

    pub const Range = struct {
        page: usize,
        address: usize,
    };

    pub inline fn kernelPageAddress(self: PagingConfiguration, i: usize) u64 {
        return self.kernel_base | (i << self.page_bits);
    }
};
