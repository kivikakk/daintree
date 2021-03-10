const std = @import("std");
const dcommon = @import("common/dcommon.zig");
const arch = @import("arch.zig");

// Must be pub at build root -- Zig will use this, see lib/std/builtin.zig's 'panic'.
pub const panic = arch.panic;

comptime {
    // Pull in exception vector exports, arch-specific entry point.
    _ = @import(@tagName(dcommon.daintree_arch) ++ "/exception.zig");
    _ = @import(@tagName(dcommon.daintree_arch) ++ "/entry.zig");

    // Pull in daintree_main export, which we jump to at the end of daintree_mmu_start.
    _ = @import("main.zig");
}
