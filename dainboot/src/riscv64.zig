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

    while (relsz > 0) {
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
                : [r_info] "{t0}" (relp.r_info)
                : "memory"
            );
        }
        relp = @intToPtr(*elf.Elf64_Rela, @ptrToInt(relp) + relent);
        relsz -= relent;
    }

    return .Success;
}
