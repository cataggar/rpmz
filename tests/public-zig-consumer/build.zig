const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tdnf_dep = b.dependency("tdnf", .{
        .target = target,
        .optimize = optimize,
    });
    const consumer_mod = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    consumer_mod.addImport("tdnf", tdnf_dep.module("tdnf"));

    const consumer = b.addExecutable(.{
        .name = "tdnf-public-zig-consumer",
        .root_module = consumer_mod,
    });
    const replay_export_mod = b.createModule(.{
        .root_source_file = b.path("replay_export.zig"),
        .target = target,
        .optimize = optimize,
    });
    replay_export_mod.addImport("tdnf", tdnf_dep.module("tdnf"));
    const replay_export = b.addExecutable(.{
        .name = "tdnf-replay-export",
        .root_module = replay_export_mod,
    });
    const install_replay_export = b.addInstallArtifact(
        replay_export,
        .{},
    );
    b.step(
        "replay-export",
        "Build the acceptance-only replay export consumer",
    ).dependOn(&install_replay_export.step);
    const run_consumer = b.addRunArtifact(consumer);
    // The consumer writes its fixture relative to cwd, so give it a private
    // directory inside the build cache rather than the audit tree.
    run_consumer.setCwd(b.path("."));
    const check = b.step("check", "Build and run the public Zig API consumer");
    check.dependOn(&run_consumer.step);
    check.dependOn(&replay_export.step);
}
