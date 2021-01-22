const ExceptionContext = packed struct {
    regs: [30]u64,
    elr_el1: u64,
    spsr_el1: u64,
    lr: u64,
};

inline fn handle(ctx: *ExceptionContext, name: []const u8) noreturn {
    @panic(name);
}

export fn el1_sp0_sync(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_SP0_SYNC");
}

export fn el1_sp0_irq(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_SP0_IRQ");
}

export fn el1_sp0_fiq(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_SP0_FIQ");
}

export fn el1_sp0_error(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_SP0_ERROR");
}

export fn el1_sync(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_SYNC");
}

export fn el1_irq(ctx: *ExceptionContext) void {
    handle(ctx, "TODO: EL1_IRQ");
}

export fn el1_fiq(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_FIQ");
}

export fn el1_error(ctx: *ExceptionContext) void {
    handle(ctx, "EL1_ERROR");
}

export fn el0_sync(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_SYNC");
}

export fn el0_irq(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_IRQ");
}

export fn el0_fiq(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_FIQ");
}

export fn el0_error(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_ERROR");
}

export fn el0_32_sync(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_32_SYNC");
}

export fn el0_32_irq(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_32_IRQ");
}

export fn el0_32_fiq(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_32_FIQ");
}

export fn el0_32_error(ctx: *ExceptionContext) void {
    handle(ctx, "EL0_32_ERROR");
}
