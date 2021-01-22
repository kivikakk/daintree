const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const version = @import("version.zig").version;

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

    const exe = b.addExecutable("dainkrnl", "src/entry.zig");
    exe.addAssemblyFile("src/exception.s");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setLinkerScriptPath("linker.ld");
    exe.setVerboseLink(true);
    exe.addBuildOption([:0]const u8, "version", try b.allocator.dupeZ(u8, try version(b)));
    exe.install();

    b.default_step.dependOn(&exe.step);
}
