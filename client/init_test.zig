// Copyright (C) 2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const std = @import("std");
const abi = @import("transaction_plan_capture_abi");
const c = @import("client_init_abi").C;

comptime {
    _ = @import("client_root");
}

const invalid_parameter: u32 = 1622;
const stdout_fileno: c_int = 1;

extern fn pipe([*]c_int) c_int;
extern fn dup(c_int) c_int;
extern fn dup2(c_int, c_int) c_int;
extern fn close(c_int) c_int;
extern fn read(c_int, ?*anyopaque, usize) isize;
extern fn TDNFBuildRefreshInput(
    ?*c.RPMZ,
    ?*c.TDNF_PACKAGE_CONTEXT,
    ?*abi.RepositoryRefreshInput,
) u32;
extern fn TDNFPackageContextCreate(
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*const c.rpmz_rpm_config,
    c_int,
    ?*?*c.TDNF_PACKAGE_CONTEXT,
) u32;
extern fn TDNFPackageContextFree(?*c.TDNF_PACKAGE_CONTEXT) void;
extern fn TDNFFreeMemory(?*anyopaque) void;
extern fn TDNFUtilsMakeDirs(?[*:0]const u8) u32;
extern fn TDNFGetCachePath(
    ?*anyopaque,
    ?*anyopaque,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*?[*:0]u8,
) u32;
extern fn TDNFGetRepoMD(
    ?*anyopaque,
    ?*anyopaque,
    ?[*:0]const u8,
    ?*?*anyopaque,
) u32;
extern fn TDNFFreeRepoMetadata(?*anyopaque) void;
extern fn TDNFRepoMdCalculateCookieForFile(
    ?[*:0]const u8,
    ?[*]u8,
) u32;

const Fixture = struct {
    args: c.TDNF_CMD_ARGS = std.mem.zeroes(c.TDNF_CMD_ARGS),
    conf: c.TDNF_CONF = std.mem.zeroes(c.TDNF_CONF),
    handle: c.RPMZ = std.mem.zeroes(c.RPMZ),
    context: ?*c.TDNF_PACKAGE_CONTEXT = null,

    fn init(self: *Fixture) !void {
        try std.testing.expectEqual(
            @as(u32, 0),
            TDNFPackageContextCreate(
                "/cache",
                "/install-root",
                "fixture-arch",
                null,
                0,
                &self.context,
            ),
        );
        self.handle.pSack = self.context;
        self.handle.pArgs = &self.args;
        self.handle.pConf = &self.conf;
    }

    fn deinit(self: *Fixture) void {
        TDNFPackageContextFree(self.context);
    }
};

fn pointerAddress(pointer: anytype) usize {
    return @intFromPtr(pointer);
}

fn expectSameBytes(expected: anytype, actual: @TypeOf(expected)) !void {
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(expected),
        std.mem.asBytes(actual),
    );
}

