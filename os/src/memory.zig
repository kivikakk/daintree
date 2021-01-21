const std = @import("std");
// const framebuffer = @import("framebuffer.zig");
// const printf = framebuffer.printf;
const paging = @import("paging.zig");
comptime {
    _ = @import("exception.zig");
}

pub fn init(
    // memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    // memory_map_size: usize,
    // descriptor_size: usize,
) void {
    // for (memory_map[0 .. memory_map_size / descriptor_size]) |ptr, i| {
    //     if (ptr.type == .ConventionalMemory) {
    //         printf("{:2} {s:23} p=0x{x:0>16} size={:16}\n", .{ i, @tagName(ptr.type), ptr.physical_start, ptr.number_of_pages << 12 });
    //     }
    // }

    // printf("framebuffer: {x:0>16}\n", .{@ptrToInt(framebuffer.fb)});

    // var i: u19 = 0;
    // while (i < 8192) : (i += 1) {
    //     PAGE_TABLE_0[i] = (paging.PageTableEntry{ .oa = i }).toU64();
    //     PAGE_TABLE_1[i] = (paging.PageTableEntry{ .oa = i }).toU64();

    //     if (i < 2) {
    //         printf("PTE{}: {x:0>16}\n", .{ i, PAGE_TABLE_0[i] });
    //     }
    // }
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

    TTBR0_IDENTITY = @intToPtr(*[INDEX_SIZE]u64, daintree_end);
    const ttbr0_el1 = @ptrToInt(TTBR0_IDENTITY) | 1;
    // printf("TTBR0_EL1: {x:0>16} -> {x:0>16}\n", .{ read_register(.TTBR0_EL1), ttbr0_el1 });
    write_register(.TTBR0_EL1, ttbr0_el1); // 0b1 = CNP, "common not private"

    const memory_base: u64 = 0x4000_0000;
    const memory_end: u64 = memory_base + 512 * 1048576;

    const start = comptime index(1, memory_base);
    const end = comptime index(1, memory_end);
    comptime std.testing.expectEqual(1, start);
    comptime std.testing.expectEqual(1, end);
    var i = start;
    var address = memory_base;
    while (i <= end) : (i += 1) {
        tableSet(TTBR0_IDENTITY, i, address, IDENTITY_FLAGS.toU64());
        address += BLOCK_L1_SIZE;
    }

    TTBR1_L1 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE);
    TTBR1_L2 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 2);
    TTBR1_L3 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 3);
    const ttbr1_el1 = @ptrToInt(TTBR1_L1) | 1;
    // printf("TTBR1_EL1: {x:0>16} -> {x:0>16}\n", .{ read_register(.TTBR1_EL1), ttbr1_el1 });
    write_register(.TTBR1_EL1, ttbr1_el1);
    tableSet(TTBR1_L1, 0, @ptrToInt(TTBR1_L2), KERNEL_DATA_TABLE.toU64());
    tableSet(TTBR1_L2, 0, @ptrToInt(TTBR1_L3), KERNEL_DATA_TABLE.toU64());

    var theEnd = (daintree_end - daintree_base) >> PAGE_BITS;
    if (theEnd > 512) {
        while (true) {}
    }

    address = daintree_base;
    var flags = KERNEL_CODE_TABLE.toU64();
    i = 0;
    while (i < theEnd) : (i += 1) {
        if (address >= daintree_data_base) {
            flags = KERNEL_DATA_TABLE.toU64();
        } else if (address >= daintree_rodata_base) {
            flags = KERNEL_RODATA_TABLE.toU64();
        }
        tableSet(TTBR1_L3, i, address, flags);
    }

    address += 4 * PAGE_SIZE;
    tableSet(TTBR1_L3, theEnd, 0xDEADBEEF, KERNEL_DATA_TABLE.toU64());
    i = theEnd + 1;
    theEnd = i + STACK_PAGES;
    while (i < theEnd) : (i += 1) {
        tableSet(TTBR1_L3, i, address, KERNEL_DATA_TABLE.toU64());
        address += PAGE_SIZE;
    }

    const lr = asm volatile ("mov %[ret], lr"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );

    const vbar_el1 = asm volatile ("adr %[ret], __vbar_el1"
        : [ret] "=r" (-> u64)
        :
        : "volatile"
    );

    asm volatile (
        \\mov sp, %[sp]
        \\mov lr, %[lr]
        \\msr VBAR_EL1, %[vbar_el1]
        \\mrs x0, SCTLR_EL1
        \\orr x0, x0, #1
        \\msr SCTLR_EL1, x0
        \\isb
        \\b .
        \\nop
        \\nop
        \\nop
        \\nop
        \\nop
        \\nop
        \\ret
        :
        : [sp] "r" (KERNEL_BASE | (theEnd << PAGE_BITS)),
          [vbar_el1] "r" (vbar_el1 - daintree_base + KERNEL_BASE),
          [lr] "r" (lr - daintree_base + KERNEL_BASE)
        : "volatile"
    );
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
const PAGE_SIZE = 1 << PAGE_BITS;
const PAGE_MASK = PAGE_SIZE - 1;

const BLOCK_L1_BITS = 30;
const BLOCK_L1_SIZE = 1 << BLOCK_L1_BITS;

const INDEX_BITS = 9;
const INDEX_SIZE = 1 << INDEX_BITS;

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
