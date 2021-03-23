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

/// dainboot passes control here.  MMU is **off**.  We are in S-mode.
pub export fn daintree_mmu_start(entry_data: *dcommon.EntryData) noreturn {
    hw.entry_uart.init(entry_data);

    const daintree_base = arch.loadAddress("__daintree_base");
    const daintree_rodata_base = arch.loadAddress("__daintree_rodata_base");
    const daintree_data_base = arch.loadAddress("__daintree_data_base");
    const daintree_end = arch.loadAddress("__daintree_end");
    const daintree_main = arch.loadAddress("daintree_main");
    const trap_entry = arch.loadAddress("__trap_entry");

    hw.entry_uart.carefully(.{ "__daintree_base: ", daintree_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_rodata_base: ", daintree_rodata_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_data_base: ", daintree_data_base, "\r\n" });
    hw.entry_uart.carefully(.{ "__daintree_end: ", daintree_end, "\r\n" });
    hw.entry_uart.carefully(.{ "daintree_main: ", daintree_main, "\r\n" });
    hw.entry_uart.carefully(.{ "__trap_entry: ", trap_entry, "\r\n" });

    var bump = paging.BumpAllocator{ .next = daintree_end };
    K_DIRECTORY = bump.alloc(PageTable);
    var l2 = bump.alloc(PageTable);
    var l3 = bump.alloc(PageTable);

    // XXX: start from 0 to include syscon in mapped range so CI works.
    // XXX add 100MiB to catch page tables
    var it = PAGING.range(1, 0, entry_data.conventional_start + entry_data.conventional_bytes + 100 * 1048576);
    while (it.next()) |r| {
        hw.entry_uart.carefully(.{ "mapping identity: page ", r.page, " address ", r.address, "\r\n" });
        K_DIRECTORY.map(r.page, r.address, .kernel_promisc);
    }

    K_DIRECTORY.map(256, @ptrToInt(l2), .non_leaf);
    l2.map(0, @ptrToInt(l3), .non_leaf);

    var end: u64 = (daintree_end - daintree_base) >> PAGING.page_bits;
    entryAssert(end <= 512, "end got too big (1)");

    var address = daintree_base;
    var flags: paging.MapFlags = .kernel_code;
    var i: u64 = 0;
    hw.entry_uart.carefully(.{ "MAP: text at   ", PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        if (address >= daintree_data_base) {
            if (flags != .kernel_data) {
                hw.entry_uart.carefully(.{ "MAP: data at   ", PAGING.kernelPageAddress(i), "~\r\n" });
                flags = .kernel_data;
            }
        } else if (address >= daintree_rodata_base) {
            if (flags != .kernel_rodata) {
                hw.entry_uart.carefully(.{ "MAP: rodata at ", PAGING.kernelPageAddress(i), "~\r\n" });
                flags = .kernel_rodata;
            }
        }
        l3.map(i, address, flags);
        address += PAGING.page_size;
    }

    hw.entry_uart.carefully(.{ "MAP: PTs at    ", PAGING.kernelPageAddress(i), "~\r\n" });
    var k_directory_va = PAGING.kernelPageAddress(i);
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;

    var l2_va = PAGING.kernelPageAddress(i);
    K_DIRECTORY.setVirt(256, l2_va);
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;

    var l3x_va = PAGING.kernelPageAddress(i);
    l2.setVirt(0, l3x_va);
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;
    l3.map(i, address, .kernel_data);
    address += PAGING.page_size;
    i += 1;

    hw.entry_uart.carefully(.{ "MAP: null at   ", PAGING.kernelPageAddress(i), "\r\n" });
    l3.map(i, 0, .kernel_rodata);
    i += 1;

    end = i + STACK_PAGES;
    hw.entry_uart.carefully(.{ "MAP: stack at  ", PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        l3.map(i, address, .kernel_data);
        address += PAGING.page_size;
    }

    entryAssert(end <= 512, "end got too big (2)");

    hw.entry_uart.carefully(.{ "MAP: UART at   ", PAGING.kernelPageAddress(i), "\r\n" });
    l3.map(i, entry_data.uart_base, .peripheral);

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
        .uart_base = PAGING.kernelPageAddress(end),
        .uart_width = entry_data.uart_width,
        .bump_next = bump.next,
    };

    var new_sp = PAGING.kernelPageAddress(end);
    new_sp -= @sizeOf(dcommon.EntryData);
    new_sp &= ~@as(u64, 15);

    {
        i += 1;
        new_entry.dtb_ptr = @intToPtr([*]const u8, PAGING.kernelPageAddress(i));
        std.mem.copy(u8, @intToPtr([*]u8, address)[0..entry_data.dtb_len], entry_data.dtb_ptr[0..entry_data.dtb_len]);

        // How many pages?
        const dtb_pages = (entry_data.dtb_len + PAGING.page_size - 1) / PAGING.page_size;

        var new_end = end + 1 + dtb_pages; // Skip 1 page since UART is there
        entryAssert(new_end <= 512, "end got too big (3)");

        hw.entry_uart.carefully(.{ "MAP: DTB at    ", PAGING.kernelPageAddress(i), "~\r\n" });
        while (i < new_end) : (i += 1) {
            l3.map(i, address, .kernel_rodata);
            address += PAGING.page_size;
        }
    }

    const satp = (SATP{
        .ppn = @truncate(u44, @ptrToInt(K_DIRECTORY) >> PAGING.page_bits),
        .asid = 0,
        .mode = .sv39,
    }).toU64();

    // Adjust for paging enable.
    hw.entry_uart.carefully(.{ "changing K_DIRECTORY: ", @ptrToInt(K_DIRECTORY), " -> ", k_directory_va, "\r\n" });
    K_DIRECTORY = @intToPtr(*PageTable, k_directory_va);

    hw.entry_uart.carefully(.{ "MAP: end at    ", PAGING.kernelPageAddress(i), ".\r\n" });
    hw.entry_uart.carefully(.{ "about to install:\r\nsp: ", new_sp, "\r\n" });
    hw.entry_uart.carefully(.{ "ra: ", daintree_main - daintree_base + PAGING.kernel_base, "\r\n" });
    hw.entry_uart.carefully(.{ "uart mapped to: ", PAGING.kernelPageAddress(end), "\r\n" });

    asm volatile (
        \\mv sp, %[sp]
        \\csrw satp, %[satp]
        \\sfence.vma
        \\ret
        :
        : [sp] "{a0}" (new_sp), // Argument to daintree_main.
          [satp] "r" (satp),
          [ra] "{ra}" (daintree_main - daintree_base + PAGING.kernel_base)
        : "memory"
    );

    unreachable;
}