test "build refresh input rejects invalid handle combinations without clearing output" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();

    var input: abi.RepositoryRefreshInput = undefined;
    @memset(std.mem.asBytes(&input), 0xa5);
    const stale = input;

    try std.testing.expectEqual(
        invalid_parameter,
        TDNFBuildRefreshInput(null, null, &input),
    );
    try expectSameBytes(&stale, &input);
    try std.testing.expectEqual(
        invalid_parameter,
        TDNFBuildRefreshInput(&fixture.handle, null, null),
    );

    const live_sack = fixture.handle.pSack;
    fixture.handle.pSack = null;
    try std.testing.expectEqual(
        invalid_parameter,
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    try expectSameBytes(&stale, &input);
    fixture.handle.pSack = live_sack;

    const args = fixture.handle.pArgs;
    fixture.handle.pArgs = null;
    try std.testing.expectEqual(
        invalid_parameter,
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    try expectSameBytes(&stale, &input);
    fixture.handle.pArgs = args;

    const conf = fixture.handle.pConf;
    fixture.handle.pConf = null;
    try std.testing.expectEqual(
        invalid_parameter,
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    try expectSameBytes(&stale, &input);
    fixture.handle.pConf = conf;
}

test "build refresh input wires every field and live pointer slot" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();

    var first_repo = std.mem.zeroes(c.TDNF_REPO_DATA);
    var live_repository_storage: usize = 0;
    var command_line_repository_storage: usize = 0;
    var state_storage: usize = 0;
    const live_repository: *c.Repo = @ptrCast(&live_repository_storage);
    const command_line_repository: *c.Repo = @ptrCast(&command_line_repository_storage);
    const state: *c.TDNF_TRANSACTION_PLAN_STATE = @ptrCast(&state_storage);
    const scratch: *c.TDNF_PACKAGE_CONTEXT = @ptrFromInt(0x1000);
    const rpm_config: *c.rpmz_rpm_config = @ptrFromInt(0x2000);

    fixture.args.nRefresh = 7;
    fixture.args.nCacheOnly = -3;
    fixture.args.nAllDeps = 11;
    fixture.args.pszArch = @constCast("requested-arch");
    fixture.conf.pszCacheDir = @constCast("/configured-cache");
    fixture.handle.pRpmConfig = rpm_config;
    fixture.handle.pRepos = &first_repo;
    fixture.handle.pCmdLineRepo = command_line_repository;
    fixture.handle.pTransactionPlanState = state;
    fixture.handle.nTestReloadFailureStage = 6;
    first_repo.pRepo = live_repository;

    var input: abi.RepositoryRefreshInput = undefined;
    @memset(std.mem.asBytes(&input), 0xa5);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, scratch, &input),
    );

    try std.testing.expectEqual(pointerAddress(&fixture.handle), pointerAddress(input.rpmz_handle.?));
    try std.testing.expectEqual(pointerAddress(scratch), pointerAddress(input.sack.?));
    try std.testing.expectEqual(pointerAddress(fixture.context.?), pointerAddress(input.live_sack.?));
    try std.testing.expectEqual(pointerAddress(&first_repo), pointerAddress(input.repository_head.?));
    try std.testing.expectEqual(pointerAddress(&fixture.handle.pCmdLineRepo), pointerAddress(input.command_line_repository_slot.?));
    try std.testing.expectEqual(pointerAddress(&fixture.handle.pTransactionPlanState), pointerAddress(input.state_slot.?));
    try std.testing.expectEqual(pointerAddress(&fixture.handle.nTestReloadFailureStage), pointerAddress(input.failure_stage.?));
    try std.testing.expectEqual(pointerAddress(&fixture.args.nRefresh), pointerAddress(input.refresh_flag.?));
    try std.testing.expectEqualStrings("/configured-cache", std.mem.span(input.cache_dir.?));
    try std.testing.expectEqualStrings("/install-root", std.mem.span(input.root_dir.?));
    try std.testing.expectEqualStrings("requested-arch", std.mem.span(input.architecture.?));
    try std.testing.expectEqual(pointerAddress(rpm_config), pointerAddress(input.rpm_config.?));
    try std.testing.expectEqual(@as(c_int, -3), input.cache_only);
    try std.testing.expectEqual(@as(c_int, 11), input.all_deps);
    try std.testing.expect(input.repository_init_callbacks != null);
    try std.testing.expect(input.describe_repository != null);
    try std.testing.expect(input.set_repository_enabled != null);

    input.command_line_repository_slot.?.* = null;
    try std.testing.expect(fixture.handle.pCmdLineRepo == null);
    input.state_slot.?.* = null;
    try std.testing.expect(fixture.handle.pTransactionPlanState == null);
    input.failure_stage.?.* = 4;
    try std.testing.expectEqual(@as(u32, 4), fixture.handle.nTestReloadFailureStage);
    input.refresh_flag.?.* = 9;
    try std.testing.expectEqual(@as(c_int, 9), fixture.args.nRefresh);
}

