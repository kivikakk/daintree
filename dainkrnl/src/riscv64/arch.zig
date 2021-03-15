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

pub fn reset() void {
    @panic("unimpl: reset");
}

pub fn poweroff() void {
    @panic("unimpl: poweroff");
}

pub const SATP = struct {
    pub fn toU64(satp: SATP) callconv(.Inline) u64 {
        return @as(u64, satp.ppn) |
            (@as(u64, satp.asid) << 44) |
            (@as(u64, @enumToInt(satp.mode)) << 60);
    }

    ppn: u44,
    asid: u16,
    mode: enum(u4) {
        bare = 0,
        sv39 = 8,
        sv48 = 9,
    },
};

pub const RWX = enum(u3) {
    non_leaf = 0b000,
    ro = 0b001,
    rw = 0b011,
    rx = 0b101,
    rwx = 0b111,
};

pub const PageTableEntry = struct {
    pub fn toU64(pte: PageTableEntry) callconv(.Inline) u64 {
        return @as(u64, pte.v) |
            (@as(u64, @enumToInt(pte.rwx)) << 1) |
            (@as(u64, pte.u) << 4) |
            (@as(u64, pte.g) << 5) |
            (@as(u64, pte.a) << 6) |
            (@as(u64, pte.d) << 7) |
            (@as(u64, pte.ppn) << 10);
    }

    // Set rwx=000 to indicate a non-leaf PTE.

    v: u1 = 1,
    rwx: RWX,
    u: u1, // Accessible to usermode.
    g: u1, // Global mapping (exists in all address spaces).
    a: u1, // Access bit.
    d: u1, // Dirty bit.
    // _res_rsw: u2,  // Reserved; ignore.
    ppn: u44,
    // _res: u10,
};
