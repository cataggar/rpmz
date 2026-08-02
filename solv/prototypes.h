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

/* The libsolv pool handle, incomplete on purpose. Unlike Repo it appears
   in no public header, so it is declared here rather than in tdnftypes.h:
   Pool is a generic enough name that leaking it into every consumer of
   <tdnf.h> would be a gratuitous compatibility hazard. The tag must match
   libsolv's own (pooltypes.h: `typedef struct s_Pool Pool;`) so that
   translation units seeing both get one identical typedef. */
typedef struct s_Pool Pool;

typedef struct _SolvSack
{
    Pool*       pPool;
    char*       pszCacheDir;
    char*       pszRootDir;
} SolvSack, *PSolvSack;

/* Opaque to every consumer except solv/, which alone can see the libsolv
   Queue the list carries. client/ reaches the contents through
   TDNFPkgListGetIds(). The definition is in solv/includes.h. */
typedef struct _SolvPackageList SolvPackageList, *PSolvPackageList;

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
    const int32_t* pIds,
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
    int32_t *pdwSolvableId
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
