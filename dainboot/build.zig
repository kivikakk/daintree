const std = @import("std");
const CrossTarget = std.zig.CrossTarget;
const Builder = std.build.Builder;

const version = @import("version.zig").version;

pub fn build(b: *Builder) !void {
    const target = CrossTarget{
        .cpu_arch = .aarch64,
        .os_tag = .uefi,
        .abi = .msvc,
    };

    const exe = b.addExecutable("BOOTAA64", "src/dainboot.zig");
    exe.setTarget(target);
    exe.setBuildMode(b.standardReleaseOptions());
    exe.setOutputDir("disk/EFI/BOOT");
    exe.addBuildOption([:0]const u8, "version", try b.allocator.dupeZ(u8, try version(b)));
    exe.install();

    b.default_step.dependOn(&exe.step);
}
