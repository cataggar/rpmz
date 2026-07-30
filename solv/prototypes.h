/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define TDNF_ID_DEPENDS "tdnf:depends"
#define TDNF_ID_REQUIRES_PRE "tdnf:requires-pre"

typedef struct _SolvSack
{
    Pool*       pPool;
    uint32_t    dwNumOfCommandPkgs;
    char*       pszCacheDir;
    char*       pszRootDir;
} SolvSack, *PSolvSack;

typedef struct _SolvQuery
{
    PSolvSack   pSack;
    Queue       queueJob;
    Solver      *pSolv;
    Transaction *pTrans;
    Queue       queueRepoFilter;
    char**      ppszPackageNames;
    Queue       queueResult;
    uint32_t    dwNewPackages;
    TDNF_SCOPE  nScope;
} SolvQuery, *PSolvQuery;

typedef struct _SolvPackageList
{
    Queue       queuePackages;
} SolvPackageList, *PSolvPackageList;

typedef struct _SOLV_REPO_INFO_INTERNAL_
{
    Repo*         pRepo;
    unsigned char cookie[SOLV_COOKIE_LEN];
    int           nCookieSet;
    char          *pszRepoCacheDir;
}SOLV_REPO_INFO_INTERNAL, *PSOLV_REPO_INFO_INTERNAL;

// tdnfpackage.c
uint32_t
SolvGetPkgNameFromId(
    PSolvSack pSack,
    uint32_t dwPkgId,
    char** ppszName);

uint32_t
SolvGetPkgNevrFromId(
    PSolvSack pSack,
    uint32_t dwPkgId,
    char** ppszNevr);

uint32_t
SolvSplitEvr(
    const PSolvSack pSack,
    const char *pEVRstring,
    char **ppEpoch,
    char **ppVersion,
    char **ppLease);

uint32_t
SolvCmpEvr(
    PSolvSack pSack,
    Id dwPkg1,
    Id dwPkg2,
    int* pdwResult
    );

uint32_t
SolvCreatePackageList(
    PSolvPackageList* ppSolvPackageList
    );

void
SolvFreePackageList(
    PSolvPackageList pPkgList
    );

