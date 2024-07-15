const std = @import("std");
const uefi = std.os.uefi;
const elf = std.elf;
const dcommon = @import("common/dcommon.zig");

pub fn halt() noreturn {
    asm volatile (
        \\   csrci mstatus, 1
        \\0: wfi
        \\   j 0b
    );
    unreachable;
}

pub inline fn transfer(entry_data: *dcommon.EntryData, uart_base: u64, adjusted_entry: u64) noreturn {
    // Supervisor mode, MMU disabled. (SATP = 0)
    _ = uart_base;

    asm volatile (
        \\ret
        :
        : [entry_data] "{a0}" (entry_data),
          [entry] "{ra}" (adjusted_entry),
        : "memory"
    );
    unreachable;
}

pub inline fn cleanInvalidateDCacheICache(start: u64, len: u64) void {
    _ = start;
    _ = len;

    // I think this does enough.
    asm volatile (
        \\fence.i
        ::: "memory");
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
            elf.DT_RELA => rel = @as(*elf.Elf64_Rela, @ptrFromInt(dyn[i].d_val + ldbase)),
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
        if (relp.r_type() == 3) {
            // R_RISCV_RELATIVE
            const addr: *u64 = @as(*u64, @ptrFromInt(ldbase + relp.r_offset));
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
                  [dyn] "{t1}" (@intFromPtr(dyn)),
                  [i] "{t2}" (i),
                  [rel] "{t3}" (@intFromPtr(rel)),
                : "memory"
            );
        }
        relp = @as(*elf.Elf64_Rela, @ptrFromInt(@intFromPtr(relp) + relent));
        relsz -= relent;
    }

    return .Success;
}

// For whatever reason, memset and memcpy implementations aren't being
// included, and it's adding a PLT and GOT to have them looked up later.  They
// aren't being provided by anyone else, so we must.
export fn memset(b: *anyopaque, c: c_int, len: usize) *anyopaque {
    std.mem.set(u8, @as([*]u8, @ptrFromInt(b))[0..len], @as(u8, @truncate(std.math.absCast(c))));
    return b;
}

export fn memcpy(dst: *anyopaque, src: *const anyopaque, n: usize) *anyopaque {
    std.mem.copy(u8, @as([*]u8, @ptrFromInt(dst))[0..n], @as([*]const u8, @ptrFromInt(src))[0..n]);
    return dst;
}
