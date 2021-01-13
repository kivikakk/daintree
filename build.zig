const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .uefi,
        .abi = .msvc,
    };

    const exe = b.addExecutable("BOOTAA64", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setOutputDir("disk/EFI/BOOT");
    exe.install();

    b.default_step.dependOn(&exe.step);
}
