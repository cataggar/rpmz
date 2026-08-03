/*
 * Copyright (C) 2015-2022 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#pragma once

typedef struct _TDNF_PLUGIN_
{
    char *pszName;
    int nEnabled;
    void *pModule;
    PTDNF_PLUGIN_HANDLE pHandle;
    TDNF_PLUGIN_EVENT RegisterdEvts;
    TDNF_PLUGIN_INTERFACE stInterface;
    struct _TDNF_PLUGIN_ *pNext;
} TDNF_PLUGIN;

typedef struct _TDNF_
{
    PSolvSack pSack;
    PTDNF_CMD_ARGS pArgs;
    PTDNF_CONF pConf;
    tdnf_rpm_config *pRpmConfig;
    PTDNF_REPO_DATA pRepos;
    Repo *pSolvCmdLineRepo;
    PTDNF_PLUGIN pPlugins;
    char **ppszRepoFromDirIds;
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *pRequestTrace;
    TDNF_TRANSACTION_PLAN_STATE *pTransactionPlanState;
    /* "repo\x1fNEVRA" refs of every package hidden by excludepkgs/--exclude
       and minversions, produced natively. This is the sole representation of
       the hidden set: it feeds the native solver's hidden-available list and
       the plan's repository visibility snapshot. */
    char **ppszHiddenRefs;
    uint32_t dwHiddenRefCount;
    /* Local .rpm path of every solvable in the command-line repository,
       recorded where it is already known -- when the file is handed to
       TDNFRepoMdNativeAddRpm -- and indexed by the handle that call
       returns. Goal translation needs the path back and used to re-derive
       it from libsolv; keeping it here means the only component that has
       ever known it is also the one that reports it.

       The two arrays are parallel and share dwCmdLinePkgCount. They are
       emptied at the top of TDNFAddCmdLinePackages, not just at
       TDNFCloseHandle: TDNFRefresh() rebuilds the sack into a replacement
       pool with a new, empty command-line repo, so ids recorded before a
       refresh name nothing afterwards and the fresh pool reissues them. */
    TDNF_PKG_ID *pdwCmdLinePkgIds;
    char **ppszCmdLinePkgPaths;
    uint32_t dwCmdLinePkgCount;
    uint32_t nTestReloadFailureStage;
} TDNF;

typedef struct _TDNF_CACHED_RPM_ENTRY
{
    char* pszFilePath;
    struct _TDNF_CACHED_RPM_ENTRY *pNext;
} TDNF_CACHED_RPM_ENTRY, *PTDNF_CACHED_RPM_ENTRY;

typedef struct _TDNF_CACHED_RPM_LIST
{
    int nSize;
    PTDNF_CACHED_RPM_ENTRY pHead;
} TDNF_CACHED_RPM_LIST, *PTDNF_CACHED_RPM_LIST;

typedef enum
{
    TDNF_RPM_TS_ITEM_INSTALL = 1,
    TDNF_RPM_TS_ITEM_UPGRADE = 2,
    TDNF_RPM_TS_ITEM_REINSTALL = 3,
    TDNF_RPM_TS_ITEM_ERASE = 4
} TDNF_RPM_TS_ITEM_TYPE;

typedef struct _TDNF_RPM_TS_ITEM
{
    TDNF_RPM_TS_ITEM_TYPE nType;
    tdnf_rpm_file *pRpmFile;
    uint32_t dwRpmDbHnum;
    int nPackageKind;
    char *pszPath;
    char *pszName;
    char *pszEVR;
    char *pszArch;
    struct _TDNF_RPM_TS_ITEM *pNext;
} TDNF_RPM_TS_ITEM, *PTDNF_RPM_TS_ITEM;

typedef struct _TDNF_RPM_TS_
{
    int                     nQuiet;
    TDNF_RPMTRANS_FLAGS     nTransFlags;
    PTDNF_CACHED_RPM_LIST   pCachedRpmsArray;
    uint32_t                dwTransactionItemCount;
    PTDNF_RPM_TS_ITEM       pTransactionItems;
    PTDNF_RPM_TS_ITEM       pTransactionItemsTail;
    TDNF_REPOMD_NATIVE_TRANSACTION_PLAN *pNativePlan;
} TDNFRPMTS, *PTDNFRPMTS;

typedef struct _TDNF_REPO_METADATA
{
    char *pszRepoCacheDir;
    char *pszRepo;
    char *pszRepoMD;
    char *pszPrimary;
    char *pszFileLists;
    char *pszUpdateInfo;
    char *pszOther;
} TDNF_REPO_METADATA,*PTDNF_REPO_METADATA;

typedef struct _TDNF_EVENT_DATA_
{
    union
    {
        int nInt;
        const char *pcszStr;
        const void *pPtr;
    };
    TDNF_EVENT_ITEM_TYPE nType;
    const char *pcszName;
    struct _TDNF_EVENT_DATA_ *pNext;
} TDNF_EVENT_DATA;

typedef struct progress_cb_data {
    time_t cur_time;
    time_t prev_time;
    char pszData[64];
} pcb_data;

