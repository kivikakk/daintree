export fn daintree_start() void {
    while (true) {
        asm volatile ("nop");
        asm volatile ("br x0"
            :
            : [x0] "{x0}" (@as(u64, 0x1234567812345678))
            : "memory"
        );
        asm volatile ("wfi");
    }
}
