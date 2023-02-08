const dcommon = @import("common/dcommon.zig");

pub usingnamespace switch (dcommon.daintree_arch) {
    .arm64 => @import("arm64.zig"),
    .riscv64 => @import("riscv64.zig"),
};
