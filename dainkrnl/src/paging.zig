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
    // XXX: not guaranteed consecutive.
    var base = base_in;
    var page_count = page_count_in - 1;

    var first = try mapPage(base, flags);
    hw.entry_uart.carefully(.{ "FB: ", first, "\r\n" });
    while (page_count > 0) : (page_count -= 1) {
        base += PAGING.page_size;
        const n = try mapPage(base, flags);
        hw.entry_uart.carefully(.{ "FB~ ", n, "\r\n" });
    }
    asm volatile (
        \\tlbi vmalle1
        \\dsb ish
        \\isb
        ::: "memory");
    return first;
}

pub const BumpAllocator = struct {
    next: usize,

    fn allocSz(self: *BumpAllocator, comptime size: usize) callconv(.Inline) usize {
        const next = self.next;
        self.next += size;
        std.mem.set(u8, @intToPtr([*]u8, next)[0..size], 0); // Can only do this if in phys mode.
        return next;
    }

    pub fn alloc(self: *BumpAllocator, comptime T: type) callconv(.Inline) *T {
        return @intToPtr(*T, self.allocSz(@sizeOf(T)));
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

    pub fn index(self: PagingConfiguration, comptime level: u2, va: u64) callconv(.Inline) usize {
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

    pub fn kernelPageAddress(self: PagingConfiguration, i: usize) callconv(.Inline) u64 {
        return self.kernel_base | (i << self.page_bits);
    }
};
