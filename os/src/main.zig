const build_options = @import("build_options");
const entry = @import("entry.zig");
const fb = @import("console/fb.zig");
const printf = fb.printf;
const halt = @import("halt.zig").halt;

// From daintree_mmu_start.
export fn daintree_main(entry_data: *entry.EntryData) void {
    fb.init(entry_data.fb, entry_data.fb_vert, entry_data.fb_horiz);
    printf("\x1b\x0adaintree \x1b\x07{s}\n", .{build_options.version});

    halt();
}
