const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const arch = @import("arch.zig");

// Must be pub at build root -- Zig will use this, see lib/std/builtin.zig's 'panic'.
pub const panic = arch.panic;

comptime {
    // Pull in exception vector exports, arch-specific entry point.
    switch (dcommon.daintree_arch) {
        .arm64 => {
            _ = @import("arm64/exception.zig");
            _ = @import("arm64/entry.zig");
        },
        .riscv64 => {
            _ = @import("riscv64/exception.zig");
            _ = @import("riscv64/entry.zig");
        },
    }

    // Pull in daintree_main export, which we jump to at the end of daintree_mmu_start.
    _ = @import("main.zig");
}
