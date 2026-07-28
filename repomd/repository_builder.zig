//! Concatenates individually built packages into one repository model.
//!
//! `rpmpkg.BuiltPackage` owns private relation, file and changelog slices, and
//! every `model.Package` addresses them through ranges. Merging several built
//! packages into a single `model.RepositoryModel` therefore has to rebase each
//! range onto the combined arrays. Both the installed repository (built from
//! rpmdb headers) and the command-line repository (built from `.rpm` files)
//! need exactly that.

const std = @import("std");

const model = @import("model.zig");
const rpmpkg = @import("rpmpkg.zig");

pub const RepositoryBuilder = struct {
    allocator: std.mem.Allocator,
    packages: std.array_list.Managed(model.Package),
    relations: std.array_list.Managed(model.Relation),
    files: std.array_list.Managed(model.FileEntry),
    changelogs: std.array_list.Managed(model.ChangelogEntry),

    pub fn init(allocator: std.mem.Allocator) RepositoryBuilder {
        return .{
            .allocator = allocator,
            .packages = std.array_list.Managed(model.Package).init(allocator),
            .relations = std.array_list.Managed(model.Relation).init(allocator),
            .files = std.array_list.Managed(model.FileEntry).init(allocator),
            .changelogs = std.array_list.Managed(model.ChangelogEntry).init(
                allocator,
            ),
        };
    }

    pub fn deinit(self: *RepositoryBuilder) void {
        self.packages.deinit();
        self.relations.deinit();
        self.files.deinit();
        self.changelogs.deinit();
    }

    pub fn appendBuiltPackage(
        self: *RepositoryBuilder,
        built: rpmpkg.BuiltPackage,
    ) std.mem.Allocator.Error!void {
        var pkg = built.package;
        const relation_base = self.relations.items.len;
        const file_base = self.files.items.len;
        const changelog_base = self.changelogs.items.len;

        try self.relations.appendSlice(built.relations);
        try self.files.appendSlice(built.files);
        try self.changelogs.appendSlice(built.changelogs);

        inline for (std.enums.values(model.DependencyKind)) |kind| {
            pkg.rangePtr(kind).start += relation_base;
        }
        pkg.files.start += file_base;
        pkg.changelogs.start += changelog_base;
        try self.packages.append(pkg);
    }

    pub fn finish(
        self: *RepositoryBuilder,
    ) std.mem.Allocator.Error!model.RepositoryModel {
        return .{
            .packages = try self.packages.toOwnedSlice(),
            .relations = try self.relations.toOwnedSlice(),
            .files = try self.files.toOwnedSlice(),
            .changelogs = try self.changelogs.toOwnedSlice(),
        };
    }
};
