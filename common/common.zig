const std = @import("std");
const build = std.build;

const daintree_version = std.builtin.Version{ .major = 0, .minor = 0, .patch = 1 };

pub const Board = enum {
    qemu,
    rockpro64,
};

pub fn getBoard(b: *build.Builder) !Board {
    return b.option(Board, "board", "Target board.") orelse
        error.UnknownBoard;
}

// From dainboot.
pub const EntryData = packed struct {
    memory_map: [*]std.os.uefi.tables.MemoryDescriptor,
    memory_map_size: usize,
    descriptor_size: usize,
    dtb_ptr: [*]const u8,
    dtb_len: usize,
    conventional_start: usize,
    conventional_bytes: usize,
    fb: [*]u32,
    fb_horiz: u32,
    fb_vert: u32,
    uart_base: u64, // PA coming in from dainboot, translated when we pass to daintree_main.
};

comptime {
    std.testing.expectEqual(0x50, @sizeOf(EntryData));
}

pub fn addBuildOptions(b: *build.Builder, exe: *build.LibExeObjStep, board: Board) !void {
    exe.addBuildOption([:0]const u8, "version", try b.allocator.dupeZ(u8, try getVersion(b)));
    exe.addBuildOption([:0]const u8, "board", try b.allocator.dupeZ(u8, @tagName(board)));
}

// adapted from Zig's own build.zig:
// https://github.com/ziglang/zig/blob/a021c7b1b2428ecda85e79e281d43fa1c92f8c94/build.zig#L140-L188
fn getVersion(b: *build.Builder) ![]u8 {
    const version_string = b.fmt("{d}.{d}.{d}", .{ daintree_version.major, daintree_version.minor, daintree_version.patch });

    var code: u8 = undefined;
    const git_describe_untrimmed = b.execAllowFail(&[_][]const u8{
        "git", "-C", b.build_root, "describe", "--match", "*.*.*", "--tags",
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
            var it = std.mem.split(git_describe, "-");
            const tagged_ancestor = it.next() orelse unreachable;
            const commit_height = it.next() orelse unreachable;
            const commit_id = it.next() orelse unreachable;

            const ancestor_ver = try std.builtin.Version.parse(tagged_ancestor);
            if (daintree_version.order(ancestor_ver) != .gt) {
                std.debug.print("Daintree version '{}' must be greater than tagged ancestor '{}'\n", .{ daintree_version, ancestor_ver });
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
