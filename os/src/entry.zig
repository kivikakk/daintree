// Must be pub at build root -- Zig will use this, see lib/std/builtin.zig's 'panic'.
pub const panic = @import("panic.zig").panic;

const std = @import("std");
const arch = @import("arch.zig");
const build_options = @import("build_options");
comptime {
    _ = @import("exception.zig");
    _ = @import("main.zig");
}

// From dainboot.
pub const EntryData = packed struct {
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    conventional_start: usize,
    conventional_bytes: usize,
    fb: [*]u32,
    verthoriz: u64,
    uart_base: u64,
};

comptime {
    std.testing.expectEqual(64, @sizeOf(EntryData));
}

var TTBR0_IDENTITY: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L1: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L2: *[INDEX_SIZE]u64 = undefined;
var TTBR1_L3: *[INDEX_SIZE]u64 = undefined;

usingnamespace @import("hacks.zig");

// UEFI passes control here. MMU is **off**.
pub export fn daintree_mmu_start(
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    conventional_start: usize,
    conventional_bytes: usize,
    fb: [*]u32,
    verthoriz: u64,
    uart_base: u64,
) noreturn {
    HACK_uart(.{ "dainkrnl pre-MMU stage on ", build_options.board, "\r\n" });

    var daintree_base: u64 = asm volatile ("adr %[ret], __daintree_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_rodata_base: u64 = asm volatile ("adr %[ret], __daintree_rodata_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_data_base: u64 = asm volatile ("adr %[ret], __daintree_data_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_end: u64 = asm volatile ("adr %[ret], __daintree_end"
        : [ret] "=r" (-> u64)
    );
    const daintree_main = asm volatile ("adr %[ret], daintree_main"
        : [ret] "=r" (-> u64)
    );
    const vbar_el1 = asm volatile ("adr %[ret], __vbar_el1"
        : [ret] "=r" (-> u64)
    );
    const current_el = arch.readRegister(.CurrentEL) >> 2;
    const sctlr_el1 = arch.readRegister(.SCTLR_EL1);

    HACK_uart(.{ "__daintree_base: ", daintree_base, "\r\n" });
    HACK_uart(.{ "__daintree_rodata_base: ", daintree_rodata_base, "\r\n" });
    HACK_uart(.{ "__daintree_data_base: ", daintree_data_base, "\r\n" });
    HACK_uart(.{ "__daintree_end: ", daintree_end, "\r\n" });
    HACK_uart(.{ "daintree_main: ", daintree_main, "\r\n" });
    HACK_uart(.{ "__vbar_el1: ", vbar_el1, "\r\n" });
    HACK_uart(.{ "CurrentEL: ", current_el, "\r\n" });
    HACK_uart(.{ "SCTLR_EL1: ", sctlr_el1, "\r\n" });

    const tcr_el1 = comptime (arch.TCR_EL1{
        .ips = .B36,
        .tg1 = .K4,
        .t1sz = 64 - ADDRESS_BITS, // in practice: 25
        .tg0 = .K4,
        .t0sz = 64 - ADDRESS_BITS,
    }).toU64();
    comptime std.testing.expectEqual(0x00000001_b5193519, tcr_el1);
    arch.writeRegister(.TCR_EL1, tcr_el1);

    const mair_el1 = comptime (arch.MAIR_EL1{ .index = DEVICE_MAIR_INDEX, .attrs = 0b00 }).toU64() |
        (arch.MAIR_EL1{ .index = MEMORY_MAIR_INDEX, .attrs = 0b11111111 }).toU64();
    comptime std.testing.expectEqual(0x00000000_000000ff, mair_el1);
    arch.writeRegister(.MAIR_EL1, mair_el1);

    comptime {
        std.testing.expectEqual(@sizeOf([INDEX_SIZE]u64), PAGE_SIZE);
    }
    TTBR0_IDENTITY = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 0);
    TTBR1_L1 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 1);
    TTBR1_L2 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 2);
    TTBR1_L3 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 3);

    const ttbr0_el1 = @ptrToInt(TTBR0_IDENTITY) | 1;
    const ttbr1_el1 = @ptrToInt(TTBR1_L1) | 1;
    HACK_uart(.{ "setting TTBR0_EL1: ", ttbr0_el1, "\r\n" });
    HACK_uart(.{ "setting TTBR1_EL1: ", ttbr1_el1, "\r\n" });
    arch.writeRegister(.TTBR0_EL1, ttbr0_el1);
    arch.writeRegister(.TTBR1_EL1, ttbr1_el1);

    {
        const l1_start = index(1, conventional_start);
        const l1_end = index(1, conventional_start + conventional_bytes);

        var l1_i = l1_start;
        var l1_address = conventional_start;
        while (l1_i <= l1_end) : (l1_i += 1) {
            tableSet(TTBR0_IDENTITY, l1_i, l1_address, IDENTITY_FLAGS.toU64());
            l1_address += BLOCK_L1_SIZE;
        }
    }

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
    address -= @sizeOf(EntryData);
    address &= ~@as(u64, 15);
    @intToPtr(*EntryData, address).* = .{
        .memory_map = memory_map,
        .memory_map_size = memory_map_size,
        .descriptor_size = descriptor_size,
        .conventional_start = conventional_start,
        .conventional_bytes = conventional_bytes,
        .fb = fb,
        .verthoriz = verthoriz,
        .uart_base = uart_base,
    };

    var new_sp = KERNEL_BASE | (end << PAGE_BITS);
    new_sp -= @sizeOf(EntryData);
    new_sp &= ~@as(u64, 15);

    HACK_uart(.{ "about to install:\r\nsp: ", new_sp, "\r\n" });
    HACK_uart(.{ "lr: ", daintree_main - daintree_base + KERNEL_BASE, "\r\n" });
    HACK_uart(.{ "vbar_el1: ", vbar_el1 - daintree_base + KERNEL_BASE, "\r\n" });

    // Control passes to daintree_main.
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
    );

    unreachable;
}

fn index(comptime level: u2, va: u64) callconv(.Inline) usize {
    if (level == 0) {
        @compileError("level must be 1, 2, 3");
    }

    return (va & VADDRESS_MASK) >> (@as(u8, 3 - level) * INDEX_BITS + PAGE_BITS);
}

fn tableSet(table: []u64, ix: usize, address: u64, flags: u64) callconv(.Inline) void {
    table[ix] = address | flags;
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

const IDENTITY_FLAGS = arch.PageTableEntry{
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

const KERNEL_DATA_TABLE = arch.PageTableEntry{
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

const KERNEL_RODATA_TABLE = arch.PageTableEntry{
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

const KERNEL_CODE_TABLE = arch.PageTableEntry{
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
