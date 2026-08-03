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
SolvSackReadInstalledRpms(
    PSolvSack pSack,
    const char *pszCacheFileName,
    const tdnf_rpm_config *pRpmConfig
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

uint32_t
SolvGetRepoDataList(
    PSolvSack pSack,
    PTDNF_REPO_DATA **pppRepoData,
    uint32_t *pdwCount
    );

/*
 * Package-handle accessors. Every read of a field out of a
 * TDNF_PKG_ID goes through these, so the handle representation is
 * changeable in one place. Strings from TDNFPkgHandleGetFields are
 * borrowed from the sack; the NEVRA is allocated and owned by the
 * caller.
 */
uint32_t
TDNFPkgHandleGetFields(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    PTDNF_PKG_FIELDS pFields
    );


uint32_t
TDNFPkgHandleGetRepoNevra(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    const char **ppszRepo,
    char **ppszNevra
    );





/*
 * Queries over the installed set. They take a Pool rather than a sack
 * handle because that is what the job builders already hold; the name
 * says "Installed" rather than "Sack" so it does not promise otherwise.
 * An absent installed repo is reported as an error, never as an empty
 * set.
 */
uint32_t
TDNFInstalledGetPkgIds(
    Pool *pPool,
    PTDNF_ID_LIST pIdList
    );

/* Every package the sack knows about, the counterpart to
   TDNFInstalledGetPkgIds. Delegates to FOR_POOL_SOLVABLES, so the set
   and order are the macro's exactly. */
uint32_t
TDNFPoolGetPkgIds(
    Pool *pPool,
    PTDNF_ID_LIST pIdList
    );

/* Repo lifecycle. These hand back a Repo * the caller passes on without
   dereferencing; that plumbing goes away when Pool/Repo become opaque
   typedefs. */
uint32_t
TDNFPoolCreateRepo(
    Pool *pPool,
    const char *pszName,
    Repo **ppRepo
    );

/* Frees the repo and its solvables. Null-tolerant. */
void
TDNFRepoFree(
    Repo *pRepo
    );


