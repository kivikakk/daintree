const std = @import("std");

const dcommon = @import("dcommon.zig");
const Arch = dcommon.Arch;
const Board = dcommon.Board;

pub fn getBoard(b: *std.Build) !Board {
    return b.option(Board, "board", "Target board.") orelse
        error.UnknownBoard;
}

pub fn getArch(board: Board) Arch {
    return switch (board) {
        .qemu_arm64, .rockpro64 => .arm64,
        .qemu_riscv64 => .riscv64,
    };
}

pub fn queryFor(board: Board) std.Target.Query {
    switch (board) {
        .qemu_arm64, .rockpro64 => {
            var features = std.Target.Cpu.Feature.Set.empty;
            // Unaligned LDR in daintree_mmu_start (before MMU bring up) is
            // causing crashes.  I wish I could turn this on just for that one
            // function.  Can't seem to find a register setting (like in SCTLR_EL1
            // or something) that stops this happening.  Reproduced on both
            // QEMU and rockpro64 so giving up for now.
            features.addFeature(@intFromEnum(std.Target.aarch64.Feature.strict_align));

            return .{
                .cpu_arch = .aarch64,
                .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_a53 },
                .cpu_features_add = features,
            };
        },
        .qemu_riscv64 => return .{
            .cpu_arch = .riscv64,
            .cpu_model = .baseline,
        },
    }
}

pub fn efiTagFor(cpu_arch: std.Target.Cpu.Arch) []const u8 {
    return switch (cpu_arch) {
        .aarch64 => "AA64",
        .riscv64 => "RISCV64",
        else => @panic("can't handle other arch in efiTagFor"),
    };
}

pub fn addBuildOptions(b: *std.Build, exe: *std.Build.Step.Compile, board: Board) !void {
    const options = b.addOptions();
    options.addOption([]const u8, "version", try b.allocator.dupe(u8, try getVersion(b)));
    options.addOption([]const u8, "board", try b.allocator.dupe(u8, @tagName(board)));
    exe.root_module.addOptions("build_options", options);
}

// adapted from Zig's own build.zig:
// https://github.com/ziglang/zig/blob/a021c7b1b2428ecda85e79e281d43fa1c92f8c94/build.zig#L140-L188
fn getVersion(b: *std.Build) ![]u8 {
    const version = dcommon.version;
    const version_string = b.fmt("{d}.{d}.{d}", .{ version.major, version.minor, version.patch });

    var code: u8 = undefined;
    const git_describe_untrimmed = b.runAllowFail(&[_][]const u8{
        "git", "-C", b.build_root.path orelse ".", "describe", "--match", "*.*.*", "--tags",
    }, &code, .Ignore) catch {
        return version_string;
    };
    const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            // Tagged release version (e.g. 0.7.0).
            if (!std.mem.eql(u8, git_describe, version_string)) {
                std.debug.print("Daintree version '{s}' does not match Git tag '{s}'\n", .{ version_string, git_describe });
                std.process.exit(1);
            }
            return version_string;
        },
        2 => {
            // Untagged development build (e.g. 0.7.0-684-gbbe2cca1a).
            var it = std.mem.split(u8, git_describe, "-");
            const tagged_ancestor = it.next() orelse unreachable;
            const commit_height = it.next() orelse unreachable;
            const commit_id = it.next() orelse unreachable;

            const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
            if (version.order(ancestor_ver) != .gt) {
                std.debug.print("Daintree version '{}' must be greater than tagged ancestor '{}'\n", .{ version, ancestor_ver });
                std.process.exit(1);
            }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                return version_string;
            }

            // The version is reformatted in accordance with the https://semver.org specification.
            return b.fmt("{s}-dev.{s}+{s}", .{ version_string, commit_height, commit_id[1..] });
        },
        else => {
            std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
            return version_string;
        },
    }
}
