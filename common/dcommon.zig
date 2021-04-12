const std = @import("std");
const builtin = @import("builtin");

pub const version = std.builtin.Version{ .major = 0, .minor = 0, .patch = 2 };

pub const Arch = enum {
    arm64,
    riscv64,
};

pub const daintree_arch: Arch = switch (builtin.target.cpu.arch) {
    .aarch64 => .arm64,
    .riscv64 => .riscv64,
    else => @panic("unsupported arch"),
};

pub const daintree_kernel_start: u64 = switch (daintree_arch) {
    .arm64 => 0xffffff80_00000000,
    .riscv64 => 0xffffffc0_00000000,
};

pub const Board = enum {
    qemu_arm64,
    qemu_riscv64,
    rockpro64,
};

/// Used both in dainboot passing to dainkrnl's daintree_mmu_start, and in
/// daintree_mmu_start passing to daintree_main.
pub const EntryData = struct {
    /// dainboot->daintree_mmu_start: PA.  Unused after.
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,

    /// PA before and after.
    dtb_ptr: [*]const u8,
    dtb_len: usize,
    conventional_start: usize,
    conventional_bytes: usize,

    /// PA before and after.
    fb: ?[*]u32,
    fb_horiz: u32,
    fb_vert: u32,

    /// dainboot->daintree_mmu_start: PA.  daintree_mmu_start->daintree_main: VA.
    uart_base: u64,
    uart_width: u3,

    bump_next: usize = 0,
};
