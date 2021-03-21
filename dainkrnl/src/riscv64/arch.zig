const std = @import("std");
const fb = @import("../console/fb.zig");
const hw = @import("../hw.zig");
const printf = @import("../console/fb.zig").printf;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    hw.entry_uart.carefully(.{"\r\n!!!!!!!!!!!!\r\nkernel panic\r\n!!!!!!!!!!!!\r\n"});
    hw.entry_uart.carefully(.{ "@returnAddress: ", @returnAddress(), "\r\n" });

    hw.entry_uart.carefully(.{ "panic message ptr: ", @ptrToInt(msg.ptr), "\r\n<" });
    hw.entry_uart.carefully(.{ hw.entry_uart.Escape.Runtime, msg, ">\r\n" });

    if (fb.present()) {
        fb.panicMessage(msg);
    }

    halt();
}

pub fn loadAddress(comptime symbol: []const u8) callconv(.Inline) u64 {
    return asm volatile ("la %[ret], " ++ symbol
        : [ret] "=r" (-> u64)
    );
}

pub const Register = enum { satp };
pub fn writeRegister(comptime register: Register, value: u64) callconv(.Inline) void {
    asm volatile ("csrw " ++ @tagName(register) ++ ", %[value]"
        :
        : [value] "r" (value)
        : "memory"
    );
}

pub fn readRegister(comptime register: Register) callconv(.Inline) u64 {
    return asm volatile ("csrr %[ret], " ++ @tagName(register)
        : [ret] "=r" (-> u64)
    );
}

pub fn orRegister(comptime register: Register, value: u64) callconv(.Inline) void {
    asm volatile ("csrs " ++ @tagName(register) ++ ", %[value]"
        :
        : [value] "r" (value)
        : "memory"
    );
}

pub fn halt() noreturn {
    asm volatile (
        \\   csrci sstatus, 1
        \\0: wfi
        \\   j 0b
    );
    unreachable;
}

pub fn sleep(ms: u64) void {
    // XXX impl
}

pub fn reset() noreturn {
    hw.syscon.reboot();
}

pub fn poweroff() noreturn {
    hw.syscon.poweroff();
}
