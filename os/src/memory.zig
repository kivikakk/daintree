const std = @import("std");
const paging = @import("paging.zig");
const entry = @import("entry.zig");
comptime {
    _ = @import("exception.zig");
}

pub export fn daintree_start(
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    fb: [*]u32,
    fb_vert: u32,
    fb_horiz: u32,
) void {
    const tcr_el1 = comptime (paging.TCR_EL1{
        .ips = .B36,
        .tg1 = .K4,
        .t1sz = 64 - ADDRESS_BITS, // in practice: 25
        .tg0 = .K4,
        .t0sz = 64 - ADDRESS_BITS,
    }).toU64();
    comptime std.testing.expectEqual(0x00000001_b5193519, tcr_el1);
    write_register(.TCR_EL1, tcr_el1);

    const mair_el1 = comptime (paging.MAIR_EL1{ .index = DEVICE_MAIR_INDEX, .attrs = 0b00 }).toU64() |
        (paging.MAIR_EL1{ .index = MEMORY_MAIR_INDEX, .attrs = 0b11111111 }).toU64();
    comptime std.testing.expectEqual(0x00000000_000000ff, mair_el1);
    write_register(.MAIR_EL1, mair_el1);

    var daintree_base: u64 = asm volatile ("adr %[ret], __daintree_base"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );
    var daintree_rodata_base: u64 = asm volatile ("adr %[ret], __daintree_rodata_base"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );
    var daintree_data_base: u64 = asm volatile ("adr %[ret], __daintree_data_base"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );
    var daintree_end: u64 = asm volatile ("adr %[ret], __daintree_end"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );

    comptime {
        std.testing.expectEqual(@sizeOf([INDEX_SIZE]u64), PAGE_SIZE);
    }
    TTBR0_IDENTITY = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 0);
    TTBR1_L1 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 1);
    TTBR1_L2 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 2);
    TTBR1_L3 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 3);

    const ttbr0_el1 = @ptrToInt(TTBR0_IDENTITY) | 1;
    const ttbr1_el1 = @ptrToInt(TTBR1_L1) | 1;
    write_register(.TTBR0_EL1, ttbr0_el1);
    write_register(.TTBR1_EL1, ttbr1_el1);

    {
        const memory_base: u64 = 0x4000_0000;
        const memory_end: u64 = memory_base + 512 * 1048576;

        const l1_start = comptime index(1, memory_base);
        const l1_end = comptime index(1, memory_end);
        comptime std.testing.expectEqual(1, l1_start);
        comptime std.testing.expectEqual(1, l1_end);

        var l1_i = l1_start;
        var l1_address = memory_base;
        while (l1_i <= l1_end) : (l1_i += 1) {
            tableSet(TTBR0_IDENTITY, l1_i, l1_address, IDENTITY_FLAGS.toU64());
            l1_address += BLOCK_L1_SIZE;
        }
    }

    // user not kernel?
    tableSet(TTBR1_L1, 0, @ptrToInt(TTBR1_L2), KERNEL_DATA_TABLE.toU64());
    tableSet(TTBR1_L2, 0, @ptrToInt(TTBR1_L3), KERNEL_DATA_TABLE.toU64());

    var end = (daintree_end - daintree_base) >> PAGE_BITS;
    if (end > 512) {
        while (true) {}
    }

    var address = daintree_base;
    var flags = KERNEL_CODE_TABLE.toU64();
    var i: u64 = 0;
    while (i < end) : (i += 1) {
        if (address >= daintree_data_base) {
            flags = KERNEL_DATA_TABLE.toU64();
        } else if (address >= daintree_rodata_base) {
            flags = KERNEL_RODATA_TABLE.toU64();
        }
        tableSet(TTBR1_L3, i, address, flags);
        address += PAGE_SIZE;
    }

    // i = end
    end += 4;
    while (i < end) : (i += 1) {
        tableSet(TTBR1_L3, i, 0, 0);
        address += PAGE_SIZE;
    }
    end = i + STACK_PAGES;
    while (i < end) : (i += 1) {
        tableSet(TTBR1_L3, i, address, KERNEL_DATA_TABLE.toU64());
        address += PAGE_SIZE;
    }

    // address now points to the stack. make space for EntryData, align.
    address -= @sizeOf(entry.EntryData);
    address &= ~@as(u64, 15);
    @intToPtr(*entry.EntryData, address).* = .{
        .memory_map = memory_map,
        .memory_map_size = memory_map_size,
        .descriptor_size = descriptor_size,
        .fb = fb,
        .fb_vert = fb_vert,
        .fb_horiz = fb_horiz,
    };

    const daintree_main = asm volatile ("adr %[ret], daintree_main"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );

    const vbar_el1 = asm volatile ("adr %[ret], __vbar_el1"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );

    var new_sp = KERNEL_BASE | (end << PAGE_BITS);
    new_sp -= @sizeOf(entry.EntryData);
    new_sp &= ~@as(u64, 15);

    asm volatile (
        \\mov sp, %[sp]
        \\mov lr, %[lr]
        \\msr VBAR_EL1, %[vbar_el1]
        \\mov x0, %[sp]
        \\mrs x1, SCTLR_EL1
        \\orr x1, x1, #1
        \\msr SCTLR_EL1, x1
        \\tlbi vmalle1
        \\dsb ish
        \\isb
        \\ret
        :
        : [sp] "r" (new_sp),
          [lr] "r" (daintree_main - daintree_base + KERNEL_BASE),
          [vbar_el1] "r" (vbar_el1 - daintree_base + KERNEL_BASE)
        : "volatile"
    );

    // unreachable;
}

