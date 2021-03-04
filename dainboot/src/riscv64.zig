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

export fn relocate(ldbase: c_long, dyn: *elf.Elf64_Dyn) uefi.Status {
    return .Success;
}
