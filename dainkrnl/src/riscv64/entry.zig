const std = @import("std");
const build_options = @import("build_options");
const dcommon = @import("../common/dcommon.zig");
const arch = @import("arch.zig");
const hw = @import("../hw.zig");

/// dainboot passes control here.  MMU is **off**.
pub export fn daintree_mmu_start(entry_data: *dcommon.EntryData) noreturn {
    hw.entry_uart.base = @intToPtr(*volatile u8, entry_data.uart_base);

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

    arch.halt();
}
