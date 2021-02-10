const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const common = @import("common.zig");

pub fn build(b: *Builder) !void {
    // We used to force strict alignment since we run without MMU. Now we do enable it,
    // but maybe we'll need to put it back on again later if our pre-MMU code generates a badly aligned access?
    // var features = std.Target.Cpu.Feature.Set.empty;
    // features.addFeature(@enumToInt(std.Target.aarch64.Feature.strict_align));
    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
        .os_tag = .freestanding,
        .abi = .none,
        // .cpu_features_add = features,
    };

    const board = try common.getBoard(b);
    const exe = b.addExecutable(b.fmt("dainkrnl.{s}", .{@tagName(board)}), "src/entry.zig");
    exe.addAssemblyFile("src/exception.s");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setLinkerScriptPath("linker.ld");
    exe.setVerboseLink(true);
    try common.addBuildOptions(b, exe, board);
    exe.install();

    b.default_step.dependOn(&exe.step);
}
