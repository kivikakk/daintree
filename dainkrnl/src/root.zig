const std = @import("std");
const arch = @import("arch.zig");

// Must be pub at build root -- Zig will use this, see lib/std/builtin.zig's 'panic'.
pub const panic = arch.panic;

comptime {
    // Pull in exception vector exports
    _ = switch (std.builtin.arch) {
        .aarch64 => @import("arm64/exception.zig"),
        .riscv64 => @import("riscv64/exception.zig"),
        else => @panic("unknown arch"),
    };

    // Pull in arch-specific entry point.
    _ = switch (std.builtin.arch) {
        .aarch64 => @import("arm64/entry.zig"),
        .riscv64 => @import("riscv64/entry.zig"),
        else => @panic("unknown arch"),
    };

    // Pull in daintree_main export, which we jump to at the end of daintree_mmu_start.
    _ = @import("main.zig");
}
