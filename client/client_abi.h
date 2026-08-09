/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#pragma once

#include <tdnftypes.h>
#include <tdnfdownload.h>
#include <tdnfrepomd.h>
#include <tdnfrpmconfig.h>

#include "../rpmzig/rpmdb.h"

typedef struct _TDNF_ID_LIST TDNF_ID_LIST, *PTDNF_ID_LIST;

#include "package_context.h"
#include "transaction_plan_capture_abi.inc"
#include "structs.h"
#include "../llconf/nodes.h"

struct history_ctx;

uint32_t
TDNFNativeQueryBuildRepoInputs(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_REPO_INPUT *ppRepos,
    uint32_t *pdwRepoCount
    );

uint32_t
TDNFNativeQueryBuildSingleRepoInput(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepoData,
    TDNF_REPOMD_NATIVE_REPO_INPUT *pRepo
    );

void
TDNFNativeQueryFreeRepoInputs(
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos,
    uint32_t dwRepoCount
    );

const char *
TDNFNativeQueryInstallRoot(
    PTDNF pTdnf
    );

uint32_t
TDNFNativeQueryFilterUserInstalled(
    PTDNF pTdnf,
    PTDNF_PKG_INFO pPkgInfos,
    uint32_t *pdwCount
    );

uint32_t
TDNFNativeQueryApplyLocationUrls(
    PTDNF pTdnf,
    PTDNF_PKG_INFO pPkgInfos,
    uint32_t dwCount
    );

uint32_t
TDNFNativeQueryInstalledPkgIds(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueue
    );

uint32_t
TDNFNativeQuerySerializePackageId(
    PTDNF_PACKAGE_CONTEXT pSack,
    TDNF_PKG_ID dwPkgId,
    char **ppszLine
    );

uint32_t
TDNFNativeQuerySerializeQueuePackageRefs(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueue,
    char ***pppszRefs,
    uint32_t *pdwCount
    );

uint32_t
TDNFNativeQuerySerializePackageInfoRefs(
    PTDNF_PKG_INFO pPkgInfos,
    uint32_t dwCount,
    char ***pppszRefs,
    uint32_t *pdwCount
    );

uint32_t
TDNFNativeQuerySerializeAutoInstalledRefs(
    PTDNF pTdnf,
    struct history_ctx *pHistoryCtx,
    char ***pppszRefs,
    uint32_t *pdwCount
    );

uint32_t
TDNFNativeQueryResolvePackageRefArrayToQueue(
    PTDNF_PACKAGE_CONTEXT pSack,
    char **ppszPackageRefs,
    uint32_t dwCount,
    int nInstalledOnly,
    PTDNF_ID_LIST pQueue
    );

uint32_t
TDNFNativeQueryResolveSinglePackageRef(
    PTDNF_PACKAGE_CONTEXT pSack,
    const char *pszPackageRef,
    int nInstalledOnly,
    TDNF_PKG_ID *pdwPkgId
    );

uint32_t
TDNFNativeQuerySplitPackageRef(
    const char *pszRef,
    char **ppszRepo,
    uint32_t *pdwEpoch,
    char **ppszName,
    char **ppszVersion,
    char **ppszRelease,
    char **ppszArch
    );

uint32_t
TDNFNativeQueryBuildUpdateInfoSummary(
    char **ppszLines,
    uint32_t dwCount,
    PTDNF_UPDATEINFO_SUMMARY *ppSummary
    );

uint32_t
TDNFNativeQueryBuildUpdateInfo(
    char **ppszLines,
    uint32_t dwCount,
    PTDNF_UPDATEINFO *ppInfo
    );

uint32_t
TDNFAddPackagesForInstall(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char *pszPkgName,
    int nSource,
    int nInstallOnly
    );

uint32_t
TDNFMatchForReinstall(
    PTDNF_PACKAGE_CONTEXT pSack,
    const char *pszName,
    PTDNF_ID_LIST pQueueGoal
    );

uint32_t
TDNFPopulatePkgInfosFromRefs(
    PTDNF_PACKAGE_CONTEXT pSack,
    char **ppszPackageRefs,
    uint32_t dwRefCount,
    PTDNF_PKG_INFO *ppPkgInfo
    );

uint32_t
TDNFPkgInfoFilterNewest(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_PKG_INFO pPkgInfos
    );

uint32_t
TDNFAddPackagesForErase(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char *pszPkgName
    );

uint32_t
TDNFAddPackagesForUpgrade(
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char *pszPkgName
    );

uint32_t
TDNFAddPackagesForDowngrade(
    PTDNF pTdnf,
    PTDNF_PACKAGE_CONTEXT pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char *pszPkgName
    );

uint32_t
TDNFGetAvailableCacheBytes(
    PTDNF_CONF pConf,
    uint64_t *pqwAvailCacheBytes
    );

uint32_t
TDNFCheckDownloadCacheBytes(
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo,
    uint64_t qwAvailCacheBytes
    );

uint32_t
ReadGPGKeyFile(
    const char *pszFile,
    char **ppszKeyData,
    int *pnSize
    );

uint32_t
TDNFGPGCheckPackageEx(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszFilePath,
    tdnf_rpm_file **ppRpmFile,
    int *pnPolicyRejected
    );

uint32_t
TDNFGPGCheckPackageWithFile(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszFilePath,
    tdnf_rpm_file *pRpmFile,
    int *pnPolicyRejected
    );

uint32_t
TDNFFetchRemoteGPGKey(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszUrlGPGKey,
    char **ppszKeyLocation
    );

uint32_t
TDNFGetGPGKeys(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    char*** pppszUrlGPGKeys
    );

uint32_t
TDNFGetRepoMD(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepoData,
    const char *pszRepoDataDir,
    PTDNF_REPO_METADATA *ppRepoMD
    );

void
TDNFFreeRepoMetadata(
    PTDNF_REPO_METADATA pRepoMD
    );

uint32_t
TDNFDownloadMetadata(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszRepoDir,
    int nPrintOnly
    );

uint32_t
TDNFLoadRepoData(
    PTDNF pTdnf,
    PTDNF_REPO_DATA* ppReposAll
    );

uint32_t
TDNFRepoListFinalize(
    PTDNF pTdnf
    );

uint32_t
TDNFCloneRepo(
    PTDNF_REPO_DATA pRepoIn,
    PTDNF_REPO_DATA* ppRepo
    );

void
TDNFFreeReposInternal(
    PTDNF_REPO_DATA pRepos
    );