uint32_t
SolvQueueToPackageList(
    Queue* pQueue,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvGetPackageListSize(
    PSolvPackageList pPkgList,
    uint32_t* pdwSize
    );

uint32_t
SolvGetPackageId(
    PSolvPackageList pPkgList,
    uint32_t dwPkgIndex,
    Id* dwPkgId
    );

uint32_t
SolvFindAllInstalled(
    PSolvSack pSack,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvFindAvailablePkgByName(
    PSolvSack pSack,
    const char* pszName,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvFindAvailableSrcPkgByName(
    PSolvSack pSack,
    const char* pszName,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvFindInstalledPkgByName(
    PSolvSack pSack,
    const char* pszName,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvFindInstalledPkgByMultipleNames(
    PSolvSack pSack,
    char** ppszName,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvFindHighestAvailable(
    PSolvSack pSack,
    const char* pszPkgName,
    int nSource,
    Id* pdwId
    );

uint32_t
SolvFindLowestInstalled(
    PSolvSack pSack,
    const char* pszPkgName,
    Id* pdwId
    );

uint32_t
SolvFindHighestInstalled(
    PSolvSack pSack,
    const char* pszPkgName,
    Id* pdwId
    );

uint32_t
SolvFindHighestOrLowestInstalled(
    PSolvSack pSack,
    const char* pszPkgName,
    Id* pdwId,
    uint32_t dwFindHighest
    );

uint32_t
SolvGetNevraFromId(
    PSolvSack pSack,
    uint32_t dwPkgId,
    uint32_t *pdwEpoch,
    char **ppszName,
    char **ppszVersion,
    char **ppszRelease,
    char **ppszArch,
    char **ppszEVR
    );

// tdnfpool.c
uint32_t
SolvCreateSack(
    PSolvSack* ppSack
    );

void
SolvFreeSack(
    PSolvSack);

uint32_t
SolvCreatePool(Pool **ppPool);

uint32_t
SolvInitSack(
    PSolvSack *ppSack,
    const char* pszCacheDir,
    const char* pszRootDir,
    const char* pszArch
);

// tdnfquery.c
uint32_t
SolvCreateQuery(
    PSolvSack pSack,
    PSolvQuery* ppQuery
    );

void
SolvFreeQuery(
    PSolvQuery pQuery
    );

uint32_t
SolvApplyPackageFilter(
    PSolvQuery  pQuery,
    char** ppszPackageNames
    );

uint32_t
SolvApplySinglePackageFilter(
    PSolvQuery pQuery,
    const char* pszPackageName
    );

uint32_t
SolvApplyListQuery(
    PSolvQuery pQuery
    );

uint32_t
SolvGenerateCommonJob(
    PSolvQuery pQuery,
    uint32_t dwSelectFlags
    );

uint32_t
SolvAddSystemRepoFilter(
    PSolvQuery pQuery
    );

uint32_t
SolvAddAvailableRepoFilter(
    PSolvQuery pQuery
    );

uint32_t
SolvGetQueryResult(
    PSolvQuery pQuery,
    PSolvPackageList* ppPkgList
    );

uint32_t
SolvAddUpgradeAllJob(
    Queue* pQueueJobs
    );

uint32_t
SolvAddDistUpgradeJob(
    Queue* pQueueJobs
    );

uint32_t
SolvAddFlagsToJobs(
    Queue* pQueueJobs,
    int dwFlags
    );

uint32_t
SolvAddPkgInstallJob(
    Queue* pQueueJobs,
    Id dwId
    );

uint32_t
SolvAddPkgDowngradeJob(
    Queue* pQueueJobs,
    Id dwId
    );

uint32_t
SolvAddPkgEraseJob(
    Queue* pQueueJobs,
    Id dwId
    );

uint32_t
SolvAddUserInstalledToJobs(
    Queue* pQueueJobs,
    Pool *pPool,
    struct history_ctx *pHistoryCtx
    );

uint32_t
SolvFindAllUpDownCandidates(
    PSolvSack pSack,
    PSolvPackageList  pInstalledPackages,
    int up,
    Queue *pQueueResult
    );

// tdnfrepo.c
uint32_t
SolvReadYumRepo(
    Repo *pRepo,
    const char *pszRepoName,
    const char *pszRepomd,
    const char *pszPrimary,
    const char *pszFilelists,
    const char *pszUpdateinfo,
    const char *pszOther
    );

uint32_t
SolvReadYumRepoNative(
    Repo *pRepo,
    const char *pszRepomd,
    const char *pszPrimary,
    const char *pszFilelists,
    const char *pszUpdateinfo,
    const char *pszOther
    );

uint32_t
SolvCountPackages(
    PSolvSack pSack,
    uint32_t* pdwCount
    );

uint32_t
SolvReadRpmsFromDirectory(
    Repo *pRepo,
    const char *pszDir
);

uint32_t
SolvReadInstalledRpms(
    Repo* pRepo,
    const char *pszCacheFileName,
    const tdnf_rpm_config *pRpmConfig
);

uint32_t
SolvReadInstalledRpmsNative(
    Repo* pRepo,
    const char *pszRootDir,
    const tdnf_rpm_config *pRpmConfig,
    int dwFlags
    );

uint32_t
SolvAddRpmNative(
    Repo *pRepo,
    const char *pszPath,
    int dwFlags,
    Id *pdwSolvableId
    );

uint32_t
SolvReportProblems(
    PSolvSack pSack,
    Solver* pSolv,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
    );

uint32_t
SolvAddExcludes(
    Pool* pPool,
    char** ppszExcludes
    );

uint32_t
SolvDataIterator(
     Pool* pPool,
     char** ppszExcludes,
     Map* pMap
     );

int
SolvIsGlob(
    const char* pszString
    );

uint32_t
SolvGetMetaDataCachePath(
    PSOLV_REPO_INFO_INTERNAL pSolvRepoInfo,
    char** ppszCachePath
    );

uint32_t
SolvAddSolvMetaData(
    PSOLV_REPO_INFO_INTERNAL pSolvRepoInfo,
    const char *pszTempSolvFile
    );

uint32_t
SolvCreateMetaDataCache(
    PSolvSack pSack,
    PSOLV_REPO_INFO_INTERNAL pSolvRepoInfo
    );

uint32_t
SolvUseMetaDataCache(
    PSolvSack pSack,
    PSOLV_REPO_INFO_INTERNAL pSolvRepoInfo,
    int       *nUseMetaDataCache
    );

#ifdef __cplusplus
}
#endif
