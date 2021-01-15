const std = @import("std");
const uefi = std.os.uefi;
const build_options = @import("build_options");
const font = @import("font.zig");

export fn daintree_start(
    memory_map: [*]uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    in_fb: [*]u32,
    in_vert: u32,
    in_horiz: u32,
) void {
    // for (memory_map[0 .. memory_map_size / descriptor_size]) |ptr, i| {
    // printf("{:3} {s:23} p=0x{x:0>16} size={:16}\r\n", .{ i, @tagName(ptr.type), ptr.physical_start, ptr.number_of_pages << 12 });
    // }
    fb = in_fb;
    fb_vert = in_vert;
    fb_horiz = in_horiz;

    var y: u32 = 0;
    while (y < fb_vert) : (y += 1) {
        var x: u32 = 0;
        while (x < fb_horiz) : (x += 1) {
            fbPlot(x, y, 0x00000000);
        }
    }

    font.print("daintree ", 0x0a);
    font.print(build_options.version ++ "\n", 0x07);

    halt();
}

var fb: [*]u32 = undefined;
var fb_vert: u32 = undefined;
var fb_horiz: u32 = undefined;

pub fn fbPlot(x: u32, y: u32, c: u32) void {
    fb[fb_horiz * y + x] = c;
}

fn halt() noreturn {
    asm volatile ("msr daifset, #15");
    while (true) {
        asm volatile ("wfi");
    }
}

fn puts(msg: []const u8) void {
    for (msg) |c| {
        const c_ = [2]u16{ c, 0 };
        //   _ = con_out.outputString(@ptrCast(*const [1:0]u16, &c_));
    }
}

fn printf(comptime format: []const u8, args: anytype) void {
    var buf: [256]u8 = undefined;
    puts(std.fmt.bufPrint(buf[0..], format, args) catch unreachable);
}
