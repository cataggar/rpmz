/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#define _GNU_SOURCE 1
#include "includes.h"

#define PACKAGEUTILS_NATIVE_REF_SEP ((char)0x1f)


static uint32_t
PackageUtilsBuildNativeRepoInputsFromSack(
    PSolvSack pSack,
    PTDNF_REPOMD_NATIVE_REPO_INPUT *ppRepos,
    uint32_t *pdwRepoCount
    );

static void
PackageUtilsFreeNativeRepoInputs(
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos,
    uint32_t dwRepoCount
    );

static uint32_t
PackageUtilsCreateRpmConfigFromSack(
    PSolvSack pSack,
    tdnf_rpm_config **ppConfig
    );

static uint32_t
PackageUtilsFindNativePackageRefs(
    PSolvSack pSack,
    const char *pszPkgName,
    TDNF_SCOPE nScope,
    char ***pppszPackageRefs,
    uint32_t *pdwCount
    );

static uint32_t
PackageUtilsFindHighestAvailableRef(
    PSolvSack pSack,
    const char *pszPkgName,
    int nSource,
    char **ppszPackageRef
    );

static uint32_t
PackageUtilsFindHighestOrLowestInstalledRef(
    PSolvSack pSack,
    const char *pszPkgName,
    uint32_t dwFindHighest,
    char **ppszPackageRef
    );

static uint32_t
PackageUtilsComparePackageRefsEvr(
    PSolvSack pSack,
    const char *pszLeftRef,
    const char *pszRightRef,
    int *pnResult
    );

static uint32_t
PackageUtilsGetPackageNameFromRef(
    PSolvSack pSack,
    const char *pszPackageRef,
    char **ppszName
    );

static uint32_t
PackageUtilsCopyNevraFromRef(
    const char *pszPackageRef,
    char **ppszNevra
    );

static uint32_t
PackageUtilsResolveSinglePackageRef(
    PSolvSack pSack,
    const char *pszPackageRef,
    int nInstalledOnly,
    TDNF_PKG_ID* pdwPkgId
    );

static uint32_t
PackageUtilsResolvePackageRefsToQueue(
    PSolvSack pSack,
    char **ppszPackageRefs,
    uint32_t dwCount,
    int nInstalledOnly,
    PTDNF_ID_LIST pQueueGoal
    );

static uint32_t
PackageUtilsPopulatePkgInfoFromRefs(
    PSolvSack pSack,
    char **ppszPackageRefs,
    uint32_t dwRefCount,
    TDNF_PKG_DETAIL nDetail,
    int nQueryFormat,
    uint32_t dwDependencyMask,
    int nFileList,
    int nChecksum,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
    );

static uint32_t
PackageUtilsPopulatePkgInfoFromPackageList(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    TDNF_PKG_DETAIL nDetail,
    int nQueryFormat,
    uint32_t dwDependencyMask,
    int nFileList,
    int nChecksum,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
    );

static int
_pkginfo_compare(
    const void *ptr1,
    const void *ptr2,
    void *data
    );

uint32_t
TDNFMatchForReinstall(
    PSolvSack pSack,
    const char* pszName,
    PTDNF_ID_LIST pQueueGoal
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID  dwAvailableId = 0;
    char *pszInstalledNevra = NULL;
    char **ppszInstalledRefs = NULL;
    char **ppszAvailableRefs = NULL;
    uint32_t dwInstalledCount = 0;
    uint32_t dwAvailableCount = 0;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindNativePackageRefs(
                  pSack,
                  pszName,
                  SCOPE_INSTALLED,
                  &ppszInstalledRefs,
                  &dwInstalledCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwInstalledCount == 0)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsCopyNevraFromRef(
                  ppszInstalledRefs[0],
                  &pszInstalledNevra);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsFindNativePackageRefs(
                  pSack,
                  pszInstalledNevra,
                  SCOPE_AVAILABLE,
                  &ppszAvailableRefs,
                  &dwAvailableCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwAvailableCount == 0)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsResolveSinglePackageRef(
                  pSack,
                  ppszAvailableRefs[0],
                  0,
                  &dwAvailableId);
    BAIL_ON_TDNF_ERROR(dwError);


    dwError = TDNFIdListPush(pQueueGoal, dwAvailableId);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszInstalledNevra);
    TDNFFreeStringArray(ppszAvailableRefs);
    TDNFFreeStringArray(ppszInstalledRefs);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPopulatePkgInfoQueryFormat(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount
    )
{
    return PackageUtilsPopulatePkgInfoFromPackageList(
               pSack,
               pPkgList,
               DETAIL_LIST,
               1,
               0,
               0,
               0,
               ppPkgInfo,
               pdwCount);
}

uint32_t
TDNFPopulatePkgInfoArray(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    TDNF_PKG_DETAIL nDetail,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount
    )
{
    return PackageUtilsPopulatePkgInfoFromPackageList(
               pSack,
               pPkgList,
               nDetail,
               0,
               0,
               0,
               0,
               ppPkgInfo,
               pdwCount);
}

