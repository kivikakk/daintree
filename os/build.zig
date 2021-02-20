const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const dbuild = @import("src/common/dbuild.zig");

pub fn build(b: *Builder) !void {
    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
        .os_tag = .freestanding,
        .abi = .none,
    };

    const board = try dbuild.getBoard(b);
    const exe = b.addExecutable(b.fmt("dainkrnl.{s}", .{@tagName(board)}), "src/entry.zig");
    exe.addAssemblyFile("src/exception.s");
    exe.addPackagePath("dtb", "../dtb/src/dtb.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setLinkerScriptPath("linker.ld");
    exe.setVerboseLink(true);

    // Avoid using atomic stores/loads in suspend/resume code.
    // Right now they fail with ESR 96000035 which suggests the PE doesn't think
    // the stack is appropriate -- see B2.9.2 (page B2-137~139).  It looks fine?
    // Need to see what other settings might be causing the area to appear non-
    // cacheable.  It's weird, because we definitely do see caching activity ...
    // I saw something online mentioning PSCI core init at some point?  Surely not.
    exe.single_threaded = true;

    try dbuild.addBuildOptions(b, exe, board);
    exe.install();

    b.default_step.dependOn(&exe.step);
}
