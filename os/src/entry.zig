const std = @import("std");
const build_options = @import("build_options");
const framebuffer = @import("framebuffer.zig");
const memory = @import("memory.zig");
comptime {
    _ = memory.daintree_start;
}

const printf = framebuffer.printf;

pub const EntryData = packed struct {
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    fb: [*]u32,
    fb_vert: u32,
    fb_horiz: u32,
};

comptime {
    std.testing.expectEqual(40, @sizeOf(EntryData));
}

// export fn daintree_start(
//     // memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
//     // memory_map_size: usize,
//     // descriptor_size: usize,
//     // fb: [*]u32,
//     // fb_vert: u32,
//     // fb_horiz: u32,
// ) callconv(.Naked) void {
//     memory.init();
//     // memory.init(EntryData{
//     //     .memory_map = memory_map,
//     //     .memory_map_size = memory_map_size,
//     //     .descriptor_size = descriptor_size,
//     //     .fb = fb,
//     //     .fb_vert = fb_vert,
//     //     .fb_horiz = fb_horiz,
//     // });
// }

export fn daintree_main(entry_data: *EntryData) void {
    asm volatile (
        \\mov x12, %[fb_addr]
        \\b .
        :
        : [fb_addr] "r" (entry_data.fb)
        : "volatile"
    );
    // framebuffer.init(entry_data.fb, entry_data.fb_vert, entry_data.fb_horiz);
    // printf("\x1b\x0adaintree \x1b\x07{s}\n", .{build_options.version});

    // printf("all systems \x1b\x0ago\x1b\x07\n", .{});
    // halt();
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    while (true) {}
    const msg_len: framebuffer.CONSOLE_DIMENSION = @truncate(framebuffer.CONSOLE_DIMENSION, "kernel panic: ".len + msg.len);
    const left: framebuffer.CONSOLE_DIMENSION = framebuffer.console_width - msg_len - 2;

    framebuffer.colour(0x4f);
    framebuffer.locate(0, left);
    var x: framebuffer.CONSOLE_DIMENSION = 0;
    while (x < msg_len + 2) : (x += 1) {
        framebuffer.print(" ");
    }
    framebuffer.locate(1, left);
    printf(" kernel panic: {s} ", .{msg});
    framebuffer.locate(2, left);
    x = 0;
    while (x < msg_len + 2) : (x += 1) {
        framebuffer.print(" ");
    }
    halt();
}

fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}
