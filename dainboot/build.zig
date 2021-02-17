const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const dcommon = @import("src/common/dcommon.zig");

pub fn build(b: *Builder) !void {
    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
        .os_tag = .uefi,
    };

    const board = try dcommon.getBoard(b);
    const exe = b.addExecutable(b.fmt("BOOTAA64.{s}", .{@tagName(board)}), "src/dainboot.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    try dcommon.addBuildOptions(b, exe, board);
    exe.addPackagePath("dtb", "../dtb/src/dtb.zig");
    exe.install();

    b.default_step.dependOn(&exe.step);
}
