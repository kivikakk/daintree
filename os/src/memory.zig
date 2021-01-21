const std = @import("std");
const framebuffer = @import("framebuffer.zig");
const printf = framebuffer.printf;
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

    printf("framebuffer: {x:0>16}\n", .{@ptrToInt(framebuffer.fb)});

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

    const ttbr0_el1 = @ptrToInt(&TTBR0_IDENTITY) | 1;
    printf("TTBR0_EL1: {x:0>16} -> {x:0>16}\n", .{ read_register(.TTBR0_EL1), ttbr0_el1 });
    write_register(.TTBR0_EL1, ttbr0_el1); // 0b1 = CNP, "common not private"

    const memory_base: u64 = 0x4000_0000;
    const memory_end: u64 = memory_base + 512 * 1048576;

    const start = comptime index(1, memory_base);
    const end = comptime index(1, memory_end);
    comptime std.testing.expectEqual(1, start);
    comptime std.testing.expectEqual(1, end);
    var i = start;
    var address = memory_base;
    while (i < end) : (i += 1) {
        tableSet(TTBR0_IDENTITY[0..], i, address, IDENTITY_FLAGS.toU64());
        address += BLOCK_L1_SIZE;
    }

    printf("SCTLR_EL1: {x:0>16} -> ", .{read_register(.SCTLR_EL1)});
    or_register(.SCTLR_EL1, 1); // MMU enable
    printf("{x:0>16}\n", .{read_register(.SCTLR_EL1)});

    printf("isb: ", .{});
    asm volatile ("isb");
    printf("success.\n", .{});
}

fn index(comptime level: u2, va: u64) usize {
    if (level == 0) {
        @compileError("level must be 1, 2, 3");
    }

    return (va & VADDRESS_MASK) >> (@as(u8, 3 - level) * INDEX_BITS + PAGE_BITS);
}

fn tableSet(table: []u64, ix: usize, address: u64, flags: u64) void {
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

const BLOCK_L1_BITS = 30;
const BLOCK_L1_SIZE = 1 << BLOCK_L1_BITS;

const INDEX_BITS = 9;
const INDEX_SIZE = 1 << INDEX_BITS;

const TRANSLATION_LEVELS = 3;
const ADDRESS_BITS = PAGE_BITS + TRANSLATION_LEVELS * INDEX_BITS;

const IDENTITY_FLAGS = paging.PageTableEntry{
    .uxn = 1,
    .pxn = 0,
    .af = 1,
    .sh = .inner_shareable,
    .attr_indx = MEMORY_MAIR_INDEX,
    .type = .block,
    .oa = 0,
};

comptime {
    std.testing.expectEqual(0x0040000000000701, IDENTITY_FLAGS.toU64());
}

const VADDRESS_MASK = 0x0000007f_fffff000;

pub var TTBR0_IDENTITY: [INDEX_SIZE]u64 align(8192) = [_]u64{0} ** INDEX_SIZE;
pub var PAGE_TABLE_0: [8192]u64 align(8192) = undefined;
pub var PAGE_TABLE_1: [8192]u64 align(8192) = undefined;
