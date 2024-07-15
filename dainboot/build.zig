const std = @import("std");

const dbuild = @import("src/common/dbuild.zig");
const dcommon = @import("src/common/dcommon.zig");

pub fn build(b: *std.Build) !void {
    const board = try dbuild.getBoard(b);
    var targetQuery = dbuild.queryFor(board);
    targetQuery.os_tag = .uefi;
    const resolvedTarget = b.resolveTargetQuery(targetQuery);

    if (resolvedTarget.query.cpu_arch.? == .riscv64) {
        try buildRiscv64(b, board, resolvedTarget);
        return;
    }

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = bootName(b, board, resolvedTarget),
        .root_source_file = b.path("src/dainboot.zig"),
        .target = resolvedTarget,
        .optimize = optimize,
    });
    try dbuild.addBuildOptions(b, exe, board);
    const dtb = b.dependency("dtb.zig", .{
        .target = resolvedTarget,
        .optimize = optimize,
    }).module("dtb");
    exe.root_module.addImport("dtb", dtb);

    b.installArtifact(exe);

    b.default_step.dependOn(&exe.step);
}

fn buildRiscv64(b: *std.Build, board: dcommon.Board, resolvedTarget: std.Build.ResolvedTarget) !void {
    const optimize = b.standardOptimizeOption(.{});

    const crt0 = b.addAssembly(.{
        .name = "crt0-efi-riscv64",
        .source_file = b.path("src/crt0-efi-riscv64.S"),
        .target = resolvedTarget, // .os_tag = .freestanding
        .optimize = optimize,
    });

    const obj = b.addObject(.{
        .name = bootName(b, board, resolvedTarget),
        .root_source_file = b.path("src/dainboot.zig"),
        .target = resolvedTarget,
        .optimize = optimize,
    });
    try dbuild.addBuildOptions(b, obj, board);

    const dtb = b.dependency("dtb.zig", .{
        .target = resolvedTarget,
        .optimize = optimize,
    }).module("dtb");
    obj.root_module.addImport("dtb", dtb);

    const combined = b.addSystemCommand(&.{
        "ld.lld",
        "-nostdlib",
        "-znocombreloc",
        "-T",
        "elf_riscv64_efi.lds",
        "-shared",
        "-Bsymbolic",
        "-o",
        "combined.o",
        "-s",
    });
    combined.addArtifactArg(crt0);
    combined.addArtifactArg(obj);

    try std.fs.cwd().makePath("zig-out/bin");
    const efi = b.addSystemCommand(&.{
        "llvm-objcopy",
        "-j",
        ".header",
        "-j",
        ".text",
        "-j",
        ".plt",
        "-j",
        ".sdata",
        "-j",
        ".data",
        "-j",
        ".dynamic",
        "-j",
        ".dynstr",
        "-j",
        ".dynsym",
        "-j",
        ".rel*",
        "-j",
        ".rela*",
        "-j",
        ".reloc",
        "--output-target=binary",
        "combined.o",
        b.fmt("zig-out/bin/{s}.efi", .{bootName(b, board, resolvedTarget)}),
    });
    efi.step.dependOn(&combined.step);

    b.default_step.dependOn(&efi.step);
}

fn bootName(b: *std.Build, board: dcommon.Board, resolvedTarget: std.Build.ResolvedTarget) []const u8 {
    return b.fmt("BOOT{s}.{s}", .{ dbuild.efiTagFor(resolvedTarget.query.cpu_arch.?), @tagName(board) });
}
