const std = @import("std");
const build_options = @import("build_options");
const dcommon = @import("../common/dcommon.zig");
const arch = @import("arch.zig");
const hw = @import("../hw.zig");

var PT_L1: *[INDEX_SIZE]u64 = undefined;
var PTS_L2: *[INDEX_SIZE]u64 = undefined;
var PTS_L3_1: *[INDEX_SIZE]u64 = undefined;
var PTS_L3_2: *[INDEX_SIZE]u64 = undefined;
var PTS_L3_3: *[INDEX_SIZE]u64 = undefined;

/// dainboot passes control here.  MMU is **off**.
pub export fn daintree_mmu_start(entry_data: *dcommon.EntryData) noreturn {
    hw.entry_uart.base = entry_data.uart_base;
    hw.entry_uart.width = entry_data.uart_width;

    hw.entry_uart.carefully(.{ "\r\n\r\ndainkrnl ", build_options.version, " pre-MMU stage on ", build_options.board, "\r\n" });

    hw.entry_uart.carefully(.{ "entry_data (", @ptrToInt(entry_data), ")\r\n" });
    hw.entry_uart.carefully(.{ "memory_map:         ", @ptrToInt(entry_data.memory_map), "\r\n" });
    hw.entry_uart.carefully(.{ "memory_map_size:    ", entry_data.memory_map_size, "\r\n" });
    hw.entry_uart.carefully(.{ "descriptor_size:    ", entry_data.descriptor_size, "\r\n" });
    hw.entry_uart.carefully(.{ "dtb_ptr:            ", @ptrToInt(entry_data.dtb_ptr), "\r\n" });
    hw.entry_uart.carefully(.{ "dtb_len:            ", entry_data.dtb_len, "\r\n" });
    hw.entry_uart.carefully(.{ "conventional_start: ", entry_data.conventional_start, "\r\n" });
    hw.entry_uart.carefully(.{ "conventional_bytes: ", entry_data.conventional_bytes, "\r\n" });
    hw.entry_uart.carefully(.{ "fb:                 ", @ptrToInt(entry_data.fb), "\r\n" });
    hw.entry_uart.carefully(.{ "fb_vert:            ", entry_data.fb_vert, "\r\n" });
    hw.entry_uart.carefully(.{ "fb_horiz:           ", entry_data.fb_horiz, "\r\n" });
    hw.entry_uart.carefully(.{ "uart_base:          ", entry_data.uart_base, "\r\n" });

    var daintree_base: u64 = asm volatile ("la %[ret], __daintree_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_rodata_base: u64 = asm volatile ("la %[ret], __daintree_rodata_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_data_base: u64 = asm volatile ("la %[ret], __daintree_data_base"
        : [ret] "=r" (-> u64)
    );
    var daintree_end: u64 = asm volatile ("la %[ret], __daintree_end"
        : [ret] "=r" (-> u64)
    );
    const daintree_main = asm volatile ("la %[ret], daintree_main"
        : [ret] "=r" (-> u64)
    );
    const trap_entry = asm volatile ("la %[ret], __trap_entry"
        : [ret] "=r" (-> u64)
    );

    hw.entry_uart.carefully(.{ "__daintree_base: ", daintree_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_rodata_base: ", daintree_rodata_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_data_base: ", daintree_data_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_end: ", daintree_end, "\r\n" });
    hw.entry_uart.carefully(.{ "daintree_main: ", daintree_main, "\r\n" });
    hw.entry_uart.carefully(.{ "__trap_entry: ", trap_entry, "\r\n" });

    PT_L1 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 0);
    PTS_L2 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 1);
    PTS_L3_1 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 2);
    PTS_L3_2 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 3);
    PTS_L3_3 = @intToPtr(*[INDEX_SIZE]u64, daintree_end + PAGE_SIZE * 4);

    std.debug.assert((@ptrToInt(PT_L1) & 0xfff) == 0);

    {
        // XXX 0 to capture serial UART for now.
        const l1_start = @as(usize, 0); // index(1, entry_data.conventional_start);
        const l1_end = index(1, entry_data.conventional_start + entry_data.conventional_bytes);
        var l1_i = l1_start;
        var l1_address = entry_data.conventional_start & ~(@as(usize, BLOCK_L1_SIZE) - 1);

        while (l1_i <= l1_end) : (l1_i += 1) {
            hw.entry_uart.carefully(.{ "mapping identity: page ", l1_i, " address ", l1_address, "\r\n" });
            tableSet(PT_L1, l1_i, arch.PageTableEntry{
                .rwx = .rwx,
                .u = 0,
                .g = 0,
                .a = 1, // XXX ???
                .d = 1, // XXX ???
                .ppn = @truncate(u44, l1_address >> PAGE_BITS),
            });
            l1_address += BLOCK_L1_SIZE;
        }
    }

    tableSet(PT_L1, 256, .{ .rwx = .non_leaf, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, @ptrToInt(PTS_L2) >> PAGE_BITS) });
    tableSet(PTS_L2, 0, .{ .rwx = .non_leaf, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, @ptrToInt(PTS_L3_1) >> PAGE_BITS) });
    tableSet(PTS_L2, 1, .{ .rwx = .non_leaf, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, @ptrToInt(PTS_L3_2) >> PAGE_BITS) });
    tableSet(PTS_L2, 2, .{ .rwx = .non_leaf, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, @ptrToInt(PTS_L3_3) >> PAGE_BITS) });

    var end: u64 = (daintree_end - daintree_base) >> PAGE_BITS;
    if (end > 512) {
        hw.entry_uart.carefully(.{"end got too big (1)\r\n"});
        while (true) {}
    }

    var address = daintree_base;
    var rwx: arch.RWX = .rx;
    var i: u64 = 0;
    hw.entry_uart.carefully(.{ "MAP: text at   ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
    while (i < end) : (i += 1) {
        if (address >= daintree_data_base) {
            if (rwx != .rw)
                hw.entry_uart.carefully(.{ "MAP: data at   ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
            rwx = .rw;
        } else if (address >= daintree_rodata_base) {
            if (rwx != .ro)
                hw.entry_uart.carefully(.{ "MAP: rodata at ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
            rwx = .ro;
        }

        hw.entry_uart.carefully(.{});
        tableSet(PTS_L3_1, i, .{ .rwx = rwx, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, address >> PAGE_BITS) });
        address += PAGE_SIZE;
    }

    // i = end
    end += 5; // PT_L1 .. PTS_L3_3
    hw.entry_uart.carefully(.{ "MAP: null at   ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
    while (i < end) : (i += 1) {
        tableSet(PTS_L3_1, i, std.mem.zeroes(arch.PageTableEntry));
    }
    end = i + STACK_PAGES;
    hw.entry_uart.carefully(.{ "MAP: stack at  ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
    while (i < end) : (i += 1) {
        tableSet(PTS_L3_1, i, .{ .rwx = .rw, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, address >> PAGE_BITS) });
        address += PAGE_SIZE;
    }

    if (end > 512) {
        hw.entry_uart.carefully(.{"end got too big (2)\r\n"});
        while (true) {}
    }

    hw.entry_uart.carefully(.{ "MAP: UART at   ", KERNEL_BASE | (i << PAGE_BITS), "\r\n" });
    // XXX doesn't look like RV MMU needs any special peripheral/cacheability stuff?
    tableSet(PTS_L3_1, i, .{ .rwx = .rw, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, entry_data.uart_base >> 12) });

    // Below is verbatim from arm64 entry. ---
    var entry_address = address - @sizeOf(dcommon.EntryData);
    entry_address &= ~@as(u64, 15);
    var new_entry = @intToPtr(*dcommon.EntryData, entry_address);
    new_entry.* = .{
        .memory_map = entry_data.memory_map,
        .memory_map_size = entry_data.memory_map_size,
        .descriptor_size = entry_data.descriptor_size,
        .dtb_ptr = undefined,
        .dtb_len = entry_data.dtb_len,
        .conventional_start = entry_data.conventional_start,
        .conventional_bytes = entry_data.conventional_bytes,
        .fb = entry_data.fb,
        .fb_vert = entry_data.fb_vert,
        .fb_horiz = entry_data.fb_horiz,
        .uart_base = KERNEL_BASE | (end << PAGE_BITS),
        .uart_width = entry_data.uart_width,
    };

    var new_sp = KERNEL_BASE | (end << PAGE_BITS);
    new_sp -= @sizeOf(dcommon.EntryData);
    new_sp &= ~@as(u64, 15);

    {
        i += 1;
        new_entry.dtb_ptr = @intToPtr([*]const u8, KERNEL_BASE | (i << PAGE_BITS));
        std.mem.copy(u8, @intToPtr([*]u8, address)[0..entry_data.dtb_len], entry_data.dtb_ptr[0..entry_data.dtb_len]);

        // How many pages?
        const dtb_pages = (entry_data.dtb_len + PAGE_SIZE - 1) / PAGE_SIZE;

        var new_end = end + 1 + dtb_pages; // Skip 1 page since UART is there
        if (new_end > 512) {
            hw.entry_uart.carefully(.{"end got too big (3)\r\n"});
            while (true) {}
        }

        hw.entry_uart.carefully(.{ "MAP: DTB at    ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
        while (i < new_end) : (i += 1) {
            tableSet(PTS_L3_1, i, .{ .rwx = .ro, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, address >> PAGE_BITS) });
            address += PAGE_SIZE;
        }
    }

    // Map framebuffer as device.  Put in second/third TTBR1_L3 as it tends to be
    // huge.
    if (new_entry.fb) |base| {
        i = 512;
        address = @ptrToInt(base);
        new_entry.fb = @intToPtr([*]u32, KERNEL_BASE | (i << PAGE_BITS));
        var new_end = i + (new_entry.fb_vert * new_entry.fb_horiz * 4 + PAGE_SIZE - 1) / PAGE_SIZE;
        if (new_end > 512 + 512 * 2) {
            hw.entry_uart.carefully(.{ "end got too big (4): ", new_end, "\r\n" });
            while (true) {}
        }

        hw.entry_uart.carefully(.{ "MAP: FB at     ", KERNEL_BASE | (i << PAGE_BITS), "~\r\n" });
        while (i < new_end) : (i += 1) {
            if (i - 512 < 512) {
                tableSet(PTS_L3_2, i - 512, .{ .rwx = .rw, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, address >> PAGE_BITS) });
            } else {
                tableSet(PTS_L3_3, i - 1024, .{ .rwx = .rw, .u = 0, .g = 0, .a = 1, .d = 1, .ppn = @truncate(u44, address >> PAGE_BITS) });
            }
            address += PAGE_SIZE;
        }
    }
    hw.entry_uart.carefully(.{ "MAP: end at    ", KERNEL_BASE | (i << PAGE_BITS), ".\r\n" });

    hw.entry_uart.carefully(.{ "about to install:\r\nsp: ", new_sp, "\r\n" });
    hw.entry_uart.carefully(.{ "ra: ", daintree_main - daintree_base + KERNEL_BASE, "\r\n" });
    hw.entry_uart.carefully(.{ "uart mapped to: ", KERNEL_BASE | (end << PAGE_BITS), "\r\n" });

    const satp = (arch.SATP{
        .ppn = @truncate(u44, @ptrToInt(PT_L1) >> PAGE_BITS),
        .asid = 0,
        .mode = .sv39,
    }).toU64();

    asm volatile (
        \\mv sp, %[sp]
        \\csrw satp, %[satp]
        \\sfence.vma
        \\ret
        :
        : [sp] "{a0}" (new_sp),
          [satp] "r" (satp),
          [ra] "{ra}" (daintree_main - daintree_base + KERNEL_BASE),
          [uart_base] "r" (@as(u64, 0x38000000))
        : "memory"
    );

    unreachable;
}

// dupe with arm64 (except our consts are different); refactor.
fn index(comptime level: u2, va: u64) usize {
    if (level == 0) {
        @compileError("level must be 1, 2, 3");
    }

    return (va & VADDRESS_MASK) >> (@as(u8, 3 - level) * INDEX_BITS + PAGE_BITS);
}

fn tableSet(table: []u64, ix: usize, pte: arch.PageTableEntry) void {
    table[ix] = pte.toU64();
}

const PAGE_BITS = 12;
const PAGE_SIZE = 1 << PAGE_BITS; // 4096 (= 512 * 8)
const PAGE_MASK = PAGE_SIZE - 1;

const BLOCK_L1_BITS = 30;
const BLOCK_L1_SIZE = 1 << BLOCK_L1_BITS;

const INDEX_BITS = 9;
const INDEX_SIZE = 1 << INDEX_BITS; // 512

const TRANSLATION_LEVELS = 3;
const ADDRESS_BITS = PAGE_BITS + TRANSLATION_LEVELS * INDEX_BITS;

const VADDRESS_MASK = 0x0000003f_fffff000;

const KERNEL_BASE = ~@as(u64, VADDRESS_MASK | PAGE_MASK);
comptime {
    std.debug.assert(dcommon.daintree_kernel_start == KERNEL_BASE);
}
const STACK_PAGES = 16;
