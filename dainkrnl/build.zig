const std = @import("std");

const dbuild = @import("src/common/dbuild.zig");

pub fn build(b: *std.Build) !void {
    const board = try dbuild.getBoard(b);
    var targetQuery = dbuild.queryFor(board);
    targetQuery.os_tag = .freestanding;
    targetQuery.abi = .none;
    const resolvedTarget = b.resolveTargetQuery(targetQuery);

    const arch_tag = dbuild.getArch(board);
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = b.fmt("dainkrnl.{s}", .{@tagName(board)}),
        .root_source_file = b.path("src/root.zig"),
        .target = resolvedTarget,
        .optimize = optimize,
    });

    if (dbuild.getArch(board) == .riscv64) {
        exe.root_module.code_model = .medium;
    }
    exe.addAssemblyFile(b.path(b.fmt("src/{s}/exception.s", .{@tagName(arch_tag)})));
    const dtb = b.dependency("dtb.zig", .{
        .target = resolvedTarget,
        .optimize = optimize,
    }).module("dtb");
    exe.root_module.addImport("dtb", dtb);

    exe.setLinkerScriptPath(b.path(b.fmt("linker.{s}.ld", .{@tagName(arch_tag)})));
    exe.setVerboseLink(true);

    // Commented out because we don't use (= Zig doesn't have) suspend/resume code any more.
    // // Avoid using atomic stores/loads in suspend/resume code.
    // // Right now they fail with ESR 96000035 which suggests the PE doesn't think
    // // the stack is appropriate -- see B2.9.2 (page B2-137~139).  It looks fine?
    // // Need to see what other settings might be causing the area to appear non-
    // // cacheable.  It's weird, because we definitely do see caching activity ...
    // // I saw something online mentioning PSCI core init at some point?  Surely not.
    // exe.single_threaded = true;

    try dbuild.addBuildOptions(b, exe, board);
    b.installArtifact(exe);

    b.default_step.dependOn(&exe.step);
}
