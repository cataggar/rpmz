/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#define _GNU_SOURCE 1
#include "includes.h"

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
    Queue* pQueueGoal
    )
{
    uint32_t dwError = 0;
    Id  dwInstalledId = 0;
    Id  dwAvailableId = 0;
    char* pszNevr = NULL;
    PSolvPackageList pInstalledPkgList = NULL;
    PSolvPackageList pAvailablePkgList = NULL;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvFindInstalledPkgByName(
                  pSack,
                  pszName,
                  &pInstalledPkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError =  SolvGetPackageId(pInstalledPkgList, 0, &dwInstalledId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetPkgNevrFromId(pSack, dwInstalledId, &pszNevr);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvFindAvailablePkgByName(
                  pSack,
                  pszNevr,
                  &pAvailablePkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetPackageId(pAvailablePkgList,
                               0,
                               &dwAvailableId);
    BAIL_ON_TDNF_ERROR(dwError);

    queue_push(pQueueGoal, dwAvailableId);

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszNevr);
    if(pAvailablePkgList)
    {
        SolvFreePackageList(pAvailablePkgList);
    }
    if(pInstalledPkgList)
    {
        SolvFreePackageList(pInstalledPkgList);
    }
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
    Id dwInstalled,
    PSolvSack pSack,
    PSolvPackageList pAvailabePkgList,
    Id* pdwDowngradePkgId
    )
{
    uint32_t dwError = 0;
    Id dwDownGradeId = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    char *pszInstalledRef = NULL;
    char **ppszMatches = NULL;
    uint32_t dwMatchCount = 0;

    if(!pTdnf || !pSack || !pdwDowngradePkgId || !pAvailabePkgList)
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
    Queue* pQueueGoal
    )
{
    uint32_t dwError = 0;
    PSolvPackageList pSolvPkgList = NULL;

    if(!pSack || IsNullOrEmptyString(pszPkgGlob) || !pQueueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (nIsInstalled) {
        dwError = SolvFindInstalledPkgByName(
                      pSack,
                      pszPkgGlob,
                      &pSolvPkgList);
    } else {
        dwError = SolvFindAvailablePkgByName(
                      pSack,
                      pszPkgGlob,
                      &pSolvPkgList);
    }
    BAIL_ON_TDNF_ERROR(dwError);

    if(pSolvPkgList->queuePackages.count > 0)
    {
        for(int dwPkgIndex = 0;
            dwPkgIndex < pSolvPkgList->queuePackages.count;
            dwPkgIndex++)
        {
            queue_push(pQueueGoal,
                       pSolvPkgList->queuePackages.elements[dwPkgIndex]);
        }
    }

cleanup:
    if(pSolvPkgList)
    {
        SolvFreePackageList(pSolvPkgList);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFAddPackagesForErase(
    PSolvSack pSack,
    Queue* pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    Id dwInstalledId = 0;
    int dwPkgIndex = 0;
    uint32_t dwCount = 0;
    PSolvPackageList pInstalledPkgList = NULL;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvFindInstalledPkgByName(
                  pSack,
                  pszPkgName,
                  &pInstalledPkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetPackageListSize(pInstalledPkgList, &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwPkgIndex = 0; (uint32_t)dwPkgIndex < dwCount; dwPkgIndex++)
    {
        dwError = SolvGetPackageId(
                      pInstalledPkgList,
                      dwPkgIndex,
                      &dwInstalledId);
        BAIL_ON_TDNF_ERROR(dwError);
        queue_push(pQueueGoal, dwInstalledId);
    }

cleanup:
    if(pInstalledPkgList)
    {
        SolvFreePackageList(pInstalledPkgList);
    }
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFVerifyInstallPackage(
    PSolvSack pSack,
    Id dwPkg,
    uint32_t* pdwInstallPackage
    )
{

    uint32_t dwError = 0;
    char* pszName = NULL;
    Id  dwInstalledId = 0;
    int dwEvrCompare = 0;
    uint32_t dwInstallPackage = 0;

    if(!pSack || !pdwInstallPackage)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvGetPkgNameFromId(pSack, dwPkg, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvFindHighestInstalled(
                  pSack,
                  pszName,
                  &dwInstalledId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvCmpEvr(pSack, dwPkg, dwInstalledId, &dwEvrCompare);
    BAIL_ON_TDNF_ERROR(dwError);

    //allow updates and downgrades with install
    //install could specify version
    if(dwEvrCompare)
    {
        dwInstallPackage = 1;
    }

    *pdwInstallPackage = dwInstallPackage;
cleanup:
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
    Queue* pQueueGoal,
    const char* pszPkgName,
    int nSource,
    int nInstallOnly
    )
{
    uint32_t dwError = 0;
    Id dwHighestAvailable = 0;
    uint32_t  dwInstallPackage = 0;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvFindHighestAvailable(
                  pSack,
                  pszPkgName,
                  nSource,
                  &dwHighestAvailable);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFVerifyInstallPackage(
                  pSack,
                  dwHighestAvailable,
                  &dwInstallPackage);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwInstallPackage == 1 || nInstallOnly || nSource)
    {
        queue_push(pQueueGoal, dwHighestAvailable);
    }
    else
    {
        dwError = ERROR_TDNF_ALREADY_INSTALLED;
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFVerifyUpgradePackage(
    PSolvSack pSack,
    Id dwPkg,
    uint32_t* pdwUpgradePackage
    )
{

    uint32_t dwError = 0;
    char* pszName = NULL;
    Id  dwInstalledId = 0;
    int dwEvrCompare = 0;
    uint32_t dwUpgradePackage = 0;

    if(!pSack || !pdwUpgradePackage)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvGetPkgNameFromId(pSack, dwPkg, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvFindHighestInstalled(
                  pSack,
                  pszName,
                  &dwInstalledId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvCmpEvr(pSack, dwPkg, dwInstalledId, &dwEvrCompare);
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
    Queue* pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    Id dwHighestAvailable = 0;
    uint32_t  dwUpgradePackage = 0;

    if(!pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvFindHighestAvailable(
                  pSack,
                  pszPkgName,
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
        queue_push(pQueueGoal, dwHighestAvailable);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}


uint32_t
TDNFAddPackagesForDowngrade(
    PTDNF pTdnf,
    PSolvSack pSack,
    Queue* pQueueGoal,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0;
    PSolvPackageList pAvailabePkgList = NULL;
    Id dwInstalledId = 0;
    Id dwAvailableId = 0;
    Id dwDownGradeId = 0;
    char* pszName = NULL;

    if(!pTdnf || !pSack || !pQueueGoal || IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvFindAvailablePkgByName(
                  pSack,
                  pszPkgName,
                  &pAvailabePkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetPackageId(pAvailabePkgList, 0, &dwAvailableId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetPkgNameFromId(pSack, dwAvailableId, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvFindLowestInstalled(
                  pSack,
                  pszName,
                  &dwInstalledId);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFPackageGetDowngrade(
                  pTdnf,
                  dwInstalledId,
                  pSack,
                  pAvailabePkgList,
                  &dwDownGradeId);
    BAIL_ON_TDNF_ERROR(dwError);

    queue_push(pQueueGoal, dwDownGradeId);
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszName);
    if(pAvailabePkgList)
    {
        SolvFreePackageList(pAvailabePkgList);
    }
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
    int nRepoIndex = 0;
    Pool *pool = NULL;
    Repo *pRepo = NULL;
    PTDNF_REPO_DATA pRepoData = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;

    if(!pSack || !pSack->pPool || !ppRepos || !pdwRepoCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pool = pSack->pPool;
    FOR_REPOS(nRepoIndex, pRepo)
    {
        pRepoData = (PTDNF_REPO_DATA)pRepo->appdata;
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

    FOR_REPOS(nRepoIndex, pRepo)
    {
        const char *pszCacheName = NULL;

        pRepoData = (PTDNF_REPO_DATA)pRepo->appdata;
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
