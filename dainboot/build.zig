const std = @import("std");
const Build = std.Build;

const dbuild = @import("src/common/dbuild.zig");
const dcommon = @import("src/common/dcommon.zig");

pub fn build(b: *Build) !void {
    const board = try dbuild.getBoard(b);
    var target = dbuild.crossTargetFor(board);
    target.os_tag = .uefi;

    if (target.cpu_arch.? == .riscv64) {
        try buildRiscv64(b, board, target);
        return;
    }

    const exe = b.addExecutable(.{
        .name = bootName(b, board, target),
        .root_source_file = .{ .path = "src/dainboot.zig" },
        .target = target,
        .optimize = b.standardOptimizeOption(.{}),
    });
    try dbuild.addBuildOptions(b, exe, board);
    b.addModule(.{
        .name = "dtb",
        .source_file = .{ .path = "../dtb/src/dtb.zig" },
    });
    exe.addModule("dtb", b.modules.get("dtb").?);

    exe.install();

    b.default_step.dependOn(&exe.step);
}

fn buildRiscv64(b: *Build, board: dcommon.Board, target: std.zig.CrossTarget) !void {
    const crt0 = b.addAssembly(.{
        .name = "crt0-efi-riscv64",
        .source_file = .{ .path = "src/crt0-efi-riscv64.S" },
        .target = .{
            .cpu_arch = target.cpu_arch,
            .os_tag = .freestanding,
        },
        .optimize = b.standardOptimizeOption(.{}),
    });

    const obj = b.addObject(.{
        .name = bootName(b, board, target),
        .root_source_file = .{ .path = "src/dainboot.zig" },
        .target = target,
        .optimize = b.standardOptimizeOption(.{}),
    });
    try dbuild.addBuildOptions(b, obj, board);

    const dtb_pkg = b.dependency("dtb", .{});
    obj.addModule("dtb", dtb_pkg.module("dbt"));

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
        b.fmt("zig-out/bin/{s}.efi", .{bootName(b, board, target)}),
    });
    efi.step.dependOn(&combined.step);

    b.default_step.dependOn(&efi.step);
}

fn bootName(b: *Build, board: dcommon.Board, target: std.zig.CrossTarget) []const u8 {
    return b.fmt("BOOT{s}.{s}", .{ dbuild.efiTagFor(target.cpu_arch.?), @tagName(board) });
}
