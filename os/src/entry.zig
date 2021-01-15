export fn daintree_start(fb: [*]u8) void {
    asm volatile ("nop");
    asm volatile ("nop");
    asm volatile ("nop");
    asm volatile ("nop");
    asm volatile ("nop");
    asm volatile ("nop");
    var i: u32 = 0;
    while (i < 640 * 480 * 4) : (i += 4) {
        fb[i] = @truncate(u8, @divTrunc(i, 256));
        fb[i + 1] = @truncate(u8, @divTrunc(i, 1536));
        fb[i + 2] = @truncate(u8, @divTrunc(i, 2560));
    }
    asm volatile ("b .");
}
