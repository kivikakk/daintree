const std = @import("std");
const build_options = @import("build_options");
const dcommon = @import("../common/dcommon.zig");
const arch = @import("arch.zig");
const hw = @import("../hw.zig");
const p = @import("paging.zig");

inline fn entryAssert(cond: bool, comptime msg: []const u8) void {
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

    var bump = p.paging.BumpAllocator{ .next = daintree_end };
    p.K_DIRECTORY = bump.alloc(p.PageTable);
    var l2 = bump.alloc(p.PageTable);
    var l3 = bump.alloc(p.PageTable);

    hw.entry_uart.carefully(.{ "p.K_DIRECTORY is ", @ptrToInt(p.K_DIRECTORY), "\r\n" });
    hw.entry_uart.carefully(.{ "           l2 is ", @ptrToInt(l2), "\r\n" });
    hw.entry_uart.carefully(.{ "           l3 is ", @ptrToInt(l3), "\r\n" });

    var it = p.PAGING.range(1, entry_data.conventional_start, entry_data.conventional_bytes);
    while (it.next()) |r| {
        hw.entry_uart.carefully(.{ "mapping identity: page ", r.page, " address ", r.address, "\r\n" });
        p.K_DIRECTORY.map(r.page, r.address, .kernel_promisc);
    }

    p.K_DIRECTORY.map(256, @ptrToInt(l2), .non_leaf);
    l2.map(0, @ptrToInt(l3), .non_leaf);

    var end: u64 = (daintree_end - daintree_base) >> p.PAGING.page_bits;
    entryAssert(end <= 512, "end got too big (1)");

    var i: u64 = 0;
    {
        var address = daintree_base;
        var flags: p.paging.MapFlags = .kernel_code;
        hw.entry_uart.carefully(.{ "MAP: text at   ", p.PAGING.kernelPageAddress(i), "~\r\n" });
        while (i < end) : (i += 1) {
            if (address >= daintree_data_base) {
                if (flags != .kernel_data) {
                    hw.entry_uart.carefully(.{ "MAP: data at   ", p.PAGING.kernelPageAddress(i), "~\r\n" });
                    flags = .kernel_data;
                }
            } else if (address >= daintree_rodata_base) {
                if (flags != .kernel_rodata) {
                    hw.entry_uart.carefully(.{ "MAP: rodata at ", p.PAGING.kernelPageAddress(i), "~\r\n" });
                    flags = .kernel_rodata;
                }
            }
            l3.map(i, address, flags);
            address += p.PAGING.page_size;
        }

        entryAssert(address == daintree_end, "address != daintree_end");
    }

    hw.entry_uart.carefully(.{ "MAP: null at   ", p.PAGING.kernelPageAddress(i), "\r\n" });
    l3.map(i, 0, .kernel_rodata);
    i += 1;

    end = i + p.STACK_PAGES;
    hw.entry_uart.carefully(.{ "MAP: stack at  ", p.PAGING.kernelPageAddress(i), "~\r\n" });
    while (i < end) : (i += 1) {
        l3.map(i, bump.allocPage(), .kernel_data);
    }

    entryAssert(end <= 512, "end got too big (2)");

    hw.entry_uart.carefully(.{ "MAP: UART at   ", p.PAGING.kernelPageAddress(i), "\r\n" });
    l3.map(i, entry_data.uart_base, .peripheral);

    var entry_address = bump.next - @sizeOf(dcommon.EntryData);
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
        .uart_base = p.PAGING.kernelPageAddress(end),
        .uart_width = entry_data.uart_width,
        .bump_next = undefined,
    };

    var new_sp = p.PAGING.kernelPageAddress(end);
    new_sp -= @sizeOf(dcommon.EntryData);
    new_sp &= ~@as(u64, 15);

    {
        i += 1;
        new_entry.dtb_ptr = @intToPtr([*]const u8, p.PAGING.kernelPageAddress(i));
        var dtb_target = @intToPtr([*]u8, bump.next)[0..entry_data.dtb_len];

        // How many pages?
        const dtb_pages = (entry_data.dtb_len + p.PAGING.page_size - 1) / p.PAGING.page_size;

        var new_end = end + 1 + dtb_pages; // Skip 1 page since UART is there
        entryAssert(new_end <= 512, "end got too big (3)");

        hw.entry_uart.carefully(.{ "MAP: DTB at    ", p.PAGING.kernelPageAddress(i), "~\r\n" });
        while (i < new_end) : (i += 1) {
            l3.map(i, bump.allocPage(), .kernel_rodata);
        }

        @memcpy(dtb_target, entry_data.dtb_ptr[0..entry_data.dtb_len]);
    }

    new_entry.bump_next = bump.next;

    const satp = (p.SATP{
        .ppn = @truncate(u44, @ptrToInt(p.K_DIRECTORY) >> p.PAGING.page_bits),
        .asid = 0,
        .mode = .sv39,
    }).toU64();

    hw.entry_uart.carefully(.{ "MAP: end at    ", p.PAGING.kernelPageAddress(i), ".\r\n" });
    hw.entry_uart.carefully(.{ "about to install:\r\nsp: ", new_sp, "\r\n" });
    hw.entry_uart.carefully(.{ "ra: ", daintree_main - daintree_base + p.PAGING.kernel_base, "\r\n" });
    hw.entry_uart.carefully(.{ "uart mapped to: ", p.PAGING.kernelPageAddress(end), "\r\n" });

    asm volatile (
        \\mv sp, %[sp]
        \\sfence.vma x0, x0
        \\csrw satp, %[satp]
        \\ret
        :
        : [sp] "{a0}" (new_sp), // Argument to daintree_main.
          [satp] "r" (satp),
          [ra] "{ra}" (daintree_main - daintree_base + p.PAGING.kernel_base),
        : "memory"
    );

    unreachable;
}
