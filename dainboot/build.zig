const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const dbuild = @import("src/common/dbuild.zig");

pub fn build(b: *Builder) !void {
    const board = try dbuild.getBoard(b);
    var target = dbuild.crossTargetFor(board);
    target.os_tag = .uefi;

    const exe = b.addExecutable(b.fmt("BOOT{s}.{s}", .{ dbuild.efiTagFor(target.cpu_arch.?), @tagName(board) }), "src/dainboot.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    try dbuild.addBuildOptions(b, exe, board);
    exe.addPackagePath("dtb", "../dtb/src/dtb.zig");
    exe.install();

    b.default_step.dependOn(&exe.step);
}