test "build refresh input accepts optional null values and clears stale fields" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();

    fixture.args.pszArch = null;
    fixture.conf.pszCacheDir = null;
    fixture.handle.pRpmConfig = null;
    fixture.handle.pRepos = null;

    var input: abi.RepositoryRefreshInput = undefined;
    @memset(std.mem.asBytes(&input), 0xa5);
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    try std.testing.expect(input.sack == null);
    try std.testing.expect(input.repository_head == null);
    try std.testing.expect(input.cache_dir == null);
    try std.testing.expect(input.architecture == null);
    try std.testing.expect(input.rpm_config == null);
    var expected = std.mem.zeroes(abi.RepositoryRefreshInput);
    expected.rpmz_handle = @ptrCast(&fixture.handle);
    expected.live_sack = @ptrCast(fixture.context);
    expected.command_line_repository_slot = @ptrCast(&fixture.handle.pCmdLineRepo);
    expected.state_slot = @ptrCast(&fixture.handle.pTransactionPlanState);
    expected.failure_stage = &fixture.handle.nTestReloadFailureStage;
    expected.refresh_flag = &fixture.args.nRefresh;
    expected.root_dir = input.root_dir;
    expected.repository_init_callbacks = input.repository_init_callbacks;
    expected.describe_repository = input.describe_repository;
    expected.set_repository_enabled = input.set_repository_enabled;
    try expectSameBytes(&expected, &input);
}

test "repository init callback table uses production functions" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();
    var input = abi.RepositoryRefreshInput{};
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    const callbacks = input.repository_init_callbacks.?;
    var second = abi.RepositoryRefreshInput{};
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, null, &second),
    );
    try std.testing.expectEqual(
        pointerAddress(callbacks),
        pointerAddress(second.repository_init_callbacks.?),
    );

    try std.testing.expectEqual(pointerAddress(&TDNFFreeMemory), pointerAddress(callbacks.free_memory.?));
    try std.testing.expectEqual(pointerAddress(&TDNFUtilsMakeDirs), pointerAddress(callbacks.make_dirs.?));
    try std.testing.expectEqual(pointerAddress(&TDNFGetCachePath), pointerAddress(callbacks.get_cache_path.?));
    try std.testing.expectEqual(pointerAddress(&TDNFGetRepoMD), pointerAddress(callbacks.get_repo_md.?));
    try std.testing.expectEqual(pointerAddress(&TDNFFreeRepoMetadata), pointerAddress(callbacks.free_repo_metadata.?));
    try std.testing.expectEqual(pointerAddress(&TDNFRepoMdCalculateCookieForFile), pointerAddress(callbacks.calculate_cookie.?));
}

test "describe repository handles null callbacks and exposes live traversal slots" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();
    var input = abi.RepositoryRefreshInput{};
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    const describe = input.describe_repository.?;

    var stale: abi.RepositoryRefreshView = undefined;
    @memset(std.mem.asBytes(&stale), 0x5a);
    const unchanged = stale;
    describe(null, &stale);
    try expectSameBytes(&unchanged, &stale);

    var repository = std.mem.zeroes(c.TDNF_REPO_DATA);
    repository.nEnabled = 1;
    describe(@ptrCast(&repository), null);

    var next = std.mem.zeroes(c.TDNF_REPO_DATA);
    var live_storage: usize = 0;
    var replacement_storage: usize = 0;
    const live: *c.Repo = @ptrCast(&live_storage);
    const replacement: *c.Repo = @ptrCast(&replacement_storage);
    var urls = [_]?[*:0]u8{ @constCast("https://example.test/repo"), null };
    repository.pNext = &next;
    repository.pRepo = live;
    repository.pszId = @constCast("repo-id");
    repository.pszName = @constCast("repo name");
    repository.ppszBaseUrls = @ptrCast(&urls);
    repository.lMetadataExpire = 1234;
    repository.nPriority = -7;
    repository.nEnabled = 2;
    repository.nSkipIfUnavailable = 3;
    repository.nHasMetaData = 4;

    var view: abi.RepositoryRefreshView = undefined;
    @memset(std.mem.asBytes(&view), 0xa5);
    describe(@ptrCast(&repository), &view);
    try std.testing.expectEqual(pointerAddress(&next), pointerAddress(view.next.?));
    try std.testing.expectEqual(pointerAddress(live), pointerAddress(view.live_repository.?));
    try std.testing.expectEqual(pointerAddress(&repository.pRepo), pointerAddress(view.live_repository_slot.?));
    try std.testing.expectEqualStrings("repo-id", std.mem.span(view.id.?));
    try std.testing.expectEqualStrings("repo name", std.mem.span(view.name.?));
    try std.testing.expectEqualStrings("https://example.test/repo", std.mem.span(view.base_url.?));
    try std.testing.expectEqual(@as(c_long, 1234), view.metadata_expire);
    try std.testing.expectEqual(@as(c_int, -7), view.priority);
    try std.testing.expectEqual(@as(c_int, 2), view.enabled);
    try std.testing.expectEqual(@as(c_int, 3), view.skip_if_unavailable);
    try std.testing.expectEqual(@as(c_int, 4), view.has_metadata);

    view.live_repository_slot.?.* = @ptrCast(replacement);
    try std.testing.expectEqual(pointerAddress(replacement), pointerAddress(repository.pRepo));

    repository = std.mem.zeroes(c.TDNF_REPO_DATA);
    @memset(std.mem.asBytes(&view), 0xa5);
    describe(@ptrCast(&repository), &view);
    var expected = std.mem.zeroes(abi.RepositoryRefreshView);
    expected.live_repository_slot = @ptrCast(&repository.pRepo);
    try expectSameBytes(&expected, &view);
}

