const std = @import("std");
const uefi = std.os.uefi;
const elf = @import("elf.zig");
const dcommon = @import("common/dcommon.zig");

pub fn halt() noreturn {
    @panic("unimpl");
}

pub fn transfer(entry_data: *dcommon.EntryData, uart_base: u64, adjusted_entry: u64) callconv(.Inline) noreturn {
    @panic("unimpl");
}

pub fn cleanInvalidateDCacheICache(start: u64, len: u64) callconv(.Inline) void {
    @panic("unimpl");
}

fn busyLoop() void {
    var i: usize = 0;
    while (i < 1_000) : (i += 1) {
        asm volatile ("nop");
    }
}

pub fn hex(n: u64) void {
    const ptr: *volatile u8 = @intToPtr(*volatile u8, 0x10000000);
    ptr.* = '<';
    busyLoop();

    if (n == 0) {
        ptr.* = '0';
        busyLoop();
        ptr.* = '>';
        busyLoop();
        return;
    }

    var digits: usize = 0;
    var c = n;
    while (c > 0) : (c /= 16) {
        digits += 1;
    }
    c = n;
    var pow: usize = std.math.powi(u64, 16, digits - 1) catch 0;
    while (pow > 0) : (pow /= 16) {
        var digit = c / pow;
        if (digit >= 0 and digit <= 9) {
            ptr.* = '0' + @truncate(u8, digit);
        } else if (digit >= 10 and digit <= 16) {
            ptr.* = 'a' + @truncate(u8, digit) - 10;
        } else {
            ptr.* = '?';
        }
        busyLoop();
        c -= (digit * pow);
    }
    ptr.* = '>';
    busyLoop();
}

export fn relocate(ldbase: u64, dyn: [*]elf.Elf64_Dyn) uefi.Status {
    // Ported from
    // https://source.denx.de/u-boot/u-boot/-/blob/52ba373b7825e9feab8357065155cf43dfe2f4ff/arch/riscv/lib/reloc_riscv_efi.c.
    var rel: ?*elf.Elf64_Rela = null;
    var relent: usize = 0;
    var relsz: usize = 0;

    var i: usize = 0;
    while (dyn[i].d_tag != elf.DT_NULL) : (i += 1) {
        switch (dyn[i].d_tag) {
            elf.DT_RELA => rel = @intToPtr(*elf.Elf64_Rela, dyn[i].d_val + ldbase),
            elf.DT_RELASZ => relsz = dyn[i].d_val,
            elf.DT_RELAENT => relent = dyn[i].d_val,
            else => {},
        }
    }

    if (rel == null and relent == 0) {
        return .Success;
    }

    if (rel == null or relent == 0) {
        return .LoadError;
    }

    var relp = rel.?;

    const ptr: *volatile u8 = @intToPtr(*volatile u8, 0x10000000);
    hex(relsz);
    ptr.* = '\n';
    busyLoop();

    while (relsz > 0) {
        hex(relp.r_info);
        ptr.* = '\n';
        busyLoop();
        if ((relp.r_info & 0xffffffff) == 3) {
            // R_RISCV_RELATIVE
            var addr: *u64 = @intToPtr(*u64, ldbase + relp.r_offset);
            if (relp.r_addend > 0) {
                addr.* = ldbase + std.math.absCast(relp.r_addend);
            } else {
                addr.* = ldbase - std.math.absCast(relp.r_addend);
            }
        } else {
            asm volatile (
                \\j 0
                :
                : [r_info] "{t0}" (relp.r_info),
                  [dyn] "{t1}" (@ptrToInt(dyn)),
                  [i] "{t2}" (i),
                  [rel] "{t3}" (@ptrToInt(rel))
                : "memory"
            );
        }
        relp = @intToPtr(*elf.Elf64_Rela, @ptrToInt(relp) + relent);
        relsz -= relent;
    }

    return .Success;
}
