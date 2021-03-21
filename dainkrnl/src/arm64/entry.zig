const std = @import("std");
const build_options = @import("build_options");
const dcommon = @import("../common/dcommon.zig");
const arch = @import("arch.zig");
const hw = @import("../hw.zig");

usingnamespace @import("paging.zig");

fn entryAssert(cond: bool, comptime msg: []const u8) callconv(.Inline) void {
    if (!cond) {
        hw.entry_uart.carefully(.{ msg, "\r\n" });
        while (true) {}
    }
}

/// dainboot passes control here.  MMU is **off**.  We are in EL1.
pub export fn daintree_mmu_start(entry_data: *dcommon.EntryData) noreturn {
    hw.entry_uart.init(entry_data);

    const daintree_base = arch.loadAddress("__daintree_base");
    const daintree_rodata_base = arch.loadAddress("__daintree_rodata_base");
    const daintree_data_base = arch.loadAddress("__daintree_data_base");
    const daintree_end = arch.loadAddress("__daintree_end");
    const daintree_main = arch.loadAddress("daintree_main");
    const vbar_el1 = arch.loadAddress("__vbar_el1");
    const current_el = arch.readRegister(.CurrentEL) >> 2;
    const sctlr_el1 = arch.readRegister(.SCTLR_EL1);
    const cpacr_el1 = arch.readRegister(.CPACR_EL1);

    hw.entry_uart.carefully(.{ "__daintree_base: ", daintree_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_rodata_base: ", daintree_rodata_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_data_base: ", daintree_data_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_end: ", daintree_end, "\r\n" });
    hw.entry_uart.carefully(.{ "daintree_main: ", daintree_main, "\r\n" });
    hw.entry_uart.carefully(.{ "__vbar_el1: ", vbar_el1, "\r\n" });
    hw.entry_uart.carefully(.{ "CurrentEL: ", current_el, "\r\n" });
    hw.entry_uart.carefully(.{ "SCTLR_EL1: ", sctlr_el1, "\r\n" });
    hw.entry_uart.carefully(.{ "CPACR_EL1: ", cpacr_el1, "\r\n" });

    const tcr_el1 = comptime (TCR_EL1{
        .ips = .B36,
        .tg1 = .K4,
        .t1sz = 64 - PAGING.address_bits, // in practice: 25
        .tg0 = .K4,
        .t0sz = 64 - PAGING.address_bits,
    }).toU64();
    comptime std.debug.assert(0x00000001_b5193519 == tcr_el1);
    arch.writeRegister(.TCR_EL1, tcr_el1);

    const mair_el1 = comptime (MAIR_EL1{ .index = DEVICE_MAIR_INDEX, .attrs = 0b00 }).toU64() |
        (MAIR_EL1{ .index = MEMORY_MAIR_INDEX, .attrs = 0b1111_1111 }).toU64();
    comptime std.debug.assert(0x00000000_000000ff == mair_el1);
    arch.writeRegister(.MAIR_EL1, mair_el1);

    var bump = paging.BumpAllocator{ .next = daintree_end };
    TTBR0_IDENTITY = bump.alloc([PAGING.index_size]u64);
    TTBR1_L1 = bump.alloc([PAGING.index_size]u64);
    TTBR1_L2 = bump.alloc([PAGING.index_size]u64);
    TTBR1_L3_1 = bump.alloc([PAGING.index_size]u64);
    TTBR1_L3_2 = bump.alloc([PAGING.index_size]u64);
    TTBR1_L3_3 = bump.alloc([PAGING.index_size]u64);

    const ttbr0_el1 = @ptrToInt(TTBR0_IDENTITY) | 1;
    const ttbr1_el1 = @ptrToInt(TTBR1_L1) | 1;
    hw.entry_uart.carefully(.{ "setting TTBR0_EL1: ", ttbr0_el1, "\r\n" });
    hw.entry_uart.carefully(.{ "setting TTBR1_EL1: ", ttbr1_el1, "\r\n" });
    arch.writeRegister(.TTBR0_EL1, ttbr0_el1);
    arch.writeRegister(.TTBR1_EL1, ttbr1_el1);

    var it = PAGING.range(1, entry_data.conventional_start, entry_data.conventional_bytes);
    while (it.next()) |r| {
        hw.entry_uart.carefully(.{ "mapping identity: page ", r.page, " address ", r.address, "\r\n" });
        tableSet(TTBR0_IDENTITY, r.page, r.address, IDENTITY_FLAGS.toU64());
    }

    tableSet(TTBR1_L1, 0, @ptrToInt(TTBR1_L2), KERNEL_DATA_TABLE.toU64());
    tableSet(TTBR1_L2, 0, @ptrToInt(TTBR1_L3_1), KERNEL_DATA_TABLE.toU64());
    tableSet(TTBR1_L2, 1, @ptrToInt(TTBR1_L3_2), KERNEL_DATA_TABLE.toU64());
    tableSet(TTBR1_L2, 2, @ptrToInt(TTBR1_L3_3), KERNEL_DATA_TABLE.toU64());

    var end: u64 = (daintree_end - daintree_base) >> PAGING.page_bits;
    entry_assert(end <= 512, "end got too big (1)");

    var address = daintree_base;
    var flags = KERNEL_CODE_TABLE.toU64();
    var i: u64 = 0;
    hw.entry_uart.carefully(.{ "MAP: text at   ", PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        if (address >= daintree_data_base) {
            if (flags != KERNEL_DATA_TABLE.toU64()) {
                hw.entry_uart.carefully(.{ "MAP: data at   ", PAGING.kernelPageAddress(i), "~\r\n" });
                flags = KERNEL_DATA_TABLE.toU64();
            }
        } else if (address >= daintree_rodata_base) {
            if (flags != KERNEL_RODATA_TABLE.toU64()) {
                hw.entry_uart.carefully(.{ "MAP: rodata at ", PAGING.kernelPageAddress(i), "~\r\n" });
                flags = KERNEL_RODATA_TABLE.toU64();
            }
        }
        tableSet(TTBR1_L3_1, i, address, flags);
        address += PAGING.page_size;
    }

    // i = end
    end += 6; // TTBR0_IDENTITY .. TTBR1_L3_3
    hw.entry_uart.carefully(.{ "MAP: null at   ", PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        tableSet(TTBR1_L3_1, i, 0, 0);
    }
    end = i + STACK_PAGES;
    hw.entry_uart.carefully(.{ "MAP: stack at  ", PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        tableSet(TTBR1_L3_1, i, address, KERNEL_DATA_TABLE.toU64());
        address += PAGING.page_size;
    }

    entry_assert(end <= 512, "end got too big (2)");

    // Let's hackily put UART at wherever's next.
    hw.entry_uart.carefully(.{ "MAP: UART at   ", PAGING.kernelPageAddress(i), "\r\n" });
    tableSet(TTBR1_L3_1, i, entry_data.uart_base, PERIPHERAL_TABLE.toU64());

    // address now points to the stack. make space for common.EntryData, align.
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
        .uart_base = PAGING.kernelPageAddress(i),
        .uart_width = entry_data.uart_width,
    };

    var new_sp = PAGING.kernelPageAddress(i);
    new_sp -= @sizeOf(dcommon.EntryData);
    new_sp &= ~@as(u64, 15);

    // I hate that I'm doing this. Put the DTB in here.
    {
        i += 1;
        new_entry.dtb_ptr = @intToPtr([*]const u8, PAGING.kernelPageAddress(i));
        std.mem.copy(u8, @intToPtr([*]u8, address)[0..entry_data.dtb_len], entry_data.dtb_ptr[0..entry_data.dtb_len]);

        // How many pages?
        const dtb_pages = (entry_data.dtb_len + PAGING.page_size - 1) / PAGING.page_size;

        var new_end = end + 1 + dtb_pages; // Skip 1 page since UART is there
        entry_assert(new_end <= 512, "end got too big (3)");

        hw.entry_uart.carefully(.{ "MAP: DTB at    ", PAGING.kernelPageAddress(i), "~\r\n" });
        while (i < new_end) : (i += 1) {
            tableSet(TTBR1_L3_1, i, address, KERNEL_RODATA_TABLE.toU64());
            address += PAGING.page_size;
        }
    }

    // Map framebuffer as device.  Put in second/third TTBR1_L3 as it tends to be
    // huge.
    if (new_entry.fb) |base| {
        i = 512;
        address = @ptrToInt(base);
        new_entry.fb = @intToPtr([*]u32, PAGING.kernelPageAddress(i));
        var new_end = i + (new_entry.fb_vert * new_entry.fb_horiz * 4 + PAGING.page_size - 1) / PAGING.page_size;
        entry_assert(new_end <= 512 + 512 * 2, "end got too big (4)");

        hw.entry_uart.carefully(.{ "MAP: FB at     ", PAGING.kernelPageAddress(i), "~\r\n" });
        while (i < new_end) : (i += 1) {
            if (i - 512 < 512) {
                tableSet(TTBR1_L3_2, i - 512, address, PERIPHERAL_TABLE.toU64());
            } else {
                tableSet(TTBR1_L3_3, i - 1024, address, PERIPHERAL_TABLE.toU64());
            }
            address += PAGING.page_size;
        }
    }

    hw.entry_uart.carefully(.{ "MAP: end at    ", PAGING.kernelPageAddress(i), ".\r\n" });
    hw.entry_uart.carefully(.{ "about to install:\r\nsp: ", new_sp, "\r\n" });
    hw.entry_uart.carefully(.{ "lr: ", daintree_main - daintree_base + PAGING.kernel_base, "\r\n" });
    hw.entry_uart.carefully(.{ "vbar_el1: ", vbar_el1 - daintree_base + PAGING.kernel_base, "\r\n" });
    hw.entry_uart.carefully(.{ "uart mapped to: ", PAGING.kernelPageAddress(i), "\r\n" });

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
          [lr] "r" (daintree_main - daintree_base + PAGING.kernel_base),
          [vbar_el1] "r" (vbar_el1 - daintree_base + PAGING.kernel_base)
    );

    unreachable;
}