fn captureSetEnabledLog(
    callback: *const fn (?*anyopaque, c_int) callconv(.c) void,
    repository: *c.TDNF_REPO_DATA,
    enabled: c_int,
) ![]u8 {
    var descriptors: [2]c_int = undefined;
    try std.testing.expectEqual(@as(c_int, 0), pipe(&descriptors));
    defer _ = close(descriptors[0]);
    var write_open = true;
    defer {
        if (write_open) _ = close(descriptors[1]);
    }

    const saved_stdout = dup(stdout_fileno);
    try std.testing.expect(saved_stdout >= 0);
    defer _ = close(saved_stdout);
    try std.testing.expectEqual(
        stdout_fileno,
        dup2(descriptors[1], stdout_fileno),
    );
    var restored = false;
    defer {
        if (!restored) _ = dup2(saved_stdout, stdout_fileno);
    }

    callback(@ptrCast(repository), enabled);
    try std.testing.expectEqual(
        stdout_fileno,
        dup2(saved_stdout, stdout_fileno),
    );
    restored = true;
    _ = close(descriptors[1]);
    write_open = false;

    var buffer: [256]u8 = undefined;
    const length = read(descriptors[0], &buffer, buffer.len);
    try std.testing.expect(length >= 0);
    return std.testing.allocator.dupe(u8, buffer[0..@intCast(length)]);
}

test "set repository enabled handles null and logs enabled to disabled transition" {
    var fixture = Fixture{};
    try fixture.init();
    defer fixture.deinit();
    var input = abi.RepositoryRefreshInput{};
    try std.testing.expectEqual(
        @as(u32, 0),
        TDNFBuildRefreshInput(&fixture.handle, null, &input),
    );
    const set_enabled = input.set_repository_enabled.?;

    set_enabled(null, 1);
    var repository = std.mem.zeroes(c.TDNF_REPO_DATA);
    repository.pszName = @constCast("production");
    const enable_output = try captureSetEnabledLog(set_enabled, &repository, -2);
    defer std.testing.allocator.free(enable_output);
    try std.testing.expectEqual(@as(usize, 0), enable_output.len);
    try std.testing.expectEqual(@as(c_int, -2), repository.nEnabled);

    const still_enabled_output = try captureSetEnabledLog(set_enabled, &repository, 3);
    defer std.testing.allocator.free(still_enabled_output);
    try std.testing.expectEqual(@as(usize, 0), still_enabled_output.len);
    try std.testing.expectEqual(@as(c_int, 3), repository.nEnabled);

    repository.nEnabled = 1;
    const output = try captureSetEnabledLog(set_enabled, &repository, 0);
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings(
        "Disabling Repo: 'production'\n",
        output,
    );
    try std.testing.expectEqual(@as(c_int, 0), repository.nEnabled);
}
