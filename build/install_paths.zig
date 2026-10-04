const std = @import("std");

pub const prefix_marker = "@RPMZ_INSTALL_PREFIX@";
pub const prefix_path: std.Build.LazyPath = .{ .relative = .{ .base = .install_prefix } };

pub fn rootPath(b: *std.Build) []const u8 {
    return b.root.root_dir.handle.realPathFileAlloc(
        b.graph.io,
        if (b.root.sub_path.len == 0) "." else b.root.sub_path,
        b.allocator,
    ) catch @panic("unable to resolve package root");
}

pub fn runner(b: *std.Build) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "rpmz-prefix-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/prefix_runner.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
}

pub fn path(b: *std.Build, directory: std.Build.InstallDir, sub_path: []const u8) []const u8 {
    return b.pathJoin(&.{
        prefix_marker,
        switch (directory) {
            .prefix => "",
            .bin => "bin",
            .lib => "lib",
            .header => "include",
            .custom => |relative| relative,
        },
        sub_path,
    });
}

pub fn options(b: *std.Build, helper: *std.Build.Step.Compile, input: std.Build.LazyPath) *std.Build.Module {
    const run = b.addRunArtifact(helper);
    run.addDirectoryArg2(prefix_path, .{ .make_absolute = true });
    run.addArg("options");
    run.addFileArg(input);
    const output = run.addOutputFileArg("client_config_options.zig");
    return b.createModule(.{ .root_source_file = output });
}

pub fn wire(b: *std.Build, helper: *std.Build.Step.Compile) void {
    var seen: std.AutoHashMap(*std.Build.Step, void) = .init(b.allocator);
    for (b.top_level_steps.values()) |top| visit(b, helper, &top.step, &seen);
}

fn visit(b: *std.Build, helper: *std.Build.Step.Compile, step: *std.Build.Step, seen: *std.AutoHashMap(*std.Build.Step, void)) void {
    const entry = seen.getOrPut(step) catch @panic("OOM");
    if (entry.found_existing) return;
    const dependencies = b.allocator.dupe(*std.Build.Step, step.dependencies.items) catch @panic("OOM");
    for (dependencies) |dependency| visit(b, helper, dependency, seen);
    const run = step.cast(std.Build.Step.Run) orelse return;
    var needs_prefix = false;
    for (run.argv.items) |arg| {
        if (arg == .bytes and std.mem.indexOf(u8, arg.bytes, prefix_marker) != null)
            needs_prefix = true;
    }
    if (run.environ_map) |environ| {
        var it = environ.iterator();
        while (it.next()) |item| {
            if (std.mem.indexOf(u8, item.value_ptr.*, prefix_marker) != null)
                needs_prefix = true;
        }
    }
    if (!needs_prefix) return;
    const argv = run.argv.toOwnedSlice(b.allocator) catch @panic("OOM");
    run.addArtifactArg(helper);
    run.addDirectoryArg2(prefix_path, .{ .make_absolute = true });
    run.addArg("exec");
    run.argv.appendSlice(b.allocator, argv) catch @panic("OOM");
}
