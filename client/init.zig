// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const common = @import("rpmz_common");
const abi = @import("transaction_plan_capture_abi");
const errors = @import("rpmz_error");
const c = @import("client_init_abi").C;

extern fn TDNFFreeMemory(?*anyopaque) callconv(.c) void;
extern fn TDNFUtilsMakeDirs(?[*:0]const u8) callconv(.c) u32;
extern fn TDNFGetCachePath(
    ?*anyopaque,
    ?*anyopaque,
    ?[*:0]const u8,
    ?[*:0]const u8,
    ?*?[*:0]u8,
) callconv(.c) u32;
extern fn TDNFGetRepoMD(
    ?*anyopaque,
    ?*anyopaque,
    ?[*:0]const u8,
    ?*?*anyopaque,
) callconv(.c) u32;
extern fn TDNFFreeRepoMetadata(?*anyopaque) callconv(.c) void;
extern fn TDNFRepoMdCalculateCookieForFile(
    ?[*:0]const u8,
    ?[*]u8,
) callconv(.c) u32;
extern fn TDNFPackageContextRootDir(
    ?*const c.TDNF_PACKAGE_CONTEXT,
) callconv(.c) ?[*:0]const u8;

const repository_init_callbacks = abi.RepositoryInitCallbacks{
    .free_memory = &TDNFFreeMemory,
    .make_dirs = &TDNFUtilsMakeDirs,
    .get_cache_path = &TDNFGetCachePath,
    .get_repo_md = &TDNFGetRepoMD,
    .free_repo_metadata = &TDNFFreeRepoMetadata,
    .calculate_cookie = &TDNFRepoMdCalculateCookieForFile,
};

fn describeRepository(
    raw_data: ?*anyopaque,
    raw_view: ?*abi.RepositoryRefreshView,
) callconv(.c) void {
    const repository: *c.TDNF_REPO_DATA = @ptrCast(@alignCast(
        raw_data orelse return,
    ));
    const view = raw_view orelse return;

    @memset(@as([*]u8, @ptrCast(view))[0..@sizeOf(abi.RepositoryRefreshView)], 0);
    view.next = @ptrCast(repository.pNext);
    view.live_repository = @ptrCast(repository.pRepo);
    view.live_repository_slot = @ptrCast(&repository.pRepo);
    view.id = repository.pszId;
    view.name = repository.pszName;
    view.base_url = if (repository.ppszBaseUrls != null)
        repository.ppszBaseUrls[0]
    else
        null;
    view.metadata_expire = repository.lMetadataExpire;
    view.priority = repository.nPriority;
    view.enabled = repository.nEnabled;
    view.skip_if_unavailable = repository.nSkipIfUnavailable;
    view.has_metadata = repository.nHasMetaData;
}

fn setRepositoryEnabled(
    raw_data: ?*anyopaque,
    enabled: c_int,
) callconv(.c) void {
    const repository: *c.TDNF_REPO_DATA = @ptrCast(@alignCast(
        raw_data orelse return,
    ));
    if (repository.nEnabled != 0 and enabled == 0) {
        common.log(0, "Disabling Repo: '%s'\n", .{repository.pszName});
    }
    repository.nEnabled = enabled;
}

fn buildRefreshInput(
    raw_handle: ?*c.RPMZ,
    sack: ?*c.TDNF_PACKAGE_CONTEXT,
    raw_input: ?*abi.RepositoryRefreshInput,
) callconv(.c) u32 {
    const handle = raw_handle orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    const input = raw_input orelse
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    if (handle.pSack == null or handle.pArgs == null or handle.pConf == null) {
        return errors.ERROR_TDNF_INVALID_PARAMETER;
    }

    @memset(@as([*]u8, @ptrCast(input))[0..@sizeOf(abi.RepositoryRefreshInput)], 0);
    input.rpmz_handle = @ptrCast(handle);
    input.sack = @ptrCast(sack);
    input.live_sack = @ptrCast(handle.pSack);
    input.repository_head = @ptrCast(handle.pRepos);
    input.command_line_repository_slot = @ptrCast(&handle.pCmdLineRepo);
    input.state_slot = @ptrCast(&handle.pTransactionPlanState);
    input.failure_stage = &handle.nTestReloadFailureStage;
    input.refresh_flag = &handle.pArgs[0].nRefresh;
    input.cache_dir = handle.pConf[0].pszCacheDir;
    input.root_dir = TDNFPackageContextRootDir(@ptrCast(handle.pSack));
    input.architecture = handle.pArgs[0].pszArch;
    input.rpm_config = @ptrCast(handle.pRpmConfig);
    input.cache_only = handle.pArgs[0].nCacheOnly;
    input.all_deps = handle.pArgs[0].nAllDeps;
    input.repository_init_callbacks = &repository_init_callbacks;
    input.describe_repository = &describeRepository;
    input.set_repository_enabled = &setRepositoryEnabled;
    return 0;
}

comptime {
    @export(&buildRefreshInput, .{
        .name = "TDNFBuildRefreshInput",
        .visibility = .hidden,
    });
}
