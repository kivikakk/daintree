export fn daintree_start() void {
    while (true) {
        asm volatile ("nop");
        asm volatile ("wfi");
    }
}