uint32_t
TDNFPopulatePkgInfoForRepoSync(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    PTDNF_PKG_INFO* ppPkgInfo
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;

    if(!ppPkgInfo || !pSack || !pPkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsPopulatePkgInfoFromPackageList(
                  pSack,
                  pPkgList,
                  DETAIL_LOCATION,
                  0,
                  0,
                  0,
                  0,
                  &pPkgInfos,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfo = pPkgInfos;

cleanup:
    return dwError;

error:
    if(ppPkgInfo)
    {
        *ppPkgInfo = NULL;
    }
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwCount);
    }
    goto cleanup;
}

uint32_t
TDNFPkgInfoFilterNewest(
    PSolvSack pSack,
    PTDNF_PKG_INFO pPkgInfos
)
{
    uint32_t dwError = 0;
    uint32_t dwCount, i;
    PTDNF_PKG_INFO* ppPkgInfos = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;

    dwCount = 0;
    for (pPkgInfo = pPkgInfos; pPkgInfo; pPkgInfo = pPkgInfo->pNext)
    {
        dwCount++;
    }

    dwError = TDNFAllocateMemory(
                  dwCount,
                  sizeof(PTDNF_PKG_INFO),
                  (void**)&ppPkgInfos);
    BAIL_ON_TDNF_ERROR(dwError);

    i = 0;
    for (pPkgInfo = pPkgInfos; pPkgInfo; pPkgInfo = pPkgInfo->pNext)
    {
        ppPkgInfos[i++] = pPkgInfo;
    }

    (void)pSack;
    qsort_r(ppPkgInfos, dwCount,
            sizeof(PTDNF_PKG_INFO), _pkginfo_compare, NULL);

    /* Loop though pointer array, use the linked list to skip over
       older versions of the same packages. The linked list will only
       touch the newest (first) version of a package.
       The same package in different repos will be handled as two different
       packages. */
    pPkgInfo = ppPkgInfos[0];
    for (i = 1; i < dwCount; i++)
    {
        if ((strcmp(ppPkgInfos[i]->pszRepoName, pPkgInfo->pszRepoName) != 0) ||
            (strcmp(ppPkgInfos[i]->pszName, pPkgInfo->pszName) != 0))
        {
            pPkgInfo->pNext = ppPkgInfos[i];
            pPkgInfo = ppPkgInfos[i];
            pPkgInfo->pNext = NULL;
        }
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(ppPkgInfos);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPackageGetDowngrade(
    PTDNF pTdnf,
    TDNF_PKG_ID dwInstalled,
    PSolvSack pSack,
    PSolvPackageList pAvailabePkgList,
    TDNF_PKG_ID* pdwDowngradePkgId
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID dwDownGradeId = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    char *pszInstalledRef = NULL;
    char **ppszMatches = NULL;
    uint32_t dwMatchCount = 0;

    if(!pTdnf || !pSack || !pdwDowngradePkgId)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    (void)pAvailabePkgList;

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQuerySerializePackageId(pSack, dwInstalled, &pszInstalledRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeDowngradeCandidateLines(
                  pRepos,
                  dwRepoCount,
                  TDNFNativeQueryInstallRoot(pTdnf),
                  pTdnf->pConf->ppszMinVersions,
                  pszInstalledRef,
                  &ppszMatches,
                  &dwMatchCount);
    if(dwError == ERROR_TDNF_NO_DATA)
    {
        dwError = ERROR_TDNF_NO_DOWNGRADE_PATH;
    }
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwMatchCount != 1)
    {
        dwError = ERROR_TDNF_NO_DOWNGRADE_PATH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQueryResolveSinglePackageRef(
                  pSack,
                  ppszMatches[0],
                  0,
                  &dwDownGradeId);
    BAIL_ON_TDNF_ERROR(dwError);

    *pdwDowngradePkgId = dwDownGradeId;
cleanup:
    TDNFFreeStringArray(ppszMatches);
    TDNF_SAFE_FREE_MEMORY(pszInstalledRef);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    if(pdwDowngradePkgId)
    {
        *pdwDowngradePkgId = 0;
    }
    goto cleanup;
}

uint32_t
TDNFGetGlobPackages(
    PSolvSack pSack,
    char* pszPkgGlob,
    int nIsInstalled,
    PTDNF_ID_LIST pQueueGoal
    )
{
    uint32_t dwError = 0;
    char **ppszPackageRefs = NULL;
    uint32_t dwCount = 0;

    if(!pSack || IsNullOrEmptyString(pszPkgGlob) || !pQueueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindNativePackageRefs(
                  pSack,
                  pszPkgGlob,
                  nIsInstalled ? SCOPE_INSTALLED : SCOPE_AVAILABLE,
                  &ppszPackageRefs,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsResolvePackageRefsToQueue(
                  pSack,
                  ppszPackageRefs,
                  dwCount,
                  nIsInstalled,
                  pQueueGoal);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFFreeStringArray(ppszPackageRefs);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFAddPackagesForErase(
    PSolvSack pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    char **ppszInstalledRefs = NULL;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindNativePackageRefs(
                  pSack,
                  pszPkgName,
                  SCOPE_INSTALLED,
                  &ppszInstalledRefs,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsResolvePackageRefsToQueue(
                  pSack,
                  ppszInstalledRefs,
                  dwCount,
                  1,
                  pQueueGoal);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFFreeStringArray(ppszInstalledRefs);
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFVerifyInstallPackage(
    PSolvSack pSack,
    TDNF_PKG_ID dwPkg,
    uint32_t* pdwInstallPackage
    )
{

    uint32_t dwError = 0;
    char *pszName = NULL;
    char *pszPackageRef = NULL;
    char *pszInstalledRef = NULL;
    int dwEvrCompare = 0;
    uint32_t dwInstallPackage = 0;

    if(!pSack || !pdwInstallPackage)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQuerySerializePackageId(
                  pSack,
                  dwPkg,
                  &pszPackageRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsGetPackageNameFromRef(
                  pSack,
                  pszPackageRef,
                  &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsFindHighestOrLowestInstalledRef(
                  pSack,
                  pszName,
                  1,
                  &pszInstalledRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsComparePackageRefsEvr(
                  pSack,
                  pszPackageRef,
                  pszInstalledRef,
                  &dwEvrCompare);
    BAIL_ON_TDNF_ERROR(dwError);

    //allow updates and downgrades with install
    //install could specify version
    if(dwEvrCompare)
    {
        dwInstallPackage = 1;
    }

    *pdwInstallPackage = dwInstallPackage;
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszInstalledRef);
    TDNF_SAFE_FREE_MEMORY(pszPackageRef);
    TDNF_SAFE_FREE_MEMORY(pszName);
    return dwError;

error:
    if((dwError == ERROR_TDNF_NO_MATCH || dwError == ERROR_TDNF_NO_DATA) &&
       pdwInstallPackage)
    {
        *pdwInstallPackage = 1;
        dwError = 0;
    }
    goto cleanup;
}


uint32_t
TDNFAddPackagesForInstall(
    PSolvSack pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char* pszPkgName,
    int nSource,
    int nInstallOnly
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID dwHighestAvailable = 0;
    uint32_t  dwInstallPackage = 0;
    char *pszHighestAvailableRef = NULL;
    char *pszInstalledRef = NULL;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindHighestAvailableRef(
                  pSack,
                  pszPkgName,
                  nSource,
                  &pszHighestAvailableRef);
    if(!nSource &&
       (dwError == ERROR_TDNF_NO_MATCH || dwError == ERROR_TDNF_NO_DATA))
    {
        dwError = PackageUtilsFindHighestOrLowestInstalledRef(
                      pSack,
                      pszPkgName,
                      1,
                      &pszInstalledRef);
        if(dwError == 0)
        {
            dwError = ERROR_TDNF_ALREADY_INSTALLED;
        }
    }
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsResolveSinglePackageRef(
                  pSack,
                  pszHighestAvailableRef,
                  0,
                  &dwHighestAvailable);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFVerifyInstallPackage(
                  pSack,
                  dwHighestAvailable,
                  &dwInstallPackage);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwInstallPackage == 1 || nInstallOnly || nSource)
    {
        dwError = TDNFIdListPush(pQueueGoal, dwHighestAvailable);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else
    {
        dwError = ERROR_TDNF_ALREADY_INSTALLED;
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszInstalledRef);
    TDNF_SAFE_FREE_MEMORY(pszHighestAvailableRef);
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFVerifyUpgradePackage(
    PSolvSack pSack,
    TDNF_PKG_ID dwPkg,
    uint32_t* pdwUpgradePackage
    )
{

    uint32_t dwError = 0;
    char *pszName = NULL;
    char *pszPackageRef = NULL;
    char *pszInstalledRef = NULL;
    int dwEvrCompare = 0;
    uint32_t dwUpgradePackage = 0;

    if(!pSack || !pdwUpgradePackage)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQuerySerializePackageId(
                  pSack,
                  dwPkg,
                  &pszPackageRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsGetPackageNameFromRef(
                  pSack,
                  pszPackageRef,
                  &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsFindHighestOrLowestInstalledRef(
                  pSack,
                  pszName,
                  1,
                  &pszInstalledRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsComparePackageRefsEvr(
                  pSack,
                  pszPackageRef,
                  pszInstalledRef,
                  &dwEvrCompare);
    if(dwError == 0 && dwEvrCompare > 0)
    {
        dwUpgradePackage = 1;
    }
    else
    {
        dwUpgradePackage = 0;
    }
    *pdwUpgradePackage = dwUpgradePackage;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszInstalledRef);
    TDNF_SAFE_FREE_MEMORY(pszPackageRef);
    TDNF_SAFE_FREE_MEMORY(pszName);
    return dwError;

error:
    if(pdwUpgradePackage)
    {
        *pdwUpgradePackage = 0;
    }
    goto cleanup;
}
uint32_t
TDNFAddPackagesForUpgrade(
    PSolvSack pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID dwHighestAvailable = 0;
    uint32_t  dwUpgradePackage = 0;
    char *pszHighestAvailableRef = NULL;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindHighestAvailableRef(
                  pSack,
                  pszPkgName,
                  0,
                  &pszHighestAvailableRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsResolveSinglePackageRef(
                  pSack,
                  pszHighestAvailableRef,
                  0,
                  &dwHighestAvailable);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFVerifyUpgradePackage(
                  pSack,
                  dwHighestAvailable,
                  &dwUpgradePackage);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwUpgradePackage == 1)
    {
        dwError = TDNFIdListPush(pQueueGoal, dwHighestAvailable);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszHighestAvailableRef);
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFAddPackagesForDowngrade(
    PTDNF pTdnf,
    PSolvSack pSack,
    PTDNF_ID_LIST pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID dwInstalledId = 0;
    TDNF_PKG_ID dwDownGradeId = 0;
    char *pszName = NULL;
    char *pszInstalledRef = NULL;
    char **ppszAvailableRefs = NULL;
    uint32_t dwAvailableCount = 0;

    if(!pTdnf || !pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsFindNativePackageRefs(
                  pSack,
                  pszPkgName,
                  SCOPE_AVAILABLE,
                  &ppszAvailableRefs,
                  &dwAvailableCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwAvailableCount == 0)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsGetPackageNameFromRef(
                  pSack,
                  ppszAvailableRefs[0],
                  &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsFindHighestOrLowestInstalledRef(
                  pSack,
                  pszName,
                  0,
                  &pszInstalledRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsResolveSinglePackageRef(
                  pSack,
                  pszInstalledRef,
                  1,
                  &dwInstalledId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFPackageGetDowngrade(
                  pTdnf,
                  dwInstalledId,
                  pSack,
                  NULL,
                  &dwDownGradeId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFIdListPush(pQueueGoal, dwDownGradeId);
    BAIL_ON_TDNF_ERROR(dwError);
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszInstalledRef);
    TDNF_SAFE_FREE_MEMORY(pszName);
    TDNFFreeStringArray(ppszAvailableRefs);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFGetAvailableCacheBytes(
    PTDNF_CONF pConf,
    uint64_t* pqwAvailCacheDirBytes
    )
{
    uint32_t dwError = 0;
    struct statfs stfs = {0};
    struct stat st = {0};

    if(!pConf || !pConf->pszCacheDir || !pqwAvailCacheDirBytes)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (stat(pConf->pszCacheDir, &st) != 0) {
        /* avoid failure when checking space, and dir doesn't exist */
        dwError = TDNFUtilsMakeDirs(pConf->pszCacheDir);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (statfs(pConf->pszCacheDir, &stfs) != 0)
    {
        dwError = errno;
        BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
    }

    *pqwAvailCacheDirBytes = stfs.f_bsize * stfs.f_bavail;

cleanup:
    return dwError;

error:
    if(pqwAvailCacheDirBytes)
    {
        *pqwAvailCacheDirBytes = 0;
    }
    goto cleanup;
}

uint32_t
TDNFCheckDownloadCacheBytes(
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo,
    uint64_t qwAvailCacheBytes
    )
{
    uint32_t dwError = 0;
    uint64_t qwTotalDownloadSizeBytes = 0;
    uint8_t byPkgIndex = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;

    PTDNF_PKG_INFO ppPkgsNeedDownload[4] = {
        pSolvedPkgInfo->pPkgsToInstall,
        pSolvedPkgInfo->pPkgsToDowngrade,
        pSolvedPkgInfo->pPkgsToUpgrade,
        pSolvedPkgInfo->pPkgsToReinstall
    };

    if(!pSolvedPkgInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        /* coverity[name_at_decl_position] */
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for (byPkgIndex = 0; byPkgIndex < ARRAY_SIZE(ppPkgsNeedDownload); byPkgIndex++)
    {
        pPkgInfo = ppPkgsNeedDownload[byPkgIndex];
        while(pPkgInfo) {
            qwTotalDownloadSizeBytes += pPkgInfo->dwDownloadSizeBytes;
            if (qwTotalDownloadSizeBytes > qwAvailCacheBytes)
            {
                dwError = ERROR_TDNF_CACHE_DIR_OUT_OF_DISK_SPACE;
                BAIL_ON_TDNF_ERROR(dwError);
            }
            pPkgInfo = pPkgInfo->pNext;
        }
    }

error:
    return dwError;
}

uint32_t
TDNFPopulatePkgInfos(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    PTDNF_PKG_INFO* ppPkgInfos
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwPkgIndex = 0;
    PTDNF_PKG_INFO pPkgInfoArray = NULL;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;

    if(!ppPkgInfos || !pSack || !pPkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsPopulatePkgInfoFromPackageList(
                  pSack,
                  pPkgList,
                  DETAIL_LIST,
                  1,
                  0,
                  0,
                  1,
                  &pPkgInfoArray,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    for (dwPkgIndex = 0; dwPkgIndex < dwCount; dwPkgIndex++)
    {
        dwError = TDNFAllocateMemory(
                      1,
                      sizeof(TDNF_PKG_INFO),
                      (void**)&pPkgInfo);
        BAIL_ON_TDNF_ERROR(dwError);

        *pPkgInfo = pPkgInfoArray[dwPkgIndex];
        memset(&pPkgInfoArray[dwPkgIndex], 0, sizeof(TDNF_PKG_INFO));
        pPkgInfo->pNext = pPkgInfos;
        pPkgInfos = pPkgInfo;
        pPkgInfo = NULL;
    }

    *ppPkgInfos = pPkgInfos;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pPkgInfoArray);
    return dwError;

error:

    if(ppPkgInfos)
    {
        *ppPkgInfos = NULL;
    }
    if (pPkgInfos)
    {
        TDNFFreePackageInfo(pPkgInfos);
    }
    if (pPkgInfoArray)
    {
        TDNFFreePackageInfoArray(pPkgInfoArray, dwCount);
        pPkgInfoArray = NULL;
    }
    if (pPkgInfo)
    {
        TDNFFreePackageInfo(pPkgInfo);
    }
    goto cleanup;
}

uint32_t
TDNFPopulatePkgInfoArrayDependencies(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    REPOQUERY_DEP_KEY depKey,
    PTDNF_PKG_INFO pPkgInfos
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwPkgIndex = 0;
    uint32_t dwNativeCount = 0;
    uint32_t dwDependencyMask = 0;
    PTDNF_PKG_INFO pNativePkgInfos = NULL;

    if(!pPkgInfos || !pSack || !pPkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwDependencyMask = 1u << depKey;
    dwError = PackageUtilsPopulatePkgInfoFromPackageList(
                  pSack,
                  pPkgList,
                  DETAIL_LIST,
                  0,
                  dwDependencyMask,
                  0,
                  0,
                  &pNativePkgInfos,
                  &dwNativeCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwCount = dwNativeCount;

    for (dwPkgIndex = 0; dwPkgIndex < dwCount; dwPkgIndex++)
    {
        pPkgInfos[dwPkgIndex].pppszDependencies =
            pNativePkgInfos[dwPkgIndex].pppszDependencies;
        pNativePkgInfos[dwPkgIndex].pppszDependencies = NULL;
    }

cleanup:
    if(pNativePkgInfos)
    {
        TDNFFreePackageInfoArray(pNativePkgInfos, dwNativeCount);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPopulatePkgInfoArrayFileList(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    PTDNF_PKG_INFO pPkgInfos
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwPkgIndex = 0;
    uint32_t dwNativeCount = 0;
    PTDNF_PKG_INFO pNativePkgInfos = NULL;

    if(!pPkgInfos || !pSack || !pPkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsPopulatePkgInfoFromPackageList(
                  pSack,
                  pPkgList,
                  DETAIL_LIST,
                  0,
                  0,
                  1,
                  0,
                  &pNativePkgInfos,
                  &dwNativeCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwCount = dwNativeCount;

    for (dwPkgIndex = 0; dwPkgIndex < dwCount; dwPkgIndex++)
    {
        pPkgInfos[dwPkgIndex].ppszFileList =
            pNativePkgInfos[dwPkgIndex].ppszFileList;
        pNativePkgInfos[dwPkgIndex].ppszFileList = NULL;
    }

cleanup:
    if(pNativePkgInfos)
    {
        TDNFFreePackageInfoArray(pNativePkgInfos, dwNativeCount);
    }
    return dwError;

error:
    goto cleanup;
}

static uint32_t
PackageUtilsBuildNativeRepoInputsFromSack(
    PSolvSack pSack,
    PTDNF_REPOMD_NATIVE_REPO_INPUT *ppRepos,
    uint32_t *pdwRepoCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;
    uint32_t dwRepoDataCount = 0;
    uint32_t dwRepoDataIndex = 0;
    PTDNF_REPO_DATA *ppRepoData = NULL;
    PTDNF_REPO_DATA pRepoData = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;

    if(!pSack || !ppRepos || !pdwRepoCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* Which repos the sack holds is its business; which of them are worth
       handing to the native reader is this file's. */
    dwError = SolvGetRepoDataList(pSack, &ppRepoData, &dwRepoDataCount);
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwRepoDataIndex = 0;
        dwRepoDataIndex < dwRepoDataCount;
        dwRepoDataIndex++)
    {
        pRepoData = ppRepoData[dwRepoDataIndex];
        if(pRepoData && pRepoData->nEnabled && pRepoData->nHasMetaData &&
           !IsNullOrEmptyString(pRepoData->pszId))
        {
            dwCount++;
        }
    }

    if(!dwCount)
    {
        goto cleanup;
    }

    if(IsNullOrEmptyString(pSack->pszCacheDir))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  dwCount,
                  sizeof(TDNF_REPOMD_NATIVE_REPO_INPUT),
                  (void **)&pRepos);
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwRepoDataIndex = 0;
        dwRepoDataIndex < dwRepoDataCount;
        dwRepoDataIndex++)
    {
        const char *pszCacheName = NULL;

        pRepoData = ppRepoData[dwRepoDataIndex];
        if(!pRepoData || !pRepoData->nEnabled || !pRepoData->nHasMetaData ||
           IsNullOrEmptyString(pRepoData->pszId))
        {
            continue;
        }

        pszCacheName = pRepoData->pszCacheName ?
                       pRepoData->pszCacheName : pRepoData->pszId;
        dwError = TDNFJoinPath(
                      (char **)&pRepos[dwIndex].pszCacheDir,
                      pSack->pszCacheDir,
                      pszCacheName,
                      NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        pRepos[dwIndex].pszId = pRepoData->pszId;
        pRepos[dwIndex].pszSnapshotFile = pRepoData->pszSnapshotFile;
        dwIndex++;
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(ppRepoData);
    if(ppRepos)
    {
        *ppRepos = pRepos;
    }
    if(pdwRepoCount)
    {
        *pdwRepoCount = dwIndex;
    }
    return dwError;

error:
    PackageUtilsFreeNativeRepoInputs(pRepos, dwCount);
    pRepos = NULL;
    dwIndex = 0;
    goto cleanup;
}

static void
PackageUtilsFreeNativeRepoInputs(
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos,
    uint32_t dwRepoCount
    )
{
    uint32_t dwIndex = 0;

    if(!pRepos)
    {
        return;
    }

    for(dwIndex = 0; dwIndex < dwRepoCount; dwIndex++)
    {
        char *pszCacheDir = (char *)pRepos[dwIndex].pszCacheDir;
        TDNF_SAFE_FREE_MEMORY(pszCacheDir);
        pRepos[dwIndex].pszCacheDir = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pRepos);
}

static uint32_t
PackageUtilsCreateRpmConfigFromSack(
    PSolvSack pSack,
    tdnf_rpm_config **ppConfig
    )
{
    uint32_t dwError = 0;
    const char *pszRootDir = NULL;
    tdnf_rpm_config *pConfig = NULL;

    if(!pSack || !ppConfig)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszRootDir = IsNullOrEmptyString(pSack->pszRootDir) ?
                 "/" : pSack->pszRootDir;
    pConfig = tdnf_rpm_config_create(pszRootDir);
    if(!pConfig)
    {
        dwError = ERROR_TDNF_OUT_OF_MEMORY;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppConfig = pConfig;

cleanup:
    return dwError;

error:
    if(ppConfig)
    {
        *ppConfig = NULL;
    }
    tdnf_rpm_config_destroy(pConfig);
    goto cleanup;
}

static uint32_t
PackageUtilsFindNativePackageRefs(
    PSolvSack pSack,
    const char *pszPkgName,
    TDNF_SCOPE nScope,
    char ***pppszPackageRefs,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwRepoCount = 0;
    uint32_t dwCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    tdnf_rpm_config *pConfig = NULL;
    char **ppszPackageRefs = NULL;

    if(!pSack || IsNullOrEmptyString(pszPkgName) || !pppszPackageRefs || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsBuildNativeRepoInputsFromSack(
                  pSack,
                  &pRepos,
                  &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsCreateRpmConfigFromSack(pSack, &pConfig);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativePackageRefLinesConfig(
                  pRepos,
                  dwRepoCount,
                  pConfig,
                  nScope,
                  pszPkgName,
                  &ppszPackageRefs,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *pppszPackageRefs = ppszPackageRefs;
    *pdwCount = dwCount;

cleanup:
    tdnf_rpm_config_destroy(pConfig);
    PackageUtilsFreeNativeRepoInputs(pRepos, dwRepoCount);
    return dwError;

error:
    if(pppszPackageRefs)
    {
        *pppszPackageRefs = NULL;
    }
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    TDNFFreeStringArray(ppszPackageRefs);
    goto cleanup;
}

static uint32_t
PackageUtilsFindHighestAvailableRef(
    PSolvSack pSack,
    const char *pszPkgName,
    int nSource,
    char **ppszPackageRef
    )
{
    uint32_t dwError = 0;
    uint32_t dwRepoCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    tdnf_rpm_config *pConfig = NULL;
    char *pszPackageRef = NULL;

    if(!pSack || IsNullOrEmptyString(pszPkgName) || !ppszPackageRef)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsBuildNativeRepoInputsFromSack(
                  pSack,
                  &pRepos,
                  &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsCreateRpmConfigFromSack(pSack, &pConfig);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeBestPackageRefConfig(
                  pRepos,
                  dwRepoCount,
                  pConfig,
                  SCOPE_AVAILABLE,
                  pszPkgName,
                  nSource,
                  1,
                  &pszPackageRef);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszPackageRef = pszPackageRef;
    pszPackageRef = NULL;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszPackageRef);
    tdnf_rpm_config_destroy(pConfig);
    PackageUtilsFreeNativeRepoInputs(pRepos, dwRepoCount);
    return dwError;

error:
    if(ppszPackageRef)
    {
        *ppszPackageRef = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszPackageRef);
    goto cleanup;
}

static uint32_t
PackageUtilsFindHighestOrLowestInstalledRef(
    PSolvSack pSack,
    const char *pszPkgName,
    uint32_t dwFindHighest,
    char **ppszPackageRef
    )
{
    uint32_t dwError = 0;
    uint32_t dwRepoCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    tdnf_rpm_config *pConfig = NULL;
    char *pszPackageRef = NULL;

    if(!pSack || IsNullOrEmptyString(pszPkgName) || !ppszPackageRef)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsBuildNativeRepoInputsFromSack(
                  pSack,
                  &pRepos,
                  &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsCreateRpmConfigFromSack(pSack, &pConfig);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeBestPackageRefConfig(
                  pRepos,
                  dwRepoCount,
                  pConfig,
                  SCOPE_INSTALLED,
                  pszPkgName,
                  0,
                  dwFindHighest,
                  &pszPackageRef);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszPackageRef = pszPackageRef;
    pszPackageRef = NULL;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszPackageRef);
    tdnf_rpm_config_destroy(pConfig);
    PackageUtilsFreeNativeRepoInputs(pRepos, dwRepoCount);
    return dwError;

error:
    if(ppszPackageRef)
    {
        *ppszPackageRef = NULL;
    }
    goto cleanup;
}

static uint32_t
PackageUtilsComparePackageRefsEvr(
    PSolvSack pSack,
    const char *pszLeftRef,
    const char *pszRightRef,
    int *pnResult
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    char *ppszRefs[3] = {(char *)pszLeftRef, (char *)pszRightRef, NULL};

    if(!pSack || IsNullOrEmptyString(pszLeftRef) ||
       IsNullOrEmptyString(pszRightRef) || !pnResult)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsPopulatePkgInfoFromRefs(
                  pSack,
                  ppszRefs,
                  2,
                  DETAIL_LIST,
                  0,
                  0,
                  0,
                  0,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwCount != 2)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdNativeCompareEvr(
                  pPkgInfo[0].pszEVR,
                  pPkgInfo[1].pszEVR,
                  pnResult);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    if(pPkgInfo)
    {
        TDNFFreePackageInfoArray(pPkgInfo, dwCount);
    }
    return dwError;

error:
    if(pnResult)
    {
        *pnResult = 0;
    }
    goto cleanup;
}

static uint32_t
PackageUtilsGetPackageNameFromRef(
    PSolvSack pSack,
    const char *pszPackageRef,
    char **ppszName
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    char *pszName = NULL;
    char *ppszRefs[2] = {(char *)pszPackageRef, NULL};

    if(!pSack || IsNullOrEmptyString(pszPackageRef) || !ppszName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsPopulatePkgInfoFromRefs(
                  pSack,
                  ppszRefs,
                  1,
                  DETAIL_LIST,
                  0,
                  0,
                  0,
                  0,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwCount != 1 || IsNullOrEmptyString(pPkgInfo[0].pszName))
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pPkgInfo[0].pszName, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszName = pszName;

cleanup:
    if(pPkgInfo)
    {
        TDNFFreePackageInfoArray(pPkgInfo, dwCount);
    }
    return dwError;

error:
    if(ppszName)
    {
        *ppszName = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszName);
    goto cleanup;
}

static uint32_t
PackageUtilsCopyNevraFromRef(
    const char *pszPackageRef,
    char **ppszNevra
    )
{
    uint32_t dwError = 0;
    const char *pszNevra = NULL;
    char *pszNevraCopy = NULL;

    if(IsNullOrEmptyString(pszPackageRef) || !ppszNevra)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszNevra = strchr(pszPackageRef, PACKAGEUTILS_NATIVE_REF_SEP);
    if(!pszNevra || IsNullOrEmptyString(pszNevra + 1))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    pszNevra++;

    dwError = TDNFAllocateString(pszNevra, &pszNevraCopy);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszNevra = pszNevraCopy;

cleanup:
    return dwError;

error:
    if(ppszNevra)
    {
        *ppszNevra = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszNevraCopy);
    goto cleanup;
}

static uint32_t
PackageUtilsResolveSinglePackageRef(
    PSolvSack pSack,
    const char *pszPackageRef,
    int nInstalledOnly,
    TDNF_PKG_ID* pdwPkgId
    )
{
    uint32_t dwError = 0;

    if(!pSack || IsNullOrEmptyString(pszPackageRef) || !pdwPkgId)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQueryResolveSinglePackageRef(
                  pSack,
                  pszPackageRef,
                  nInstalledOnly,
                  pdwPkgId);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    if(pdwPkgId)
    {
        *pdwPkgId = 0;
    }
    goto cleanup;
}

static uint32_t
PackageUtilsResolvePackageRefsToQueue(
    PSolvSack pSack,
    char **ppszPackageRefs,
    uint32_t dwCount,
    int nInstalledOnly,
    PTDNF_ID_LIST pQueueGoal
    )
{
    uint32_t dwError = 0;

    if(!pSack || !ppszPackageRefs || !pQueueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if(dwCount == 0)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQueryResolvePackageRefArrayToQueue(
                  pSack,
                  ppszPackageRefs,
                  dwCount,
                  nInstalledOnly,
                  pQueueGoal);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    goto cleanup;
}

static uint32_t
PackageUtilsPopulatePkgInfoFromRefs(
    PSolvSack pSack,
    char **ppszPackageRefs,
    uint32_t dwRefCount,
    TDNF_PKG_DETAIL nDetail,
    int nQueryFormat,
    uint32_t dwDependencyMask,
    int nFileList,
    int nChecksum,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwRepoCount = 0;
    uint32_t dwCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    tdnf_rpm_config *pConfig = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;

    if(!pSack || !ppszPackageRefs || !ppPkgInfo || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if(!dwRefCount)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = PackageUtilsBuildNativeRepoInputsFromSack(
                  pSack,
                  &pRepos,
                  &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsCreateRpmConfigFromSack(pSack, &pConfig);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativePackageInfoForRefsConfig(
                  pRepos,
                  dwRepoCount,
                  pConfig,
                  ppszPackageRefs,
                  nDetail,
                  nQueryFormat,
                  dwDependencyMask,
                  nFileList,
                  nChecksum,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfo = pPkgInfo;
    *pdwCount = dwCount;

cleanup:
    tdnf_rpm_config_destroy(pConfig);
    PackageUtilsFreeNativeRepoInputs(pRepos, dwRepoCount);
    return dwError;

error:
    if(ppPkgInfo)
    {
        *ppPkgInfo = NULL;
    }
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    if(pPkgInfo)
    {
        TDNFFreePackageInfoArray(pPkgInfo, dwCount);
    }
    goto cleanup;
}

static uint32_t
PackageUtilsPopulatePkgInfoFromPackageList(
    PSolvSack pSack,
    PSolvPackageList pPkgList,
    TDNF_PKG_DETAIL nDetail,
    int nQueryFormat,
    uint32_t dwDependencyMask,
    int nFileList,
    int nChecksum,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    char **ppszPackageRefs = NULL;

    if(!pSack || !pPkgList || !ppPkgInfo || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQuerySerializePackageListRefs(
                  pSack,
                  pPkgList,
                  &ppszPackageRefs,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = PackageUtilsPopulatePkgInfoFromRefs(
                  pSack,
                  ppszPackageRefs,
                  dwCount,
                  nDetail,
                  nQueryFormat,
                  dwDependencyMask,
                  nFileList,
                  nChecksum,
                  ppPkgInfo,
                  pdwCount);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFFreeStringArray(ppszPackageRefs);
    return dwError;

error:
    if(ppPkgInfo)
    {
        *ppPkgInfo = NULL;
    }
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    goto cleanup;
}

static
int _pkginfo_compare(
        const void *ptr1,
        const void *ptr2,
        void *data
    )
{
    const PTDNF_PKG_INFO* ppPkgInfo1 = (PTDNF_PKG_INFO*)ptr1;
    const PTDNF_PKG_INFO* ppPkgInfo2 = (PTDNF_PKG_INFO*)ptr2;
    int nCompare = 0;
    int ret;

    (void)data;

    /* sort by repo name first, then name, then version */
    ret = strcmp((*ppPkgInfo1)->pszRepoName, (*ppPkgInfo2)->pszRepoName);
    if (ret != 0)
    {
        return ret;
    }
    ret = strcmp((*ppPkgInfo1)->pszName, (*ppPkgInfo2)->pszName);
    if (ret != 0)
    {
        return ret;
    }

    /* we want newest version first, so reverse it by using the negated value */
    if(TDNFRepoMdNativeCompareEvr(
           (*ppPkgInfo1)->pszEVR,
           (*ppPkgInfo2)->pszEVR,
           &nCompare) == 0)
    {
        ret = -nCompare;
    }
    else
    {
        ret = 0;
    }
    return ret;
}
