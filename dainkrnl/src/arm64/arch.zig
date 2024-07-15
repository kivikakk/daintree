const std = @import("std");
const fb = @import("../console/fb.zig");
const hw = @import("../hw.zig");
const printf = @import("../console/fb.zig").printf;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    hw.entry_uart.carefully(.{"\r\n!!!!!!!!!!!!\r\nkernel panic\r\n!!!!!!!!!!!!\r\n"});
    const current_el = readRegister(.CurrentEL) >> 2;
    const sctlr_el1 = readRegister(.SCTLR_EL1);
    hw.entry_uart.carefully(.{ "CurrentEL: ", current_el, "\r\n" });
    hw.entry_uart.carefully(.{ "SCTLR_EL1: ", sctlr_el1, "\r\n" });
    if (error_return_trace) |ert| {
        hw.entry_uart.carefully(.{"trying to print stack ... \r\n"});
        var frame_index: usize = 0;
        var frames_left: usize = @min(ert.index, ert.instruction_addresses.len);
        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % ert.instruction_addresses.len;
        }) {
            const return_address = ert.instruction_addresses[frame_index];
            hw.entry_uart.carefully(.{ return_address, "\r\n" });
        }
    } else {
        hw.entry_uart.carefully(.{"no ert\r\n"});
    }
    hw.entry_uart.carefully(.{ "ret_addr: ", ret_addr, "\r\n" });
    hw.entry_uart.carefully(.{ "@returnAddress: ", @returnAddress(), "\r\n" });

    hw.entry_uart.carefully(.{ "panic message ptr: ", @intFromPtr(msg.ptr), "\r\n<" });
    hw.entry_uart.carefully(.{ hw.entry_uart.Escape.Runtime, msg, ">\r\n" });

    if (fb.present()) {
        fb.panicMessage(msg);
    }

    halt();
}

pub inline fn loadAddress(comptime symbol: []const u8) u64 {
    return asm volatile ("adr %[ret], " ++ symbol
        : [ret] "=r" (-> u64),
    );
}

pub const Register = enum {
    MAIR_EL1,
    TCR_EL1,
    TTBR0_EL1,
    TTBR1_EL1,
    SCTLR_EL1,
    CurrentEL,
    CPACR_EL1,
    CPTR_EL2,
    CPTR_EL3,
};
pub inline fn writeRegister(comptime register: Register, value: u64) void {
    asm volatile ("msr " ++ @tagName(register) ++ ", %[value]"
        :
        : [value] "r" (value),
        : "memory"
    );
}

pub inline fn readRegister(comptime register: Register) u64 {
    return asm volatile ("mrs %[ret], " ++ @tagName(register)
        : [ret] "=r" (-> u64),
    );
}

pub inline fn orRegister(comptime register: Register, value: u64) void {
    asm volatile ("mrs x0, " ++ @tagName(register) ++ "\n" ++
            "orr x0, x0, %[value]\n" ++
            "msr " ++ @tagName(register) ++ ", x0\n"
        :
        : [value] "r" (value),
        : "memory", "x0"
    );
}

pub fn sleep(ms: u64) void {
    // CURSED
    // CURSED
    // CURSED
    asm volatile (
        \\   isb
        \\   mrs x1, cntpct_el0
        \\   mrs x2, cntfrq_el0            // x2 has ticks pers second (Hz)
        \\   mov x3, #1000
        \\   udiv x2, x2, x3               // x2 has ticks per millisecond
        \\   mul x2, x2, x0                // x2 has ticks per `ms` milliseconds
        \\   add x2, x1, x2                // x2 has start time + ticks
        \\1: cmp x1, x2
        \\   b.hs 2f
        \\   isb
        \\   mrs x1, cntpct_el0
        \\   b 1b
        \\2: nop
        :
        : [ms] "{x0}" (ms),
        : "x1", "x2", "x3"
    );
}

pub fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}

pub fn reset() noreturn {
    psci(0x8400_0009);
}

pub fn poweroff() noreturn {
    psci(0x8400_0008);
}

fn psci(val: u32) noreturn {
    switch (hw.psci.method) {
        .Hvc => {
            printf("goodbye\n", .{});
            asm volatile (
                \\msr daifset, #15
                \\hvc 0
                :
                : [val] "{x0}" (val),
                : "memory"
            );
        },
        .Smc => {
            printf("goodbye\n", .{});
            asm volatile (
                \\msr daifset, #15
                \\smc 0
                :
                : [val] "{x0}" (val),
                : "memory"
            );
        },
        else => @panic("unknown psci method"),
    }
    sleep(5000);
    @panic("psci returned");
}
