const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const common = @import("common.zig");

pub fn build(b: *Builder) !void {
    // force strict alignment since we run without MMU, very hacky
    var features = std.Target.Cpu.Feature.Set.empty;
    features.addFeature(@enumToInt(std.Target.aarch64.Feature.strict_align));

    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_add = features,
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
