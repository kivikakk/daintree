const std = @import("std");
const fb = @import("../console/fb.zig");
const hw = @import("../hw.zig");
const printf = @import("../console/fb.zig").printf;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;

    hw.entry_uart.carefully(.{"\r\n!!!!!!!!!!!!\r\nkernel panic\r\n!!!!!!!!!!!!\r\n"});
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
    return asm volatile ("la %[ret], " ++ symbol
        : [ret] "=r" (-> u64),
    );
}

pub const Register = enum { satp };
pub inline fn writeRegister(comptime register: Register, value: u64) void {
    asm volatile ("csrw " ++ @tagName(register) ++ ", %[value]"
        :
        : [value] "r" (value),
        : "memory"
    );
}

pub inline fn readRegister(comptime register: Register) u64 {
    return asm volatile ("csrr %[ret], " ++ @tagName(register)
        : [ret] "=r" (-> u64),
    );
}

pub inline fn orRegister(comptime register: Register, value: u64) void {
    asm volatile ("csrs " ++ @tagName(register) ++ ", %[value]"
        :
        : [value] "r" (value),
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
    _ = ms;
    // XXX impl
}

pub fn reset() noreturn {
    hw.syscon.reboot();
}

pub fn poweroff() noreturn {
    hw.syscon.poweroff();
}
