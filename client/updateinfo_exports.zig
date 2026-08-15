// Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
//
// Licensed under the GNU Lesser General Public License v2.1 (the "License");
// you may not use this file except in compliance with the License. The terms
// of the License are located in the COPYING file of this distribution.

const updateinfo = @import("updateinfo.zig");
pub const c = updateinfo.c;

extern fn TDNFRefresh(?*c.RPMZ) callconv(.c) u32;
extern fn TDNFAllocateMemory(
    usize,
    usize,
    *?*anyopaque,
) callconv(.c) u32;
extern fn TDNFAllocateString(
    ?[*:0]const u8,
    [*c][*c]u8,
) callconv(.c) u32;
extern fn TDNFFreeMemory(?*anyopaque) callconv(.c) void;
extern fn TDNFFreeStringArray([*c][*c]u8) callconv(.c) void;
extern fn TDNFNativeQueryBuildRepoInputs(
    ?*c.RPMZ,
    *c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    *u32,
) callconv(.c) u32;
extern fn TDNFNativeQueryFreeRepoInputs(
    c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    u32,
) callconv(.c) void;
extern fn TDNFRepoMdNativeUpdateInfoSummaryLinesConfig(
    c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    u32,
    ?*const c.rpmz_rpm_config,
    [*c][*c]u8,
    u32,
    ?[*:0]const u8,
    *[*c][*c]u8,
    *u32,
) callconv(.c) u32;
extern fn TDNFNativeQueryBuildUpdateInfoSummary(
    [*c][*c]u8,
    u32,
    *c.PTDNF_UPDATEINFO_SUMMARY,
) callconv(.c) u32;
extern fn TDNFFreeUpdateInfoSummary(
    c.PTDNF_UPDATEINFO_SUMMARY,
) callconv(.c) void;
extern fn TDNFUpdateInfo(
    ?*c.RPMZ,
    [*c][*c]u8,
    *c.PTDNF_UPDATEINFO,
) callconv(.c) u32;
extern fn TDNFFreeUpdateInfo(c.PTDNF_UPDATEINFO) callconv(.c) void;

fn refresh(_: ?*anyopaque, handle: ?*c.RPMZ) u32 {
    return TDNFRefresh(handle);
}

fn allocateMemory(
    _: ?*anyopaque,
    count: usize,
    size: usize,
    output: *?*anyopaque,
) u32 {
    return TDNFAllocateMemory(count, size, output);
}

fn allocateString(
    _: ?*anyopaque,
    source: ?[*:0]const u8,
    output: [*c][*c]u8,
) u32 {
    return TDNFAllocateString(source, output);
}

fn freeMemory(_: ?*anyopaque, memory: ?*anyopaque) void {
    TDNFFreeMemory(memory);
}

fn freeStringArray(_: ?*anyopaque, values: [*c][*c]u8) void {
    TDNFFreeStringArray(values);
}

fn buildRepoInputs(
    _: ?*anyopaque,
    handle: ?*c.RPMZ,
    repos_out: *c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    count_out: *u32,
) u32 {
    return TDNFNativeQueryBuildRepoInputs(handle, repos_out, count_out);
}

fn freeRepoInputs(
    _: ?*anyopaque,
    repos: c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    count: u32,
) void {
    TDNFNativeQueryFreeRepoInputs(repos, count);
}

fn querySummary(
    _: ?*anyopaque,
    repos: c.PTDNF_REPOMD_NATIVE_REPO_INPUT,
    repo_count: u32,
    config: ?*const c.rpmz_rpm_config,
    package_specs: [*c][*c]u8,
    security: u32,
    severity: ?[*:0]const u8,
    lines_out: *[*c][*c]u8,
    count_out: *u32,
) u32 {
    return TDNFRepoMdNativeUpdateInfoSummaryLinesConfig(
        repos,
        repo_count,
        config,
        package_specs,
        security,
        severity,
        lines_out,
        count_out,
    );
}

fn buildSummary(
    _: ?*anyopaque,
    lines: [*c][*c]u8,
    count: u32,
    summary_out: *c.PTDNF_UPDATEINFO_SUMMARY,
) u32 {
    return TDNFNativeQueryBuildUpdateInfoSummary(lines, count, summary_out);
}

fn freeSummary(
    _: ?*anyopaque,
    summary: c.PTDNF_UPDATEINFO_SUMMARY,
) void {
    TDNFFreeUpdateInfoSummary(summary);
}

fn getUpdateInfo(
    _: ?*anyopaque,
    handle: ?*c.RPMZ,
    package_specs: [*c][*c]u8,
    info_out: *c.PTDNF_UPDATEINFO,
) u32 {
    return TDNFUpdateInfo(handle, package_specs, info_out);
}

fn freeUpdateInfo(_: ?*anyopaque, info: c.PTDNF_UPDATEINFO) void {
    TDNFFreeUpdateInfo(info);
}

const production_ops = updateinfo.Ops{
    .refresh = refresh,
    .allocateMemory = allocateMemory,
    .allocateString = allocateString,
    .freeMemory = freeMemory,
    .freeStringArray = freeStringArray,
    .buildRepoInputs = buildRepoInputs,
    .freeRepoInputs = freeRepoInputs,
    .querySummary = querySummary,
    .buildSummary = buildSummary,
    .freeSummary = freeSummary,
    .updateInfo = getUpdateInfo,
    .freeUpdateInfo = freeUpdateInfo,
};

pub export fn TDNFUpdateInfoSummary(
    handle: ?*c.RPMZ,
    package_specs: [*c][*c]u8,
    summary_out: [*c]c.PTDNF_UPDATEINFO_SUMMARY,
) callconv(.c) u32 {
    return updateinfo.updateInfoSummaryWithOps(
        handle,
        package_specs,
        summary_out,
        production_ops,
    );
}

pub export fn TDNFGetSecuritySeverityOption(
    handle: ?*c.RPMZ,
    security_out: [*c]u32,
    severity_out: [*c][*c]u8,
) callconv(.c) u32 {
    return updateinfo.securitySeverityOptionWithOps(
        handle,
        security_out,
        severity_out,
        production_ops,
    );
}

pub export fn TDNFGetUpdatePkgs(
    handle: ?*c.RPMZ,
    packages_out: [*c][*c][*c]u8,
    count_out: [*c]u32,
) callconv(.c) u32 {
    return updateinfo.getUpdatePkgsWithOps(
        handle,
        packages_out,
        count_out,
        production_ops,
    );
}

pub export fn TDNFGetRebootRequiredOption(
    handle: ?*c.RPMZ,
    reboot_out: [*c]u32,
) callconv(.c) u32 {
    return updateinfo.rebootRequiredOption(handle, reboot_out);
}
