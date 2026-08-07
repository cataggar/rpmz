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
    const run_consumer = b.addRunArtifact(consumer);
    b.step("check", "Build and run the public Zig API consumer")
        .dependOn(&run_consumer.step);
}
