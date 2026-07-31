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
SolvSplitEvr(
    const PSolvSack pSack,
    const char *pEVRstring,
    char **ppEpoch,
    char **ppVersion,
    char **ppLease);

void
SolvFreePackageList(
    PSolvPackageList pPkgList
    );

uint32_t
SolvIdsToPackageList(
    const Id* pIds,
    uint32_t dwIdCount,
    PSolvPackageList* ppPkgList
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
SolvAddUserInstalledToJobs(
    PTDNF_ID_LIST pQueueJobs,
    Pool *pPool,
    struct history_ctx *pHistoryCtx
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
