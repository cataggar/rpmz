//! Private cross-module ABI declarations retained while tdnf's implementation
//! is split across Zig modules. This module is not part of the public package.

const __root = @This();
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
pub extern fn __errno_location() [*c]c_int;
pub const __time_t = c_long;
pub const time_t = __time_t;
pub const struct_tm = extern struct {
    tm_sec: c_int = 0,
    tm_min: c_int = 0,
    tm_hour: c_int = 0,
    tm_mday: c_int = 0,
    tm_mon: c_int = 0,
    tm_year: c_int = 0,
    tm_wday: c_int = 0,
    tm_yday: c_int = 0,
    tm_isdst: c_int = 0,
    tm_gmtoff: c_long = 0,
    tm_zone: [*c]const u8 = null,
};
pub extern fn strftime(noalias __s: [*c]u8, __maxsize: usize, noalias __format: [*c]const u8, noalias __tp: [*c]const struct_tm) usize;
pub extern fn localtime(__timer: [*c]const time_t) [*c]struct_tm;
pub extern fn timegm(__tp: [*c]struct_tm) time_t;
pub const TDNF_RPMTRANS_FLAGS = u32;
pub const ALTER_AUTOERASE: c_int = 0;
pub const ALTER_AUTOERASEALL: c_int = 1;
pub const ALTER_DOWNGRADE: c_int = 2;
pub const ALTER_DOWNGRADEALL: c_int = 3;
pub const ALTER_ERASE: c_int = 4;
pub const ALTER_INSTALL: c_int = 5;
pub const ALTER_REINSTALL: c_int = 6;
pub const ALTER_UPGRADE: c_int = 7;
pub const ALTER_UPGRADEALL: c_int = 8;
pub const ALTER_DISTRO_SYNC: c_int = 9;
pub const ALTER_OBSOLETED: c_int = 10;
pub const TDNF_ALTERTYPE = c_uint;
pub const SCOPE_NONE: c_int = -1;
pub const SCOPE_ALL: c_int = 0;
pub const SCOPE_INSTALLED: c_int = 1;
pub const SCOPE_AVAILABLE: c_int = 2;
pub const SCOPE_EXTRAS: c_int = 3;
pub const SCOPE_OBSOLETES: c_int = 4;
pub const SCOPE_RECENT: c_int = 5;
pub const SCOPE_UPGRADES: c_int = 6;
pub const SCOPE_DOWNGRADES: c_int = 7;
pub const TDNF_SCOPE = c_int;
pub const AVAIL_AVAILABLE: c_int = 0;
pub const TDNF_AVAIL = c_uint;
pub const OUTPUT_SUMMARY: c_int = 0;
pub const OUTPUT_LIST: c_int = 1;
pub const OUTPUT_INFO: c_int = 2;
pub const TDNF_UPDATEINFO_OUTPUT = c_uint;
pub const UPDATE_UNKNOWN: c_int = 0;
pub const UPDATE_SECURITY: c_int = 1;
pub const UPDATE_BUGFIX: c_int = 2;
pub const UPDATE_ENHANCEMENT: c_int = 3;
pub const TDNF_UPDATEINFO_TYPE = c_uint;
pub const REPOLISTFILTER_ALL: c_int = 0;
pub const REPOLISTFILTER_ENABLED: c_int = 1;
pub const REPOLISTFILTER_DISABLED: c_int = 2;
pub const TDNF_REPOLISTFILTER = c_uint;
pub const SKIPPROBLEM_NONE: c_int = 0;
pub const SKIPPROBLEM_CONFLICTS: c_int = 1;
pub const SKIPPROBLEM_OBSOLETES: c_int = 2;
pub const SKIPPROBLEM_BROKEN: c_int = 8;
pub const struct__TDNF_PACKAGE_CONTEXT = opaque {};
pub const PTDNF_PACKAGE_CONTEXT = ?*struct__TDNF_PACKAGE_CONTEXT;
pub const struct_cnfnode = extern struct {
    next: [*c]struct_cnfnode = null,
    name: [*c]u8 = null,
    value: [*c]u8 = null,
    first_child: [*c]struct_cnfnode = null,
    parent: [*c]struct_cnfnode = null,
};
pub const struct__TDNF_CMD_ARGS = extern struct {
    nAllDeps: c_int = 0,
    nAllowErasing: c_int = 0,
    nAssumeNo: c_int = 0,
    nAssumeYes: c_int = 0,
    nBest: c_int = 0,
    nCacheOnly: c_int = 0,
    nDebugSolver: c_int = 0,
    nShowHelp: c_int = 0,
    nRefresh: c_int = 0,
    nRpmVerbosity: c_int = 0,
    nShowDuplicates: c_int = 0,
    nShowVersion: c_int = 0,
    nNoDeps: c_int = 0,
    nNoGPGCheck: c_int = 0,
    nNoCmdLineGPGCheck: c_int = 0,
    nSkipSignature: c_int = 0,
    nSkipDigest: c_int = 0,
    nNoOutput: c_int = 0,
    nQuiet: c_int = 0,
    nVerbose: c_int = 0,
    nIPv4: c_int = 0,
    nIPv6: c_int = 0,
    nDisableExcludes: c_int = 0,
    nDownloadOnly: c_int = 0,
    nUrlsOnly: c_int = 0,
    nNoAutoRemove: c_int = 0,
    nJsonOutput: c_int = 0,
    nTestOnly: c_int = 0,
    nSkipBroken: c_int = 0,
    nSource: c_int = 0,
    nBuildDeps: c_int = 0,
    pszArch: [*c]u8 = null,
    pszDownloadDir: [*c]u8 = null,
    pszInstallRoot: [*c]u8 = null,
    pszConfFile: [*c]u8 = null,
    pszReleaseVer: [*c]u8 = null,
    ppszCmds: [*c][*c]u8 = null,
    nCmdCount: c_int = 0,
    cn_setopts: [*c]struct_cnfnode = null,
    cn_repoopts: [*c]struct_cnfnode = null,
    nArgc: c_int = 0,
    ppszArgv: [*c][*c]u8 = null,
};
pub const PTDNF_CMD_ARGS = [*c]struct__TDNF_CMD_ARGS;
pub const struct__TDNF_CONF = extern struct {
    nGPGCheck: c_int = 0,
    nCliGPGCheck: c_int = 0,
    nSSLVerify: c_int = 0,
    nInstallOnlyLimit: c_int = 0,
    nCleanRequirementsOnRemove: c_int = 0,
    nKeepCache: c_int = 0,
    nOpenMax: c_int = 0,
    nCheckUpdateCompat: c_int = 0,
    nDistroSyncReinstallChanged: c_int = 0,
    nConnectTimeout: c_int = 0,
    rpmTransFlags: TDNF_RPMTRANS_FLAGS = 0,
    nPluginsEnabled: c_int = 0,
    nSkipDigest: c_int = 0,
    nSkipSignature: c_int = 0,
    pszRepoDir: [*c]u8 = null,
    pszCacheDir: [*c]u8 = null,
    pszPersistDir: [*c]u8 = null,
    pszProxy: [*c]u8 = null,
    pszProxyUserPass: [*c]u8 = null,
    ppszDistroVerPkgs: [*c][*c]u8 = null,
    pszBaseArch: [*c]u8 = null,
    pszVarReleaseVer: [*c]u8 = null,
    pszVarBaseArch: [*c]u8 = null,
    pszUserAgentHeader: [*c]u8 = null,
    pszOSName: [*c]u8 = null,
    pszOSVersion: [*c]u8 = null,
    ppszExcludes: [*c][*c]u8 = null,
    ppszMinVersions: [*c][*c]u8 = null,
    ppszPkgLocks: [*c][*c]u8 = null,
    ppszProtectedPkgs: [*c][*c]u8 = null,
    ppszInstallOnlyPkgs: [*c][*c]u8 = null,
    ppszVarsDirs: [*c][*c]u8 = null,
    pszPluginPath: [*c]u8 = null,
    pszPluginConfPath: [*c]u8 = null,
};
pub const PTDNF_CONF = [*c]struct__TDNF_CONF;
pub const struct_tdnf_rpm_config = opaque {};
pub const tdnf_rpm_config = struct_tdnf_rpm_config;
pub const struct_s_Repo = opaque {};
pub const Repo = struct_s_Repo;
pub const struct__TDNF_REPO_DATA = extern struct {
    nEnabled: c_int = 0,
    nSkipIfUnavailable: c_int = 0,
    nGPGCheck: c_int = 0,
    nHasMetaData: c_int = 0,
    lMetadataExpire: c_long = 0,
    pszId: [*c]u8 = null,
    pszName: [*c]u8 = null,
    ppszBaseUrls: [*c][*c]u8 = null,
    pszMetaLink: [*c]u8 = null,
    pszMirrorList: [*c]u8 = null,
    pszSnapshotUrl: [*c]u8 = null,
    pszSnapshotFile: [*c]u8 = null,
    ppszUrlGPGKeys: [*c][*c]u8 = null,
    nSSLVerify: c_int = 0,
    pszSSLCaCert: [*c]u8 = null,
    pszSSLClientCert: [*c]u8 = null,
    pszSSLClientKey: [*c]u8 = null,
    pszUser: [*c]u8 = null,
    pszPass: [*c]u8 = null,
    nPriority: c_int = 0,
    nTimeout: c_long = 0,
    nMinrate: c_long = 0,
    nThrottle: c_long = 0,
    nRetries: c_int = 0,
    nSkipMDFileLists: c_int = 0,
    nSkipMDUpdateInfo: c_int = 0,
    nSkipMDOther: c_int = 0,
    pszCacheName: [*c]u8 = null,
    pRepo: ?*Repo = null,
    pNext: [*c]struct__TDNF_REPO_DATA = null,
};
pub const PTDNF_REPO_DATA = [*c]struct__TDNF_REPO_DATA;
pub const PTDNF_REPOSITORY_CONTEXT = ?*Repo;
const enum_unnamed_2 = c_uint;
pub const struct__TDNF_PLUGIN_ = extern struct {
    pszName: [*c]u8 = null,
    nEnabled: c_int = 0,
    nKind: enum_unnamed_2 = @import("std").mem.zeroes(enum_unnamed_2),
    pHandle: ?*anyopaque = null,
    pNext: [*c]struct__TDNF_PLUGIN_ = null,
};
pub const PTDNF_PLUGIN = [*c]struct__TDNF_PLUGIN_;
pub const struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE = opaque {};
pub const TDNF_TRANSACTION_PLAN_REQUEST_TRACE = struct_TDNF_TRANSACTION_PLAN_REQUEST_TRACE;
pub const struct_TDNF_TRANSACTION_PLAN_STATE = opaque {};
pub const TDNF_TRANSACTION_PLAN_STATE = struct_TDNF_TRANSACTION_PLAN_STATE;
pub const TDNF_PKG_ID = i32;
pub const struct__TDNF_ = extern struct {
    pSack: PTDNF_PACKAGE_CONTEXT = null,
    pArgs: PTDNF_CMD_ARGS = null,
    pConf: PTDNF_CONF = null,
    pRpmConfig: ?*tdnf_rpm_config = null,
    pRepos: PTDNF_REPO_DATA = null,
    pCmdLineRepo: PTDNF_REPOSITORY_CONTEXT = null,
    pPlugins: PTDNF_PLUGIN = null,
    ppszRepoFromDirIds: [*c][*c]u8 = null,
    pRequestTrace: ?*TDNF_TRANSACTION_PLAN_REQUEST_TRACE = null,
    pTransactionPlanState: ?*TDNF_TRANSACTION_PLAN_STATE = null,
    ppszHiddenRefs: [*c][*c]u8 = null,
    dwHiddenRefCount: u32 = 0,
    pdwCmdLinePkgIds: [*c]TDNF_PKG_ID = null,
    ppszCmdLinePkgPaths: [*c][*c]u8 = null,
    dwCmdLinePkgCount: u32 = 0,
    nTestReloadFailureStage: u32 = 0,
};
pub const PTDNF = [*c]struct__TDNF_;
pub const struct__TDNF_PKG_CHANGELOG_ENTRY = extern struct {
    timeTime: time_t = 0,
    pszAuthor: [*c]u8 = null,
    pszText: [*c]u8 = null,
    pNext: [*c]struct__TDNF_PKG_CHANGELOG_ENTRY = null,
};
pub const TDNF_PKG_CHANGELOG_ENTRY = struct__TDNF_PKG_CHANGELOG_ENTRY;
pub const PTDNF_PKG_CHANGELOG_ENTRY = [*c]struct__TDNF_PKG_CHANGELOG_ENTRY;
pub const struct__TDNF_PKG_INFO = extern struct {
    dwEpoch: u32 = 0,
    dwInstallSizeBytes: u32 = 0,
    dwDownloadSizeBytes: u32 = 0,
    nChecksumType: c_int = 0,
    pszName: [*c]u8 = null,
    pszRepoName: [*c]u8 = null,
    pszVersion: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszSummary: [*c]u8 = null,
    pszURL: [*c]u8 = null,
    pszLicense: [*c]u8 = null,
    pszDescription: [*c]u8 = null,
    pszFormattedSize: [*c]u8 = null,
    pszFormattedDownloadSize: [*c]u8 = null,
    pszRelease: [*c]u8 = null,
    pszLocation: [*c]u8 = null,
    pppszDependencies: [*c][*c][*c]u8 = null,
    ppszFileList: [*c][*c]u8 = null,
    pszSourcePkg: [*c]u8 = null,
    pbChecksum: [*c]u8 = null,
    pChangeLogEntries: PTDNF_PKG_CHANGELOG_ENTRY = null,
    pNext: [*c]struct__TDNF_PKG_INFO = null,
};
pub const TDNF_PKG_INFO = struct__TDNF_PKG_INFO;
pub const PTDNF_PKG_INFO = [*c]struct__TDNF_PKG_INFO;
pub const struct__TDNF_SOLVED_PKG_INFO = extern struct {
    nNeedAction: c_int = 0,
    nNeedDownload: c_int = 0,
    nAlterType: TDNF_ALTERTYPE = @import("std").mem.zeroes(TDNF_ALTERTYPE),
    pPkgsNotAvailable: PTDNF_PKG_INFO = null,
    pPkgsExisting: PTDNF_PKG_INFO = null,
    pPkgsToInstall: PTDNF_PKG_INFO = null,
    pPkgsToDowngrade: PTDNF_PKG_INFO = null,
    pPkgsToUpgrade: PTDNF_PKG_INFO = null,
    pPkgsToRemove: PTDNF_PKG_INFO = null,
    pPkgsUnNeeded: PTDNF_PKG_INFO = null,
    pPkgsToReinstall: PTDNF_PKG_INFO = null,
    pPkgsObsoleted: PTDNF_PKG_INFO = null,
    pPkgsRemovedByDowngrade: PTDNF_PKG_INFO = null,
    ppszPkgsNotResolved: [*c][*c]u8 = null,
    ppszPkgsUserInstall: [*c][*c]u8 = null,
};
pub const TDNF_SOLVED_PKG_INFO = struct__TDNF_SOLVED_PKG_INFO;
pub const PTDNF_SOLVED_PKG_INFO = [*c]struct__TDNF_SOLVED_PKG_INFO;
pub const struct__TDNF_CMD_OPT = extern struct {
    pszOptName: [*c]u8 = null,
    pszOptValue: [*c]u8 = null,
    pNext: [*c]struct__TDNF_CMD_OPT = null,
};
pub const PTDNF_CMD_OPT = [*c]struct__TDNF_CMD_OPT;
pub const TDNF_CMD_ARGS = struct__TDNF_CMD_ARGS;
pub const TDNF_CONF = struct__TDNF_CONF;
pub const TDNF_REPO_DATA = struct__TDNF_REPO_DATA;
pub const struct__TDNF_UPDATEINFO_REF = extern struct {
    pszID: [*c]u8 = null,
    pszLink: [*c]u8 = null,
    pszTitle: [*c]u8 = null,
    pszType: [*c]u8 = null,
    pNext: [*c]struct__TDNF_UPDATEINFO_REF = null,
};
pub const PTDNF_UPDATEINFO_REF = [*c]struct__TDNF_UPDATEINFO_REF;
pub const struct__TDNF_UPDATEINFO_PKG = extern struct {
    pszName: [*c]u8 = null,
    pszFileName: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pNext: [*c]struct__TDNF_UPDATEINFO_PKG = null,
};
pub const TDNF_UPDATEINFO_PKG = struct__TDNF_UPDATEINFO_PKG;
pub const PTDNF_UPDATEINFO_PKG = [*c]struct__TDNF_UPDATEINFO_PKG;
pub const struct__TDNF_UPDATEINFO = extern struct {
    nType: c_int = 0,
    pszID: [*c]u8 = null,
    pszDate: [*c]u8 = null,
    pszDescription: [*c]u8 = null,
    nRebootRequired: c_int = 0,
    pReferences: PTDNF_UPDATEINFO_REF = null,
    pPackages: PTDNF_UPDATEINFO_PKG = null,
    pNext: [*c]struct__TDNF_UPDATEINFO = null,
};
pub const TDNF_UPDATEINFO = struct__TDNF_UPDATEINFO;
pub const PTDNF_UPDATEINFO = [*c]struct__TDNF_UPDATEINFO;
pub const struct__TDNF_UPDATEINFO_SUMMARY = extern struct {
    nCount: c_int = 0,
    nType: c_int = 0,
};
pub const TDNF_UPDATEINFO_SUMMARY = struct__TDNF_UPDATEINFO_SUMMARY;
pub const PTDNF_UPDATEINFO_SUMMARY = [*c]struct__TDNF_UPDATEINFO_SUMMARY;
pub const struct__TDNF_REPOSYNC_ARGS = extern struct {
    nDelete: c_int = 0,
    nDownloadMetadata: c_int = 0,
    nGPGCheck: c_int = 0,
    nNewestOnly: c_int = 0,
    nPrintUrlsOnly: c_int = 0,
    nNoRepoPath: c_int = 0,
    nSourceOnly: c_int = 0,
    pszDownloadPath: [*c]u8 = null,
    pszMetaDataPath: [*c]u8 = null,
    ppszArchs: [*c][*c]u8 = null,
};
pub const TDNF_REPOSYNC_ARGS = struct__TDNF_REPOSYNC_ARGS;
pub const PTDNF_REPOSYNC_ARGS = [*c]struct__TDNF_REPOSYNC_ARGS;
pub const REPOQUERY_WHAT_KEY_PROVIDES: c_int = 0;
pub const REPOQUERY_WHAT_KEY_OBSOLETES: c_int = 1;
pub const REPOQUERY_WHAT_KEY_CONFLICTS: c_int = 2;
pub const REPOQUERY_WHAT_KEY_REQUIRES: c_int = 3;
pub const REPOQUERY_WHAT_KEY_RECOMMENDS: c_int = 4;
pub const REPOQUERY_WHAT_KEY_SUGGESTS: c_int = 5;
pub const REPOQUERY_WHAT_KEY_SUPPLEMENTS: c_int = 6;
pub const REPOQUERY_WHAT_KEY_ENHANCES: c_int = 7;
pub const REPOQUERY_WHAT_KEY_DEPENDS: c_int = 8;
pub const REPOQUERY_WHAT_KEY_COUNT: c_int = 9;
pub const REPOQUERY_DEP_KEY_PROVIDES: c_int = 0;
pub const REPOQUERY_DEP_KEY_OBSOLETES: c_int = 1;
pub const REPOQUERY_DEP_KEY_CONFLICTS: c_int = 2;
pub const REPOQUERY_DEP_KEY_REQUIRES: c_int = 3;
pub const REPOQUERY_DEP_KEY_RECOMMENDS: c_int = 4;
pub const REPOQUERY_DEP_KEY_SUGGESTS: c_int = 5;
pub const REPOQUERY_DEP_KEY_SUPPLEMENTS: c_int = 6;
pub const REPOQUERY_DEP_KEY_ENHANCES: c_int = 7;
pub const REPOQUERY_DEP_KEY_DEPENDS: c_int = 8;
pub const REPOQUERY_DEP_KEY_REQUIRES_PRE: c_int = 9;
pub const REPOQUERY_DEP_KEY_COUNT: c_int = 10;
pub const struct__TDNF_REPOQUERY_ARGS = extern struct {
    pszSpec: [*c]u8 = null,
    nAvailable: c_int = 0,
    nDuplicates: c_int = 0,
    nExtras: c_int = 0,
    nLocation: c_int = 0,
    nInstalled: c_int = 0,
    nUpgrades: c_int = 0,
    nDowngrades: c_int = 0,
    nUserInstalled: c_int = 0,
    pszFile: [*c]u8 = null,
    pppszWhatKeys: [*c][*c][*c]u8 = null,
    ppszArchs: [*c][*c]u8 = null,
    nChangeLogs: c_int = 0,
    depKeySet: c_uint = 0,
    nList: c_int = 0,
    pszQueryFormat: [*c]u8 = null,
    nSource: c_int = 0,
};
pub const TDNF_REPOQUERY_ARGS = struct__TDNF_REPOQUERY_ARGS;
pub const PTDNF_REPOQUERY_ARGS = [*c]struct__TDNF_REPOQUERY_ARGS;
pub const HISTORY_CMD_LIST: c_int = 0;
pub const HISTORY_CMD_INIT: c_int = 1;
pub const HISTORY_CMD_ROLLBACK: c_int = 2;
pub const HISTORY_CMD_UNDO: c_int = 3;
pub const HISTORY_CMD_REDO: c_int = 4;
pub const HISTORY_CMD_ID: c_int = 5;
pub const HISTORY_CMD = c_uint;
pub const struct__TDNF_HISTORY_ARGS = extern struct {
    nCommand: HISTORY_CMD = @import("std").mem.zeroes(HISTORY_CMD),
    nInfo: c_int = 0,
    nFrom: c_int = 0,
    nTo: c_int = 0,
    nReverse: c_int = 0,
    pszSpec: [*c]u8 = null,
};
pub const TDNF_HISTORY_ARGS = struct__TDNF_HISTORY_ARGS;
pub const PTDNF_HISTORY_ARGS = [*c]struct__TDNF_HISTORY_ARGS;
pub const struct__TDNF_HISTORY_INFO_ITEM = extern struct {
    nId: c_int = 0,
    nType: c_int = 0,
    pszCmdLine: [*c]u8 = null,
    timeStamp: time_t = 0,
    nAddedCount: c_int = 0,
    nRemovedCount: c_int = 0,
    ppszAddedPkgs: [*c][*c]u8 = null,
    ppszRemovedPkgs: [*c][*c]u8 = null,
};
pub const TDNF_HISTORY_INFO_ITEM = struct__TDNF_HISTORY_INFO_ITEM;
pub const PTDNF_HISTORY_INFO_ITEM = [*c]struct__TDNF_HISTORY_INFO_ITEM;
pub const struct__TDNF_HISTORY_INFO = extern struct {
    nItemCount: c_int = 0,
    pItems: PTDNF_HISTORY_INFO_ITEM = null,
};
pub const TDNF_HISTORY_INFO = struct__TDNF_HISTORY_INFO;
pub const PTDNF_HISTORY_INFO = [*c]struct__TDNF_HISTORY_INFO;
pub const TDNF_ZIG_XFERINFOFUNCTION = ?*const fn (pUserData: ?*anyopaque, nDownloadTotal: i64, nDownloadedNow: i64, nUploadTotal: i64, nUploadedNow: i64) callconv(.c) c_int;
pub const struct__TDNF_ZIG_DOWNLOAD_REQUEST = extern struct {
    pszUrl: [*c]const u8 = null,
    pszDestination: [*c]const u8 = null,
    pfnProgress: TDNF_ZIG_XFERINFOFUNCTION = null,
    pProgressData: ?*anyopaque = null,
    pszUserAgent: [*c]const u8 = null,
    pszProxy: [*c]const u8 = null,
    pszProxyUserPwd: [*c]const u8 = null,
    pszUserName: [*c]const u8 = null,
    pszPassword: [*c]const u8 = null,
    pszSSLCaCert: [*c]const u8 = null,
    pszSSLClientCert: [*c]const u8 = null,
    pszSSLClientKey: [*c]const u8 = null,
    nSSLVerify: c_int = 0,
    nConnectTimeout: c_long = 0,
    nTimeout: c_long = 0,
    nLowSpeedLimit: c_long = 0,
    nLowSpeedTime: c_long = 0,
    nMaxRecvSpeed: c_long = 0,
};
pub const TDNF_ZIG_DOWNLOAD_REQUEST = struct__TDNF_ZIG_DOWNLOAD_REQUEST;
pub extern fn tdnf_rpm_config_create(pszInstallRoot: [*c]const u8) ?*tdnf_rpm_config;
pub extern fn tdnf_rpm_config_destroy(pConfig: ?*tdnf_rpm_config) void;
pub extern fn tdnf_rpm_config_apply_define(pConfig: ?*tdnf_rpm_config, pszDefinition: [*c]const u8) c_int;
pub const TDNF_REPOMD_RECORD_KIND_UNKNOWN: c_int = 0;
pub const TDNF_REPOMD_RECORD_KIND_PRIMARY: c_int = 1;
pub const TDNF_REPOMD_RECORD_KIND_UPDATEINFO: c_int = 4;
pub const struct__TDNF_REPOMD_CHECKSUM = extern struct {
    pszType: [*c]const u8 = null,
    pszValue: [*c]const u8 = null,
};
pub const TDNF_REPOMD_CHECKSUM = struct__TDNF_REPOMD_CHECKSUM;
pub const struct__TDNF_REPOMD_RECORD = extern struct {
    pszType: [*c]const u8 = null,
    dwKind: u32 = 0,
    pszLocationHref: [*c]const u8 = null,
    checksum: TDNF_REPOMD_CHECKSUM = @import("std").mem.zeroes(TDNF_REPOMD_CHECKSUM),
    openChecksum: TDNF_REPOMD_CHECKSUM = @import("std").mem.zeroes(TDNF_REPOMD_CHECKSUM),
    nTimestamp: u64 = 0,
    nSize: u64 = 0,
    nOpenSize: u64 = 0,
    nDatabaseVersion: u64 = 0,
    nHasTimestamp: c_int = 0,
    nHasSize: c_int = 0,
    nHasOpenSize: c_int = 0,
    nHasDatabaseVersion: c_int = 0,
};
pub const TDNF_REPOMD_RECORD = struct__TDNF_REPOMD_RECORD;
pub const struct__TDNF_REPOMD_NATIVE_REPO_INPUT = extern struct {
    pszId: [*c]const u8 = null,
    pszCacheDir: [*c]const u8 = null,
    pszSnapshotFile: [*c]const u8 = null,
    pszDirectory: [*c]const u8 = null,
};
pub const TDNF_REPOMD_NATIVE_REPO_INPUT = struct__TDNF_REPOMD_NATIVE_REPO_INPUT;
pub const PTDNF_REPOMD_NATIVE_REPO_INPUT = [*c]struct__TDNF_REPOMD_NATIVE_REPO_INPUT;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_INSTALL: c_int = 1;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_REINSTALL: c_int = 2;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_ERASE: c_int = 3;
pub const TDNF_REPOMD_NATIVE_TRANSACTION_OP_UPGRADE: c_int = 4;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM = extern struct {
    dwOperation: u32 = 0,
    pszPath: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszEVR: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = extern struct {
    dwOperation: u32 = 0,
    pszPath: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszEVR: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    dwRpmDbHnum: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 = struct__TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2;
pub const TDNF_REPOMD_NATIVE_PROBLEM_DEPENDENCY: c_int = 1;
pub const TDNF_REPOMD_NATIVE_PROBLEM_PRETRANS: c_int = 2;
pub const TDNF_REPOMD_NATIVE_PROBLEM_CONFLICT: c_int = 3;
pub const TDNF_REPOMD_NATIVE_PROBLEM_OBSOLETES: c_int = 4;
pub const TDNF_REPOMD_NATIVE_PROBLEM_FILE_CONFLICT: c_int = 5;
pub const TDNF_REPOMD_NATIVE_PROBLEM_UNSUPPORTED_MULTIPLE: c_int = 6;
pub const enum__TDNF_REPOMD_NATIVE_PROBLEM_TYPE = c_uint;
pub const TDNF_REPOMD_NATIVE_PROBLEM_TYPE = enum__TDNF_REPOMD_NATIVE_PROBLEM_TYPE;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = extern struct {
    nType: TDNF_REPOMD_NATIVE_PROBLEM_TYPE = @import("std").mem.zeroes(TDNF_REPOMD_NATIVE_PROBLEM_TYPE),
    dwInputIndex: u32 = 0,
    pszPackage: [*c]const u8 = null,
    pszRelatedPackage: [*c]const u8 = null,
    pszSubject: [*c]const u8 = null,
    dwCount: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = extern struct {
    dwPriorOffset: u32 = 0,
    dwPriorCount: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM;
pub const struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = extern struct {
    dwItemCount: u32 = 0,
    pdwOrderIndices: [*c]u32 = null,
    pItems: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN_ITEM = null,
    dwPriorHnumCount: u32 = 0,
    pdwPriorHnums: [*c]u32 = null,
    dwProblemCount: u32 = 0,
    pProblems: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PROBLEM = null,
};
pub const TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = struct__TDNF_REPOMD_NATIVE_TRANSACTION_PLAN;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = extern struct {
    pszRepository: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pszChecksumType: [*c]const u8 = null,
    pszChecksumValue: [*c]const u8 = null,
    pszLocationHref: [*c]const u8 = null,
    pszLocationBase: [*c]const u8 = null,
    pszSummary: [*c]const u8 = null,
    nPackageSize: u64 = 0,
    nInstalledSize: u64 = 0,
    dwPackageId: u32 = 0,
    dwRepositoryId: u32 = 0,
    dwEpoch: u32 = 0,
    dwRpmDbHnum: u32 = 0,
    nRepositoryKind: c_int = 0,
    nHasEpoch: c_int = 0,
    nHasRpmDbHnum: c_int = 0,
    nChecksumIsPkgId: c_int = 0,
    nChecksumIsHeaderOnly: c_int = 0,
    nHasPackageSize: c_int = 0,
    nHasInstalledSize: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = struct__TDNF_REPOMD_NATIVE_SOLVER_PACKAGE;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_ACTION = extern struct {
    dwPackageRef: u32 = 0,
    dwKind: u32 = 0,
    dwReason: u32 = 0,
    dwPriorOffset: u32 = 0,
    dwPriorCount: u32 = 0,
    dwRequestedJobId: u32 = 0,
    nHasRequestedJobId: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_ACTION = struct__TDNF_REPOMD_NATIVE_SOLVER_ACTION;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_RELATION = extern struct {
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszFlags: [*c]const u8 = null,
    dwComparison: u32 = 0,
    dwEpoch: u32 = 0,
    dwSense: u32 = 0,
    nHasEpoch: c_int = 0,
    nPre: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_RELATION = struct__TDNF_REPOMD_NATIVE_SOLVER_RELATION;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = extern struct {
    capability: TDNF_REPOMD_NATIVE_SOLVER_RELATION = @import("std").mem.zeroes(TDNF_REPOMD_NATIVE_SOLVER_RELATION),
    dwKind: u32 = 0,
    dwPackageRef: u32 = 0,
    dwRelatedPackageRef: u32 = 0,
    dwJobId: u32 = 0,
    dwCount: u32 = 0,
    nHasPackageRef: c_int = 0,
    nHasRelatedPackageRef: c_int = 0,
    nHasCapability: c_int = 0,
    nHasJobId: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = struct__TDNF_REPOMD_NATIVE_SOLVER_PROBLEM;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_RESULT = extern struct {
    pPackages: [*c]TDNF_REPOMD_NATIVE_SOLVER_PACKAGE = null,
    pdwSelectedPackageRefs: [*c]u32 = null,
    pActions: [*c]TDNF_REPOMD_NATIVE_SOLVER_ACTION = null,
    pdwPriorPackageRefs: [*c]u32 = null,
    pdwPriorHnums: [*c]u32 = null,
    pProblems: [*c]TDNF_REPOMD_NATIVE_SOLVER_PROBLEM = null,
    pdwSkippedJobIds: [*c]u32 = null,
    dwPackageCount: u32 = 0,
    dwSelectedPackageCount: u32 = 0,
    dwActionCount: u32 = 0,
    dwPriorPackageRefCount: u32 = 0,
    dwProblemCount: u32 = 0,
    dwSkippedJobCount: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_RESULT = struct__TDNF_REPOMD_NATIVE_SOLVER_RESULT;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = extern struct {
    pszId: [*c]const u8 = null,
    pszCacheDir: [*c]const u8 = null,
    pszSnapshotFile: [*c]const u8 = null,
    pszDirectory: [*c]const u8 = null,
    nPriority: i32 = 0,
    dwCost: u32 = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16;
pub const struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = extern struct {
    pszRepository: [*c]const u8 = null,
    pszName: [*c]const u8 = null,
    pszVersion: [*c]const u8 = null,
    pszRelease: [*c]const u8 = null,
    pszArch: [*c]const u8 = null,
    pszChecksumType: [*c]const u8 = null,
    pszChecksumValue: [*c]const u8 = null,
    dwEpoch: u32 = 0,
    nChecksumIsPkgId: c_int = 0,
    dwQueuePair: u32 = 0,
    nHasQueuePair: c_int = 0,
};
pub const TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB = struct__TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB;
pub extern fn TDNFRepoMdNativeTransactionLastError() [*c]const u8;
pub extern fn TDNFRepoMdNativeTransactionSolve(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM, dwItemCount: u32, pszInstallRoot: [*c]const u8, pppszOrderLines: [*c][*c][*c]u8, pdwOrderCount: [*c]u32, pppszProblemLines: [*c][*c][*c]u8, pdwProblemCount: [*c]u32) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanSolveV2(pItems: [*c]const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2, dwItemCount: u32, pszInstallRoot: [*c]const u8, ppPlan: [*c][*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) u32;
pub extern fn TDNFRepoMdNativeTransactionPlanFree(pPlan: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN) void;
pub const struct_tdnf_rpm_file = opaque {};
pub const tdnf_rpm_file = struct_tdnf_rpm_file;
pub extern fn tdnf_rpmdb_last_error() [*c]const u8;
pub extern fn tdnf_rpm_config_open_root_fd(config: ?*const tdnf_rpm_config) c_int;
pub const struct_tdnf_rpmdb_iter = opaque {};
pub const tdnf_rpmdb_iter = struct_tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_open(root: [*c]const u8) ?*tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_open_config(config: ?*const tdnf_rpm_config) ?*tdnf_rpmdb_iter;
pub extern fn tdnf_rpmdb_iter_close(it: ?*tdnf_rpmdb_iter) void;
pub extern fn tdnf_rpmdb_iter_next_header_blob_hnum(it: ?*tdnf_rpmdb_iter, hnum_out: [*c]u32, blob_out: [*c][*c]const u8, blob_len_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_write_install_file_config(config: ?*const tdnf_rpm_config, fh: ?*tdnf_rpm_file, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_replace_file_config(config: ?*const tdnf_rpm_config, old_hnum: u32, fh: ?*tdnf_rpm_file, install_tid: u32, install_time: u32, install_color: u32, file_states: [*c]const u8, file_state_count: usize, new_hnum_out: [*c]u32) c_int;
pub extern fn tdnf_rpmdb_write_erase_hnum_config(config: ?*const tdnf_rpm_config, hnum: u32) c_int;
pub const struct_tdnf_rpmdb_label_match = extern struct {
    hnum: u32 = 0,
    name: [*c]u8 = null,
    evr: [*c]u8 = null,
    arch: [*c]u8 = null,
};
pub const tdnf_rpmdb_label_match = struct_tdnf_rpmdb_label_match;
pub extern fn tdnf_rpmdb_find_label_matches_config(config: ?*const tdnf_rpm_config, name: [*c]const u8, evr: [*c]const u8, matches_out: [*c][*c]tdnf_rpmdb_label_match, count_out: [*c]usize) c_int;
pub extern fn tdnf_rpmdb_label_matches_free(matches: [*c]tdnf_rpmdb_label_match, count: usize) void;
pub extern fn tdnf_rpm_file_open(path: [*c]const u8) ?*tdnf_rpm_file;
pub extern fn tdnf_rpm_file_close(fh: ?*tdnf_rpm_file) void;
pub const struct_tdnf_rpm_file_metadata = extern struct {
    name: [*c]const u8 = null,
    version: [*c]const u8 = null,
    release: [*c]const u8 = null,
    arch: [*c]const u8 = null,
    epoch: u32 = 0,
    has_epoch: c_int = 0,
    package_kind: c_int = 0,
    main_header_blob: [*c]const u8 = null,
    main_header_blob_len: usize = 0,
};
pub const tdnf_rpm_file_metadata = struct_tdnf_rpm_file_metadata;
pub const struct_tdnf_rpm_header_view = extern struct {
    blob: [*c]const u8 = null,
    len: usize = 0,
};
pub const tdnf_rpm_header_view = struct_tdnf_rpm_header_view;
pub extern fn tdnf_rpm_header_name_equals(header_blob: [*c]const u8, header_len: usize, name: [*c]const u8) c_int;
pub extern fn tdnf_rpm_canonical_path_config(config: ?*const tdnf_rpm_config, path: [*c]const u8, output: [*c]u8, output_len: usize) c_int;
pub extern fn tdnf_rpm_header_owns_path_config(header_blob: [*c]const u8, header_len: usize, path: [*c]const u8, config: ?*const tdnf_rpm_config) c_int;
pub extern fn tdnf_rpm_file_get_metadata(fh: ?*tdnf_rpm_file, metadata_out: [*c]tdnf_rpm_file_metadata) c_int;
pub extern fn tdnf_rpm_file_main_header_blob(fh: ?*tdnf_rpm_file, out: [*c][*c]const u8, out_len: [*c]usize) c_int;
pub extern fn tdnf_rpm_file_bytes(fh: ?*tdnf_rpm_file, out: [*c][*c]const u8, out_len: [*c]usize) c_int;
pub extern fn tdnf_rpm_file_digest(fh: ?*tdnf_rpm_file, kind: c_int, out_digest: [*c]u8, out_len: usize) c_int;
pub extern fn tdnf_rpm_file_extract_source_config(fh: ?*tdnf_rpm_file, config: ?*const tdnf_rpm_config, trans_flags: u32) c_int;
pub const TDNF_RPM_INSTALL_KIND_INSTALL: c_int = 0;
pub const TDNF_RPM_INSTALL_KIND_UPGRADE: c_int = 1;
pub const TDNF_RPM_INSTALL_KIND_REINSTALL: c_int = 2;
pub const enum_tdnf_rpm_install_kind = c_uint;
pub const tdnf_rpm_install_kind = enum_tdnf_rpm_install_kind;
pub const struct_tdnf_rpm_install_prior_header = extern struct {
    blob: [*c]const u8 = null,
    len: usize = 0,
};
pub const tdnf_rpm_install_prior_header = struct_tdnf_rpm_install_prior_header;
pub const tdnf_rpm_install_conflict_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const tdnf_rpm_changed_path_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const struct_tdnf_rpm_install_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    trans_flags: u32 = 0,
    install_kind: tdnf_rpm_install_kind = @import("std").mem.zeroes(tdnf_rpm_install_kind),
    prior_headers: [*c]const tdnf_rpm_install_prior_header = null,
    prior_header_count: usize = 0,
    conflict_fn: tdnf_rpm_install_conflict_fn = null,
    conflict_fn_data: ?*anyopaque = null,
    changed_path_fn: tdnf_rpm_changed_path_fn = null,
    changed_path_fn_data: ?*anyopaque = null,
};
pub const tdnf_rpm_install_options = struct_tdnf_rpm_install_options;
pub extern fn tdnf_rpm_file_install(fh: ?*tdnf_rpm_file, options: [*c]const tdnf_rpm_install_options) c_int;
pub const TDNF_RPM_SCRIPTLET_PHASE_PRE: c_int = 0;
pub const TDNF_RPM_SCRIPTLET_PHASE_POST: c_int = 1;
pub const TDNF_RPM_SCRIPTLET_PHASE_PREUN: c_int = 2;
pub const TDNF_RPM_SCRIPTLET_PHASE_POSTUN: c_int = 3;
pub const TDNF_RPM_SCRIPTLET_PHASE_PRETRANS: c_int = 4;
pub const TDNF_RPM_SCRIPTLET_PHASE_POSTTRANS: c_int = 5;
pub const enum_tdnf_rpm_scriptlet_phase = c_uint;
pub const tdnf_rpm_scriptlet_phase = enum_tdnf_rpm_scriptlet_phase;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_NOT_RUN: c_int = 0;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_OK: c_int = 1;
pub const TDNF_RPM_SCRIPTLET_OUTCOME_SIGNALED: c_int = 3;
pub const enum_tdnf_rpm_scriptlet_outcome = c_uint;
pub const tdnf_rpm_scriptlet_outcome = enum_tdnf_rpm_scriptlet_outcome;
pub const struct_tdnf_rpm_scriptlet_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    arg1: c_int = 0,
    arg2: c_int = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
};
pub const tdnf_rpm_scriptlet_options = struct_tdnf_rpm_scriptlet_options;
pub const struct_tdnf_rpm_scriptlet_result = extern struct {
    ran: c_int = 0,
    critical: c_int = 0,
    outcome: tdnf_rpm_scriptlet_outcome = @import("std").mem.zeroes(tdnf_rpm_scriptlet_outcome),
    exit_status: c_int = 0,
    signal_number: c_int = 0,
};
pub const tdnf_rpm_scriptlet_result = struct_tdnf_rpm_scriptlet_result;
pub extern fn tdnf_rpm_header_run_scriptlet(header_blob: [*c]const u8, header_len: usize, phase: tdnf_rpm_scriptlet_phase, options: [*c]const tdnf_rpm_scriptlet_options, result_out: [*c]tdnf_rpm_scriptlet_result) c_int;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERIN: c_int = 0;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERUN: c_int = 1;
pub const TDNF_RPM_TRIGGER_PHASE_TRIGGERPOSTUN: c_int = 2;
pub const enum_tdnf_rpm_trigger_phase = c_uint;
pub const tdnf_rpm_trigger_phase = enum_tdnf_rpm_trigger_phase;
pub const struct_tdnf_rpm_trigger_options = extern struct {
    db_root: [*c]const u8 = null,
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
    arg2_override_present: c_int = 0,
    arg2_override_value: c_int = 0,
    transaction_headers: [*c]const tdnf_rpm_header_view = null,
    transaction_header_count: usize = 0,
    transaction_view_present: c_int = 0,
    trigger_owner_headers: [*c]const tdnf_rpm_header_view = null,
    trigger_owner_header_count: usize = 0,
    trigger_owner_view_present: c_int = 0,
};
pub const tdnf_rpm_trigger_options = struct_tdnf_rpm_trigger_options;
pub const struct_tdnf_rpm_trigger_result = extern struct {
    ran: c_int = 0,
    critical: c_int = 0,
    outcome: tdnf_rpm_scriptlet_outcome = @import("std").mem.zeroes(tdnf_rpm_scriptlet_outcome),
    exit_status: c_int = 0,
    signal_number: c_int = 0,
};
pub const tdnf_rpm_trigger_result = struct_tdnf_rpm_trigger_result;
pub extern fn tdnf_rpm_header_run_triggers(header_blob: [*c]const u8, header_len: usize, phase: tdnf_rpm_trigger_phase, options: [*c]const tdnf_rpm_trigger_options, result_out: [*c]tdnf_rpm_trigger_result) c_int;
pub const TDNF_RPM_FILE_TRIGGER_KIND_PACKAGE: c_int = 0;
pub const TDNF_RPM_FILE_TRIGGER_KIND_TRANSACTION: c_int = 1;
pub const enum_tdnf_rpm_file_trigger_kind = c_uint;
pub const tdnf_rpm_file_trigger_kind = enum_tdnf_rpm_file_trigger_kind;
pub const TDNF_RPM_TRIGGER_PRIORITY_ALL: c_int = 0;
pub const TDNF_RPM_TRIGGER_PRIORITY_HIGH: c_int = 1;
pub const TDNF_RPM_TRIGGER_PRIORITY_LOW: c_int = 2;
pub const enum_tdnf_rpm_trigger_priority_class = c_uint;
pub const tdnf_rpm_trigger_priority_class = enum_tdnf_rpm_trigger_priority_class;
pub const struct_tdnf_rpm_trigger_path = extern struct {
    path: [*c]const u8 = null,
    source_header_blob: [*c]const u8 = null,
    source_header_len: usize = 0,
};
pub const tdnf_rpm_trigger_path = struct_tdnf_rpm_trigger_path;
pub const struct_tdnf_rpm_file_trigger_owner = extern struct {
    header_blob: [*c]const u8 = null,
    header_len: usize = 0,
    paths: [*c]const tdnf_rpm_trigger_path = null,
    path_count: usize = 0,
    order: u64 = 0,
};
pub const tdnf_rpm_file_trigger_owner = struct_tdnf_rpm_file_trigger_owner;
pub const struct_tdnf_rpm_file_trigger_options = extern struct {
    install_root: [*c]const u8 = null,
    config: ?*const tdnf_rpm_config = null,
    install_root_fd: c_int = 0,
    trans_flags: u32 = 0,
    rpmdefines: [*c]const [*c]const u8 = null,
    rpmdefine_count: usize = 0,
    script_fd: c_int = 0,
    redirect_stdout_to_stderr: c_int = 0,
    suppress_stdin: c_int = 0,
};
pub const tdnf_rpm_file_trigger_options = struct_tdnf_rpm_file_trigger_options;
pub extern fn tdnf_rpm_header_validate_trigger_scripts_config(header_blob: [*c]const u8, header_len: usize, config: ?*const tdnf_rpm_config) c_int;
pub extern fn tdnf_rpm_header_has_file_trigger_metadata(header_blob: [*c]const u8, header_len: usize, kind: tdnf_rpm_file_trigger_kind) c_int;
pub extern fn tdnf_rpm_header_foreach_trigger_file(header_blob: [*c]const u8, header_len: usize, trans_flags: u32, callback: tdnf_rpm_changed_path_fn, callback_data: ?*anyopaque) c_int;
pub extern fn tdnf_rpm_run_file_triggers(owners: [*c]const tdnf_rpm_file_trigger_owner, owner_count: usize, phase: tdnf_rpm_trigger_phase, kind: tdnf_rpm_file_trigger_kind, priority_class: tdnf_rpm_trigger_priority_class, options: [*c]const tdnf_rpm_file_trigger_options, result_out: [*c]tdnf_rpm_trigger_result) c_int;
pub const tdnf_rpm_erase_keep_path_fn = ?*const fn (data: ?*anyopaque, path: [*c]const u8) callconv(.c) c_int;
pub const struct_tdnf_rpm_erase_options = extern struct {
    config: ?*const tdnf_rpm_config = null,
    trans_flags: u32 = 0,
    keep_path_fn: tdnf_rpm_erase_keep_path_fn = null,
    keep_path_fn_data: ?*anyopaque = null,
};
pub const tdnf_rpm_erase_options = struct_tdnf_rpm_erase_options;
pub extern fn tdnf_rpm_erase_header_blob(root: [*c]const u8, blob: [*c]const u8, blob_len: usize, options: [*c]const tdnf_rpm_erase_options) c_int;
pub const TDNF_PACKAGE_CONTEXT = struct__TDNF_PACKAGE_CONTEXT;
pub const struct__TDNF_REPO_METADATA = extern struct {
    pszRepoCacheDir: [*c]u8 = null,
    pszRepo: [*c]u8 = null,
    pszRepoMD: [*c]u8 = null,
    pszPrimary: [*c]u8 = null,
    pszFileLists: [*c]u8 = null,
    pszUpdateInfo: [*c]u8 = null,
    pszOther: [*c]u8 = null,
};
pub const TDNF_PLUGIN = struct__TDNF_PLUGIN_;
pub const TDNF = struct__TDNF_;
pub const struct__TDNF_CACHED_RPM_ENTRY = extern struct {
    pszFilePath: [*c]u8 = null,
    pNext: [*c]struct__TDNF_CACHED_RPM_ENTRY = null,
};
pub const TDNF_CACHED_RPM_ENTRY = struct__TDNF_CACHED_RPM_ENTRY;
pub const PTDNF_CACHED_RPM_ENTRY = [*c]struct__TDNF_CACHED_RPM_ENTRY;
pub const struct__TDNF_CACHED_RPM_LIST = extern struct {
    nSize: c_int = 0,
    pHead: PTDNF_CACHED_RPM_ENTRY = null,
};
pub const TDNF_CACHED_RPM_LIST = struct__TDNF_CACHED_RPM_LIST;
pub const PTDNF_CACHED_RPM_LIST = [*c]struct__TDNF_CACHED_RPM_LIST;
pub const TDNF_RPM_TS_ITEM_TYPE = c_uint;
pub const struct__TDNF_RPM_TS_ITEM = extern struct {
    nType: TDNF_RPM_TS_ITEM_TYPE = @import("std").mem.zeroes(TDNF_RPM_TS_ITEM_TYPE),
    pRpmFile: ?*tdnf_rpm_file = null,
    dwRpmDbHnum: u32 = 0,
    nPackageKind: c_int = 0,
    pszPath: [*c]u8 = null,
    pszName: [*c]u8 = null,
    pszEVR: [*c]u8 = null,
    pszArch: [*c]u8 = null,
    pNext: [*c]struct__TDNF_RPM_TS_ITEM = null,
};
pub const TDNF_RPM_TS_ITEM = struct__TDNF_RPM_TS_ITEM;
pub const PTDNF_RPM_TS_ITEM = [*c]struct__TDNF_RPM_TS_ITEM;
pub const struct__TDNF_RPM_TS_ = extern struct {
    nQuiet: c_int = 0,
    nTransFlags: TDNF_RPMTRANS_FLAGS = 0,
    pCachedRpmsArray: PTDNF_CACHED_RPM_LIST = null,
    dwTransactionItemCount: u32 = 0,
    pTransactionItems: PTDNF_RPM_TS_ITEM = null,
    pTransactionItemsTail: PTDNF_RPM_TS_ITEM = null,
    pNativePlan: [*c]TDNF_REPOMD_NATIVE_TRANSACTION_PLAN = null,
};
pub const TDNFRPMTS = struct__TDNF_RPM_TS_;
pub const TDNF_REPO_METADATA = struct__TDNF_REPO_METADATA;
pub extern fn create_cnfnode(name: [*c]const u8) [*c]struct_cnfnode;
pub extern fn create_cnfnode_keyval(keyval: [*c]const u8) [*c]struct_cnfnode;
pub extern fn cnfnode_getval(cn: [*c]const struct_cnfnode) [*c]const u8;
pub extern fn cnfnode_setval(cn: [*c]struct_cnfnode, value: [*c]const u8) void;
pub extern fn destroy_cnftree(cn: [*c]struct_cnfnode) void;
pub extern fn append_node(cn_parent: [*c]struct_cnfnode, cn: [*c]struct_cnfnode) void;
pub extern fn find_node(cn_list: [*c]struct_cnfnode, name: [*c]const u8) [*c]struct_cnfnode;
pub extern fn TDNFInit() u32;
pub extern fn TDNFOpenHandle(pArgs: PTDNF_CMD_ARGS, pTdnf: [*c]PTDNF) u32;
pub extern fn TDNFRefresh(pTdnf: PTDNF) u32;
pub extern fn TDNFCheckUpdates(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFClean(pTdnf: PTDNF, nCleanType: u32) u32;
pub extern fn TDNFList(pTdnf: PTDNF, nScope: TDNF_SCOPE, ppszPackageNameSpecs: [*c][*c]u8, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFInfo(pTdnf: PTDNF, nScope: TDNF_SCOPE, ppszPackageNameSpecs: [*c][*c]u8, ppPkgListInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFRepoList(pTdnf: PTDNF, nFilter: TDNF_REPOLISTFILTER, ppRepoData: [*c]PTDNF_REPO_DATA) u32;
pub extern fn TDNFCheckPackages(pTdnf: PTDNF) u32;
pub extern fn TDNFCheckLocalPackages(pTdnf: PTDNF, pszLocalPath: [*c]const u8) u32;
pub extern fn TDNFProvides(pTdnf: PTDNF, pszSpec: [*c]const u8, ppPkgInfo: [*c]PTDNF_PKG_INFO) u32;
pub extern fn TDNFRepoSync(pTdnf: PTDNF, pReposyncArgs: PTDNF_REPOSYNC_ARGS) u32;
pub extern fn TDNFRepoQuery(pTdnf: PTDNF, pRepoqueryArgs: PTDNF_REPOQUERY_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFUpdateInfo(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppUpdateInfo: [*c]PTDNF_UPDATEINFO) u32;
pub extern fn TDNFUpdateInfoSummary(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, ppSummary: [*c]PTDNF_UPDATEINFO_SUMMARY) u32;
pub extern fn TDNFHistoryResolve(pTdnf: PTDNF, pHistoryArgs: PTDNF_HISTORY_ARGS, ppSolvedPkgInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFHistoryList(pTdnf: PTDNF, pHistoryArgs: PTDNF_HISTORY_ARGS, ppHistoryInfo: [*c]PTDNF_HISTORY_INFO) u32;
pub extern fn TDNFGetPackageUrls(pTdnf: PTDNF, pSolvedPkgInfo: PTDNF_SOLVED_PKG_INFO, pppszUrls: [*c][*c][*c]u8, pnCount: [*c]c_int) u32;
pub extern fn TDNFHistoryGetId(pTdnf: PTDNF, pnId: [*c]c_int) u32;
pub extern fn TDNFCountCommand(pTdnf: PTDNF, pdwCount: [*c]u32) u32;
pub extern fn TDNFGetVersion() [*c]const u8;
pub extern fn TDNFGetPackageName() [*c]const u8;
pub extern fn TDNFSearchCommand(pTdnf: PTDNF, pCmdArgs: PTDNF_CMD_ARGS, ppPkgInfo: [*c]PTDNF_PKG_INFO, pdwCount: [*c]u32) u32;
pub extern fn TDNFResolve(pTdnf: PTDNF, nAlterType: TDNF_ALTERTYPE, ppSolvedPkgInfo: [*c]PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFTransactionPlanSetEnabled(pTdnf: PTDNF, dwEnabled: u32) u32;
pub extern fn TDNFTransactionPlanResolveCanonicalJson(pTdnf: PTDNF, ppszCmds: [*c][*c]u8, dwCmdCount: u32, ppszJson: [*c][*c]u8) u32;
pub extern fn TDNFTransactionPlanGetCanonicalJson(pTdnf: PTDNF, ppszJson: [*c][*c]u8) u32;
pub extern fn TDNFTransactionPlanFreeCanonicalJson(pszJson: [*c]u8) void;
pub extern fn TDNFAlterCommand(pTdnf: PTDNF, pSolvedInfo: PTDNF_SOLVED_PKG_INFO) u32;
pub extern fn TDNFAlterHistoryCommand(pTdnf: PTDNF, pSolvedInfo: PTDNF_SOLVED_PKG_INFO, pHistoryArgs: PTDNF_HISTORY_ARGS) u32;
pub extern fn TDNFMark(pTdnf: PTDNF, ppszPackageNameSpecs: [*c][*c]u8, dwValue: u32) u32;
pub extern fn TDNFGetErrorString(dwErrorCode: u32, ppszErrorString: [*c][*c]u8) u32;
pub extern fn TDNFCloseHandle(pTdnf: PTDNF) void;
pub extern fn TDNFFreeCmdArgs(pCmdArgs: PTDNF_CMD_ARGS) void;
pub extern fn TDNFFreePackageInfo(pPkgInfo: PTDNF_PKG_INFO) void;
pub extern fn TDNFFreePackageInfoArray(pPkgInfo: PTDNF_PKG_INFO, dwLength: u32) void;
pub extern fn TDNFFreeRepos(pRepos: PTDNF_REPO_DATA) void;
pub extern fn TDNFFreeSolvedPackageInfo(pSolvedPkgInfo: PTDNF_SOLVED_PKG_INFO) void;
pub extern fn TDNFFreeUpdateInfo(pUpdateInfo: PTDNF_UPDATEINFO) void;
pub extern fn TDNFFreeUpdateInfoSummary(pSummary: PTDNF_UPDATEINFO_SUMMARY) void;
pub extern fn TDNFFreeHistoryInfo(pHistoryInfo: PTDNF_HISTORY_INFO) void;
pub extern fn TDNFUninit() void;
pub const HTDNF = ?*anyopaque;
pub const PTDNF_CLI_CONTEXT = [*c]struct__TDNF_CLI_CONTEXT_;
pub const PFN_TDNF_ALTER = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_SOLVED_PKG_INFO) callconv(.c) u32;
pub const PFN_TDNF_CHECK_LOCAL = ?*const fn (PTDNF_CLI_CONTEXT, [*c]const u8) callconv(.c) u32;
pub const PFN_TDNF_CHECK_UPDATE = ?*const fn (PTDNF_CLI_CONTEXT, [*c][*c]u8, [*c]PTDNF_PKG_INFO, [*c]u32) callconv(.c) u32;
pub const PFN_TDNF_CHECK = ?*const fn (PTDNF_CLI_CONTEXT) callconv(.c) u32;
pub const PFN_TDNF_CLEAN = ?*const fn (PTDNF_CLI_CONTEXT, u32) callconv(.c) u32;
pub const PFN_TDNF_COUNT = ?*const fn (PTDNF_CLI_CONTEXT, [*c]u32) callconv(.c) u32;
pub const struct__TDNF_LIST_ARGS = extern struct {
    nScope: TDNF_SCOPE = @import("std").mem.zeroes(TDNF_SCOPE),
    ppszPackageNameSpecs: [*c][*c]u8 = null,
};
pub const PTDNF_LIST_ARGS = [*c]struct__TDNF_LIST_ARGS;
pub const PFN_TDNF_INFO = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_LIST_ARGS, [*c]PTDNF_PKG_INFO, [*c]u32) callconv(.c) u32;
pub const PFN_TDNF_LIST = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_LIST_ARGS, [*c]PTDNF_PKG_INFO, [*c]u32) callconv(.c) u32;
pub const PFN_TDNF_PROVIDES = ?*const fn (PTDNF_CLI_CONTEXT, [*c]const u8, [*c]PTDNF_PKG_INFO) callconv(.c) u32;
pub const PFN_TDNF_REPOLIST = ?*const fn (PTDNF_CLI_CONTEXT, TDNF_REPOLISTFILTER, [*c]PTDNF_REPO_DATA) callconv(.c) u32;
pub const PFN_TDNF_REPOSYNC = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_REPOSYNC_ARGS) callconv(.c) u32;
pub const PFN_TDNF_REPOQUERY = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_REPOQUERY_ARGS, [*c]PTDNF_PKG_INFO, [*c]u32) callconv(.c) u32;
pub const PFN_TDNF_RESOLVE = ?*const fn (PTDNF_CLI_CONTEXT, TDNF_ALTERTYPE, [*c]PTDNF_SOLVED_PKG_INFO) callconv(.c) u32;
pub const PFN_TDNF_SEARCH = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_CMD_ARGS, [*c]PTDNF_PKG_INFO, [*c]u32) callconv(.c) u32;
pub const struct__TDNF_UPDATEINFO_ARGS = extern struct {
    nMode: TDNF_UPDATEINFO_OUTPUT = @import("std").mem.zeroes(TDNF_UPDATEINFO_OUTPUT),
    nScope: TDNF_SCOPE = @import("std").mem.zeroes(TDNF_SCOPE),
    nType: TDNF_UPDATEINFO_TYPE = @import("std").mem.zeroes(TDNF_UPDATEINFO_TYPE),
    ppszPackageNameSpecs: [*c][*c]u8 = null,
};
pub const PTDNF_UPDATEINFO_ARGS = [*c]struct__TDNF_UPDATEINFO_ARGS;
pub const PFN_TDNF_UPDATEINFO = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_UPDATEINFO_ARGS, [*c]PTDNF_UPDATEINFO) callconv(.c) u32;
pub const PFN_TDNF_UPDATEINFO_SUMMARY = ?*const fn (PTDNF_CLI_CONTEXT, TDNF_AVAIL, PTDNF_UPDATEINFO_ARGS, [*c]PTDNF_UPDATEINFO_SUMMARY) callconv(.c) u32;
pub const PFN_TDNF_HISTORY_CMD = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_HISTORY_ARGS, [*c]PTDNF_HISTORY_INFO) callconv(.c) u32;
pub const PFN_TDNF_HISTORY_RESOLVE_CMD = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_HISTORY_ARGS, [*c]PTDNF_SOLVED_PKG_INFO) callconv(.c) u32;
pub const PFN_TDNF_ALTER_HISTORY = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_SOLVED_PKG_INFO, PTDNF_HISTORY_ARGS) callconv(.c) u32;
pub const PFN_TDNF_MARK_COMMAND = ?*const fn (pContext: PTDNF_CLI_CONTEXT, ppszPkgNameSpecs: [*c][*c]u8, nValue: u32) callconv(.c) u32;
pub const PFN_TDNF_GET_PKG_URLS = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_SOLVED_PKG_INFO, [*c][*c][*c]u8, [*c]c_int) callconv(.c) u32;
pub const PFN_TDNF_HISTORY_GET_ID = ?*const fn (PTDNF_CLI_CONTEXT, [*c]c_int) callconv(.c) u32;
pub const struct__TDNF_CLI_CONTEXT_ = extern struct {
    hTdnf: HTDNF = null,
    pUserData: ?*anyopaque = null,
    pFnAlter: PFN_TDNF_ALTER = null,
    pFnCheckLocal: PFN_TDNF_CHECK_LOCAL = null,
    pFnCheckUpdate: PFN_TDNF_CHECK_UPDATE = null,
    pFnCheck: PFN_TDNF_CHECK = null,
    pFnClean: PFN_TDNF_CLEAN = null,
    pFnCount: PFN_TDNF_COUNT = null,
    pFnInfo: PFN_TDNF_INFO = null,
    pFnList: PFN_TDNF_LIST = null,
    pFnProvides: PFN_TDNF_PROVIDES = null,
    pFnRepoList: PFN_TDNF_REPOLIST = null,
    pFnRepoSync: PFN_TDNF_REPOSYNC = null,
    pFnRepoQuery: PFN_TDNF_REPOQUERY = null,
    pFnResolve: PFN_TDNF_RESOLVE = null,
    pFnSearch: PFN_TDNF_SEARCH = null,
    pFnUpdateInfo: PFN_TDNF_UPDATEINFO = null,
    pFnUpdateInfoSummary: PFN_TDNF_UPDATEINFO_SUMMARY = null,
    pFnHistoryList: PFN_TDNF_HISTORY_CMD = null,
    pFnHistoryResolve: PFN_TDNF_HISTORY_RESOLVE_CMD = null,
    pFnAlterHistory: PFN_TDNF_ALTER_HISTORY = null,
    pFnMark: PFN_TDNF_MARK_COMMAND = null,
    pFnGetPackageUrls: PFN_TDNF_GET_PKG_URLS = null,
    pFnHistoryGetId: PFN_TDNF_HISTORY_GET_ID = null,
};
pub const PFN_CMD = ?*const fn (PTDNF_CLI_CONTEXT, PTDNF_CMD_ARGS) callconv(.c) u32;
pub const struct__TDNF_CLI_CMD_MAP = extern struct {
    pszCmdName: [*c]const u8 = null,
    pFnCmd: PFN_CMD = null,
    ReqRoot: bool = false,
};
pub const TDNF_CLI_CMD_MAP = struct__TDNF_CLI_CMD_MAP;
pub const TDNF_LIST_ARGS = struct__TDNF_LIST_ARGS;
pub const TDNF_UPDATEINFO_ARGS = struct__TDNF_UPDATEINFO_ARGS;
pub const TDNF_CLI_CONTEXT = struct__TDNF_CLI_CONTEXT_;
pub extern fn TDNFCliParseArgs(argc: c_int, argv: [*c][*c]u8, ppCmdArgs: [*c]PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliParseHistoryArgs(pArgs: PTDNF_CMD_ARGS, ppHistoryArgs: [*c]PTDNF_HISTORY_ARGS) u32;
pub extern fn TDNFCliFreeHistoryArgs(pHistoryArgs: PTDNF_HISTORY_ARGS) void;
pub extern fn TDNFCliParseListArgs(pCmdArgs: PTDNF_CMD_ARGS, ppListArgs: [*c]PTDNF_LIST_ARGS) u32;
pub extern fn TDNFCliParseInfoArgs(pCmdArgs: PTDNF_CMD_ARGS, ppListArgs: [*c]PTDNF_LIST_ARGS) u32;
pub extern fn TDNFCliFreeListArgs(pListArgs: PTDNF_LIST_ARGS) void;
pub extern fn TDNFCliParseCleanArgs(pCmdArgs: PTDNF_CMD_ARGS, pnCleanType: [*c]u32) u32;
pub extern fn TDNFCliParseRepoListArgs(pCmdArgs: PTDNF_CMD_ARGS, pnFilter: [*c]TDNF_REPOLISTFILTER) u32;
pub extern fn TDNFCliParseRepoSyncArgs(pCmdArgs: PTDNF_CMD_ARGS, ppReposyncArgs: [*c]PTDNF_REPOSYNC_ARGS) u32;
pub extern fn TDNFCliParseRepoQueryArgs(pCmdArgs: PTDNF_CMD_ARGS, ppRepoqueryArgs: [*c]PTDNF_REPOQUERY_ARGS) u32;
pub extern fn TDNFCliParseUpdateInfoArgs(pCmdArgs: PTDNF_CMD_ARGS, ppUpdateInfoArgs: [*c]PTDNF_UPDATEINFO_ARGS) u32;
pub extern fn TDNFCliParsePackageArgs(pCmdArgs: PTDNF_CMD_ARGS, pppszPackageArgs: [*c][*c][*c]u8, pnPackageCount: [*c]const c_int) u32;
pub extern fn TDNFCliGetErrorString(dwErrorCode: u32, ppszError: [*c][*c]u8) u32;
pub extern fn TDNFCliFreeUpdateInfoArgs(pUpdateInfoArgs: PTDNF_UPDATEINFO_ARGS) void;
pub extern fn TDNFCliFreeRepoSyncArgs(pReposyncArgs: PTDNF_REPOSYNC_ARGS) void;
pub extern fn TDNFCliFreeRepoQueryArgs(pRepoqueryArgs: PTDNF_REPOQUERY_ARGS) void;
pub extern fn TDNFCliAutoEraseCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliCleanCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliCountCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliListCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliInfoCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliSearchCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliRepoListCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliCheckCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliCheckLocalCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliCheckUpdateCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliMakeCacheCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliProvidesCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliRepoSyncCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliRepoQueryCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliUpdateInfoCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliHelpCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliHistoryCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliDowngradeCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliEraseCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliInstallCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliReinstallCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliDistroSyncCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliUpgradeCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliMarkCommand(pContext: PTDNF_CLI_CONTEXT, pCmdArgs: PTDNF_CMD_ARGS) u32;
pub extern fn TDNFCliShowUsage() void;
pub extern fn TDNFCliShowHelp() void;
pub extern fn TDNFCliShowNoSuchCommand(pszCmd: [*c]const u8) void;
pub const EPERM = @as(c_int, 1);
pub const ENOENT = @as(c_int, 2);
pub const EIO = @as(c_int, 5);
pub const ENOMEM = @as(c_int, 12);
pub const EACCES = @as(c_int, 13);
pub const ENOTDIR = @as(c_int, 20);
pub const EINVAL = @as(c_int, 22);
pub const ENAMETOOLONG = @as(c_int, 36);
pub const ENOSYS = @as(c_int, 38);
pub const ENODATA = @as(c_int, 61);
pub const EOVERFLOW = @as(c_int, 75);
pub const EBADFD = @as(c_int, 77);
pub const CLEANTYPE_NONE = @as(c_int, 0x00);
pub const CLEANTYPE_PACKAGES = @as(c_int, 0x01);
pub const CLEANTYPE_METADATA = @as(c_int, 0x02);
pub const CLEANTYPE_DBCACHE = @as(c_int, 0x04);
pub const CLEANTYPE_PLUGINS = @as(c_int, 0x08);
pub const CLEANTYPE_EXPIRE_CACHE = @as(c_int, 0x10);
pub const CLEANTYPE_KEYS = @as(c_int, 0x20);
pub const CLEANTYPE_ALL = @as(c_int, 0xff);
pub const TDNF_REPOSYNC_MAXARCHS = @as(c_int, 10);
pub const TDNF_REPOQUERY_MAXARCHS = @as(c_int, 10);
pub const LOG_ERR = @as(c_int, 1);
pub const LOG_CRIT = @as(c_int, 2);
pub const ERROR_TDNF_BASE = @as(c_int, 1000);
pub const ERROR_TDNF_INVALID_REPO_FILE = @as(c_int, 1004);
pub const ERROR_TDNF_NO_MATCH = @as(c_int, 1011);
pub const ERROR_TDNF_INVALID_ALLOCSIZE = @as(c_int, 1024);
pub const ERROR_TDNF_STRING_TOO_LONG = @as(c_int, 1025);
pub const ERROR_TDNF_ALREADY_INSTALLED = @as(c_int, 1026);
pub const ERROR_TDNF_PROTECTED = @as(c_int, 1030);
pub const ERROR_TDNF_OPERATION_ABORTED = @as(c_int, 1032);
pub const ERROR_TDNF_INVALID_INPUT = @as(c_int, 1033);
pub const ERROR_TDNF_INVALID_REPO_NAME = @as(c_int, 1038);
pub const ERROR_TDNF_SOLV_BASE = @as(c_int, 1300);
pub const ERROR_TDNF_SOLV_FAILED = ERROR_TDNF_SOLV_BASE + @as(c_int, 1);
pub const ERROR_TDNF_SOLV_IO = ERROR_TDNF_SOLV_BASE + @as(c_int, 4);
pub const ERROR_TDNF_RPM_HEADER_CONVERT_FAILED = @as(c_int, 1509);
pub const ERROR_TDNF_URL_INVALID = @as(c_int, 1524);
pub const ERROR_TDNF_RPMTS_OPENDB_FAILED = @as(c_int, 1526);
pub const ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED = @as(c_int, 1530);
pub const ERROR_TDNF_NO_SEARCH_RESULTS = @as(c_int, 1599);
pub const ERROR_TDNF_SYSTEM_BASE = @as(c_int, 1600);
pub const ERROR_TDNF_PERM = ERROR_TDNF_SYSTEM_BASE + EPERM;
pub const ERROR_TDNF_INVALID_PARAMETER = ERROR_TDNF_SYSTEM_BASE + EINVAL;
pub const ERROR_TDNF_OUT_OF_MEMORY = ERROR_TDNF_SYSTEM_BASE + ENOMEM;
pub const ERROR_TDNF_NO_DATA = ERROR_TDNF_SYSTEM_BASE + ENODATA;
pub const ERROR_TDNF_FILE_NOT_FOUND = ERROR_TDNF_SYSTEM_BASE + ENOENT;
pub const ERROR_TDNF_ACCESS_DENIED = ERROR_TDNF_SYSTEM_BASE + EACCES;
pub const ERROR_TDNF_FILESYS_IO = ERROR_TDNF_SYSTEM_BASE + EIO;
pub const ERROR_TDNF_NAME_TOO_LONG = ERROR_TDNF_SYSTEM_BASE + ENAMETOOLONG;
pub const ERROR_TDNF_CALL_NOT_SUPPORTED = ERROR_TDNF_SYSTEM_BASE + ENOSYS;
pub const ERROR_TDNF_INVALID_DIR = ERROR_TDNF_SYSTEM_BASE + ENOTDIR;
pub const ERROR_TDNF_OVERFLOW = ERROR_TDNF_SYSTEM_BASE + EOVERFLOW;
pub const ERROR_TDNF_JSONDUMP = @as(c_int, 1700);
pub const ERROR_TDNF_CHECKSUM_VALIDATION_FAILED = @as(c_int, 2501);
pub const ERROR_TDNF_FIPS_MODE_FORBIDDEN = @as(c_int, 2600);
pub const ERROR_TDNF_CLI_CHECK_UPDATES_AVAILABLE = @as(c_int, 100);
pub const ERROR_TDNF_CLI_BASE = @as(c_int, 900);
pub const ERROR_TDNF_CLI_NO_MATCH = ERROR_TDNF_CLI_BASE + @as(c_int, 1);
pub const ERROR_TDNF_CLI_INVALID_ARGUMENT = ERROR_TDNF_CLI_BASE + @as(c_int, 2);
pub const ERROR_TDNF_CLI_CLEAN_REQUIRES_OPTION = ERROR_TDNF_CLI_BASE + @as(c_int, 3);
pub const ERROR_TDNF_CLI_NOT_ENOUGH_ARGS = ERROR_TDNF_CLI_BASE + @as(c_int, 4);
pub const ERROR_TDNF_CLI_NOTHING_TO_DO = ERROR_TDNF_CLI_BASE + @as(c_int, 5);
pub const ERROR_TDNF_CLI_CHECKLOCAL_EXPECT_DIR = ERROR_TDNF_CLI_BASE + @as(c_int, 6);
pub const ERROR_TDNF_CLI_PROVIDES_EXPECT_ARG = ERROR_TDNF_CLI_BASE + @as(c_int, 7);
pub const ERROR_TDNF_CLI_OPTION_NAME_INVALID = ERROR_TDNF_CLI_BASE + @as(c_int, 8);
pub const ERROR_TDNF_CLI_OPTION_ARG_REQUIRED = ERROR_TDNF_CLI_BASE + @as(c_int, 9);
pub const ERROR_TDNF_CLI_OPTION_ARG_UNEXPECTED = ERROR_TDNF_CLI_BASE + @as(c_int, 10);
pub const ERROR_TDNF_CLI_SETOPT_NO_EQUALS = ERROR_TDNF_CLI_BASE + @as(c_int, 11);
pub const ERROR_TDNF_CLI_NO_SUCH_CMD = ERROR_TDNF_CLI_BASE + @as(c_int, 12);
pub const ERROR_TDNF_CLI_DOWNLOADDIR_REQUIRES_DOWNLOADONLY = ERROR_TDNF_CLI_BASE + @as(c_int, 13);
pub const ERROR_TDNF_CLI_ONE_DEP_ONLY = ERROR_TDNF_CLI_BASE + @as(c_int, 14);
pub const ERROR_TDNF_CLI_ALLDEPS_REQUIRES_DOWNLOADONLY = ERROR_TDNF_CLI_BASE + @as(c_int, 15);
pub const ERROR_TDNF_CLI_NODEPS_REQUIRES_DOWNLOADONLY = ERROR_TDNF_CLI_BASE + @as(c_int, 16);
pub const ERROR_TDNF_CLI_INVALID_MIXED_QUERY_QUERYFORMAT = ERROR_TDNF_CLI_BASE + @as(c_int, 17);
pub const cnfnode = struct_cnfnode;
