const std = @import("std");
const Builder = std.build.Builder;

const dbuild = @import("src/common/dbuild.zig");
const dcommon = @import("src/common/dcommon.zig");

pub fn build(b: *Builder) !void {
    const board = try dbuild.getBoard(b);
    var target = dbuild.crossTargetFor(board);
    target.os_tag = .uefi;

    if (target.cpu_arch.? == .riscv64) {
        try buildRiscv64(b, board, target);
        return;
    }

    const exe = b.addExecutable(bootName(b, board, target), "src/dainboot.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    try dbuild.addBuildOptions(b, exe, board);
    exe.addPackagePath("dtb", "../dtb/src/dtb.zig");
    exe.install();

    b.default_step.dependOn(&exe.step);
}

fn buildRiscv64(b: *Builder, board: dcommon.Board, target: std.zig.CrossTarget) !void {
    const crt0 = b.addAssemble("crt0-efi-riscv64", "src/crt0-efi-riscv64.S");
    crt0.setTarget(std.zig.CrossTarget{
        .cpu_arch = target.cpu_arch,
        .os_tag = .freestanding,
    });
    crt0.setBuildMode(b.standardReleaseOptions());

    const obj = b.addObject(bootName(b, board, target), "src/dainboot.zig");
    obj.setTarget(target);
    obj.setBuildMode(b.standardReleaseOptions());
    try dbuild.addBuildOptions(b, obj, board);
    obj.addPackagePath("dtb", "../dtb/src/dtb.zig");

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

    const efi = b.addSystemCommand(&.{
        "llvm-objcopy",
        "-j",
        ".text",
        "-j",
        ".sdata",
        "-j",
        ".data",
        "-j",
        ".dynamic",
        "-j",
        ".dynsym",
        "-j",
        ".rel*",
        "-j",
        ".rela*",
        "-j",
        ".reloc",
        "-j",
        ".dynstr",
        "--output-target=binary",
        "combined.o",
        "combined.efi",
    });
    efi.step.dependOn(&combined.step);

    b.default_step.dependOn(&efi.step);
}

fn bootName(b: *Builder, board: dcommon.Board, target: std.zig.CrossTarget) []const u8 {
    return b.fmt("BOOT{s}.{s}", .{ dbuild.efiTagFor(target.cpu_arch.?), @tagName(board) });
}
