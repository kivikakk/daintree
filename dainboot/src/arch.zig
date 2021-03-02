const std = @import("std");

pub usingnamespace switch (std.builtin.arch) {
    .aarch64 => @import("arm64.zig"),
    .riscv64 => @import("riscv64.zig"),
    else => @panic("unknown arch"),
};
