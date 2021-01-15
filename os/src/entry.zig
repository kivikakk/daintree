const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");
const framebuffer = @import("framebuffer.zig");
const font = @import("font.zig");

const printf = framebuffer.printf;

export fn daintree_start(
    memory_map: [*]uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    fb: [*]u32,
    fb_vert: u32,
    fb_horiz: u32,
) void {
    framebuffer.init(fb, fb_vert, fb_horiz);
    printf("\x1b\x0adaintree \x1b\x07{s}\n", .{build_options.version});
    var i: u8 = 0;
    while (i < 50) : (i += 1) {
        printf("  * {}\n", .{i});
    }

    halt();
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
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
