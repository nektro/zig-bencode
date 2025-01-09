const std = @import("std");
const deps = @import("./deps.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.option(std.builtin.Mode, "mode", "") orelse .Debug;

    const torrent_file = b.path("archlinux-2021.04.01-x86_64.iso.torrent");

    const bencode = b.addModule("bencode", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = mode,
    });

    const exe = b.addExecutable(.{
        .name = "zig-bencode",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = mode,
    });
    exe.root_module.addImport("bencode", bencode);

    exe.root_module.addAnonymousImport("torrent_file", .{
        .root_source_file = torrent_file,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("test.zig"),
        .target = target,
        .optimize = mode,
    });
    deps.addAllTo(tests);

    const test_step = b.step("test", "Run all library tests");
    const tests_run = b.addRunArtifact(tests);
    tests_run.has_side_effects = true;
    test_step.dependOn(&tests_run.step);
}
