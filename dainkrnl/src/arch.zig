const std = @import("std");

pub usingnamespace switch (std.builtin.arch) {
    .aarch64 => @import("arm64/arch.zig"),
    .riscv64 => @import("riscv64/arch.zig"),
    else => @panic("unknown arch"),
};
