pub const PagingConfigurationInput = struct {
    translation_levels: u2 = 3,
    index_bits: u6 = 9,
    page_bits: u6 = 12,

    vaddress_mask: u64,
};

pub fn configuration(comptime config: PagingConfigurationInput) PagingConfiguration {
    const page_size = 1 << config.page_bits;
    const page_mask = page_size - 1;
    const block_l1_bits = config.page_bits + (config.translation_levels - 1) * config.index_bits;

    return .{
        .translation_levels = config.translation_levels,
        .index_bits = config.index_bits,
        .page_bits = config.page_bits,
        .vaddress_mask = config.vaddress_mask,

        .page_size = page_size,
        .page_mask = page_mask,
        .index_size = 1 << config.index_bits,
        .address_bits = config.page_bits + config.translation_levels * config.index_bits,
        .kernel_base = ~@as(u64, config.vaddress_mask | page_mask),

        .block_l1_bits = block_l1_bits,
        .block_l1_size = 1 << block_l1_bits,
    };
}

pub const PagingConfiguration = struct {
    translation_levels: u2 = 3,
    index_bits: u6 = 9,
    page_bits: u6 = 12,

    vaddress_mask: u64,

    // computed

    page_size: u64,
    page_mask: u64,
    index_size: u64,
    address_bits: u8,
    kernel_base: u64,

    block_l1_bits: u8,
    block_l1_size: u64,

    pub fn index(self: PagingConfiguration, comptime level: u2, va: u64) callconv(.Inline) usize {
        if (level == 0) {
            @compileError("level must be 1, 2, 3");
        }

        return (va & self.vaddress_mask) >> (@as(u6, 3 - level) * self.index_bits + self.page_bits);
    }

    pub fn kernelPageAddress(self: PagingConfiguration, i: usize) callconv(.Inline) u64 {
        return self.kernel_base | (i << self.page_bits);
    }
};
