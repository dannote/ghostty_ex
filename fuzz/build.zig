const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("fuzz_vt.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    mod.addIncludePath(b.path("../priv/include"));
    mod.addLibraryPath(b.path("../priv/lib"));
    mod.linkSystemLibrary("ghostty-vt", .{});

    if (target.result.os.tag == .macos) {
        mod.addRPath(.{ .cwd_relative = b.pathFromRoot("../priv/lib") });
    }

    const fuzz = b.addTest(.{ .root_module = mod });
    const run = b.addRunArtifact(fuzz);

    const test_step = b.step("test", "Run fuzz sanity tests");
    test_step.dependOn(&run.step);
}