inline fn index(comptime level: u2, va: u64) usize {
    if (level == 0) {
        @compileError("level must be 1, 2, 3");
    }

    return (va & VADDRESS_MASK) >> (@as(u8, 3 - level) * INDEX_BITS + PAGE_BITS);
}

inline fn tableSet(table: []u64, ix: usize, address: u64, flags: u64) void {
    table[ix] = address | flags;
}

const Register = enum { MAIR_EL1, TCR_EL1, TTBR0_EL1, TTBR1_EL1, SCTLR_EL1 };
inline fn write_register(comptime register: Register, value: u64) void {
    asm volatile ("msr " ++ @tagName(register) ++ ", x0"
        :
        : [value] "{x0}" (value)
        : "memory"
    );
}

inline fn read_register(comptime register: Register) u64 {
    return asm volatile ("mrs x0, " ++ @tagName(register)
        : [ret] "={x0}" (-> u64)
    );
}

inline fn or_register(comptime register: Register, value: u64) void {
    asm volatile ("mrs x0, " ++ @tagName(register) ++ "\n" ++
            "orr x0, x0, x1\n" ++
            "msr " ++ @tagName(register) ++ ", x0\n"
        :
        : [value] "{x1}" (value)
        : "memory"
    );
}

const DEVICE_MAIR_INDEX = 1;
const MEMORY_MAIR_INDEX = 0;

const PAGE_BITS = 12;
const PAGE_SIZE = 1 << PAGE_BITS; // 4096 (= 512 * 8)
const PAGE_MASK = PAGE_SIZE - 1;

const BLOCK_L1_BITS = 30;
const BLOCK_L1_SIZE = 1 << BLOCK_L1_BITS;

const INDEX_BITS = 9;
const INDEX_SIZE = 1 << INDEX_BITS; // 512

const TRANSLATION_LEVELS = 3;
const ADDRESS_BITS = PAGE_BITS + TRANSLATION_LEVELS * INDEX_BITS;

const VADDRESS_MASK = 0x0000007f_fffff000;

const KERNEL_BASE = ~@as(u64, VADDRESS_MASK | PAGE_MASK);
comptime {
    std.testing.expectEqual(0xffffff80_00000000, KERNEL_BASE);
}
const STACK_PAGES = 4;

const IDENTITY_FLAGS = paging.PageTableEntry{
    .uxn = 1,
    .pxn = 0,
    .af = 1,
    .sh = .inner_shareable,
    .ap = .readwrite_no_el0,
    .attr_indx = MEMORY_MAIR_INDEX,
    .type = .block,
    .oa = 0,
};

comptime {
    std.testing.expectEqual(0x0040000000000701, IDENTITY_FLAGS.toU64());
}

const KERNEL_DATA_TABLE = paging.PageTableEntry{
    .uxn = 1,
    .pxn = 1,
    .af = 1,
    .sh = .inner_shareable,
    .ap = .readwrite_no_el0,
    .attr_indx = MEMORY_MAIR_INDEX,
    .type = .table,
    .oa = 0,
};

comptime {
    std.testing.expectEqual(0x00600000_00000703, KERNEL_DATA_TABLE.toU64());
}

const KERNEL_RODATA_TABLE = paging.PageTableEntry{
    .uxn = 1,
    .pxn = 1,
    .af = 1,
    .sh = .inner_shareable,
    .ap = .readonly_no_el0,
    .attr_indx = MEMORY_MAIR_INDEX,
    .type = .table,
    .oa = 0,
};

comptime {
    std.testing.expectEqual(0x00600000_00000783, KERNEL_RODATA_TABLE.toU64());
}

const KERNEL_CODE_TABLE = paging.PageTableEntry{
    .uxn = 1,
    .pxn = 0,
    .af = 1,
    .sh = .inner_shareable,
    .ap = .readonly_no_el0,
    .attr_indx = MEMORY_MAIR_INDEX,
    .type = .table,
    .oa = 0,
};

comptime {
    std.testing.expectEqual(0x0040000000000783, KERNEL_CODE_TABLE.toU64());
}

var TTBR0_IDENTITY: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L1: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L2: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L3: *[INDEX_SIZE]u64 = undefined;

// pub var TTBR0_IDENTITY: [INDEX_SIZE]u64 align(8192) = [_]u64{0} ** INDEX_SIZE;
// pub var TTBR1_L1: [PAGE_SIZE]u64 align(8192) = std.mem.zeroes([PAGE_SIZE]u64);
// pub var TTBR1_L2: [PAGE_SIZE]u64 align(8192) = std.mem.zeroes([PAGE_SIZE]u64);
// pub var TTBR1_L3: [PAGE_SIZE]u64 align(8192) = std.mem.zeroes([PAGE_SIZE]u64);