usingnamespace @import("hacks.zig");

const ExceptionContext = packed struct {
    regs: [30]u64,
    elr_el1: u64,
    spsr_el1: u64,
    lr: u64,
};

export fn test_naked() callconv(.Naked) void {
    asm volatile (
        \\br x10
        :
        :
        : "memory"
    );
}

fn handle(ctx: *ExceptionContext, comptime name: []const u8) callconv(.Inline) noreturn {
    HACK_uart(.{"exception handler running for " ++ name ++ "\r\n"});

    dumpRegs(ctx);

    @panic(name);
}

fn dumpRegs(ctx: *ExceptionContext) void {
    HACK_uart(.{ "ctx ptr:", @ptrToInt(ctx), "\r\n" });
    HACK_uart(.{ "x0  ", ctx.regs[0], "  x1  ", ctx.regs[1], "\r\n" });
    HACK_uart(.{ "x2  ", ctx.regs[2], "  x3  ", ctx.regs[3], "\r\n" });
    HACK_uart(.{ "x4  ", ctx.regs[4], "  x5  ", ctx.regs[5], "\r\n" });
    HACK_uart(.{ "x6  ", ctx.regs[6], "  x7  ", ctx.regs[7], "\r\n" });
    HACK_uart(.{ "x8  ", ctx.regs[8], "  x9  ", ctx.regs[9], "\r\n" });
    HACK_uart(.{ "x10 ", ctx.regs[10], "  x11 ", ctx.regs[11], "\r\n" });
    HACK_uart(.{ "x12 ", ctx.regs[12], "  x13 ", ctx.regs[13], "\r\n" });
    HACK_uart(.{ "x14 ", ctx.regs[14], "  x15 ", ctx.regs[15], "\r\n" });
    HACK_uart(.{ "x16 ", ctx.regs[16], "  x17 ", ctx.regs[17], "\r\n" });
    HACK_uart(.{ "x18 ", ctx.regs[18], "  x19 ", ctx.regs[19], "\r\n" });
    HACK_uart(.{ "x20 ", ctx.regs[20], "  x21 ", ctx.regs[21], "\r\n" });
    HACK_uart(.{ "x22 ", ctx.regs[22], "  x23 ", ctx.regs[23], "\r\n" });
    HACK_uart(.{ "x24 ", ctx.regs[24], "  x25 ", ctx.regs[25], "\r\n" });
    HACK_uart(.{ "x26 ", ctx.regs[26], "  x27 ", ctx.regs[27], "\r\n" });
    HACK_uart(.{ "x28 ", ctx.regs[28], "  x29 ", ctx.regs[29], "\r\n" });
    HACK_uart(.{ "elr ", ctx.elr_el1, "  sps ", ctx.spsr_el1, "\r\n" });
    HACK_uart(.{ "lr  ", ctx.lr, "\r\n\r\n" });
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

export fn el1_sync(ctx: *ExceptionContext, elr_el1: u64, esr_el1: u64) void {
    // HACK: dump ELR_EL1/ESR_EL1 before we try to reach through any pointers.
    HACK_uart2(elr_el1);
    HACK_uart2(esr_el1);
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
