const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const dbuild = @import("src/common/dbuild.zig");

pub fn build(b: *Builder) !void {
    const board = try dbuild.getBoard(b);
    var target = dbuild.crossTargetFor(board);
    target.os_tag = .freestanding;
    target.abi = .none;

    const arch_tag = dbuild.getArch(board);

    const exe = b.addExecutable(b.fmt("dainkrnl.{s}", .{@tagName(board)}), "src/root.zig");
    if (dbuild.getArch(board) == .riscv64) {
        exe.code_model = .medium;
    }
    exe.addAssemblyFile(b.fmt("src/{s}/exception.s", .{@tagName(arch_tag)}));
    exe.addPackagePath("dtb", "../dtb/src/dtb.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setLinkerScriptPath(b.fmt("linker.{s}.ld", .{@tagName(arch_tag)}));
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
