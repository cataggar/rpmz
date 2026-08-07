const std = @import("std");
const transaction_plan = @import("tdnf").transaction_plan;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const plan = try transaction_plan.Plan.create(allocator, .{
        .actions = &.{},
        .environment = .{
            .architecture = "x86_64",
            .distro = "external-consumer",
            .policy = .{
                .allow_erasing = false,
                .allow_multilib = true,
                .all_deps = false,
                .best = true,
                .clean_requirements_on_remove = false,
                .excludes = &.{},
                .force_architecture = null,
                .include_installed = true,
                .installonly_limit = 3,
                .installonly_names = &.{},
                .install_weak_dependencies = true,
                .keep_orphans = false,
                .locked_names = &.{},
                .min_versions = &.{},
                .protected_names = &.{},
                .skip_broken = false,
            },
            .releasever = "1",
            .resolution_status = .resolved,
            .rpmdb = .{
                .backend = .sqlite,
                .cookie_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
                .package_set_sha256 = "0000000000000000000000000000000000000000000000000000000000000000",
            },
        },
        .hidden_packages = &.{},
        .jobs = &.{},
        .packages = &.{},
        .problems = &.{},
        .repositories = &.{},
        .requests = &.{},
        .selected = &.{},
        .skipped = &.{},
    });
    defer plan.destroy();

    const digest = try plan.digest(allocator);
    if (digest.len != 64) return error.InvalidDigest;

    const canonical_json = try plan.canonicalJsonAlloc(allocator);
    defer allocator.free(canonical_json);
    const schema_field =
        "\"schema\":\"" ++ transaction_plan.schema ++ "\"";
    if (std.mem.indexOf(u8, canonical_json, schema_field) == null) {
        return error.MissingCanonicalSchema;
    }
}
