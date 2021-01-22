pub fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}
