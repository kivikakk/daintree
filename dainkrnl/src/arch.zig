const dcommon = @import("common/dcommon.zig");

pub usingnamespace switch (dcommon.daintree_arch) {
    .arm64 => @import("arm64/arch.zig"),
    .riscv64 => @import("riscv64/arch.zig"),
};
