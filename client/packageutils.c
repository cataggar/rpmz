/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#define _GNU_SOURCE 1
#include "includes.h"

/* The one file in client/ that is allowed to see libsolv. Everything the
   rest of client/ needs from the pool, a repo or a package list goes
   through an accessor defined below. Keeping this include here rather than
   in client/includes.h is what makes that rule compiler-enforced. */
#include "../solv/includes.h"

#define PACKAGEUTILS_NATIVE_REF_SEP ((char)0x1f)

/* The job-list encoding in defines.h is tdnf's own, but its values are
   inherited from libsolv and are recorded in the request trace, so they must
   stay byte-identical. While libsolv is still vendored we can prove that at
   compile time rather than trusting the copy. Delete this block along with
   libsolv itself. */
_Static_assert(TDNF_JOB_SOLVABLE == SOLVER_SOLVABLE, "job select value changed");
_Static_assert(TDNF_JOB_SOLVABLE_NAME == SOLVER_SOLVABLE_NAME, "job select value changed");
_Static_assert(TDNF_JOB_SOLVABLE_ALL == SOLVER_SOLVABLE_ALL, "job select value changed");
_Static_assert(TDNF_JOB_INSTALL == SOLVER_INSTALL, "job action value changed");
_Static_assert(TDNF_JOB_ERASE == SOLVER_ERASE, "job action value changed");
_Static_assert(TDNF_JOB_UPDATE == SOLVER_UPDATE, "job action value changed");
_Static_assert(TDNF_JOB_MULTIVERSION == SOLVER_MULTIVERSION, "job action value changed");
_Static_assert(TDNF_JOB_LOCK == SOLVER_LOCK, "job action value changed");
_Static_assert(TDNF_JOB_DISTUPGRADE == SOLVER_DISTUPGRADE, "job action value changed");
_Static_assert(TDNF_JOB_USERINSTALLED == SOLVER_USERINSTALLED, "job action value changed");
_Static_assert(TDNF_JOB_ALLOWUNINSTALL == SOLVER_ALLOWUNINSTALL, "job action value changed");
_Static_assert(TDNF_JOB_JOBMASK == SOLVER_JOBMASK, "job mask value changed");
_Static_assert(TDNF_JOB_CLEANDEPS == SOLVER_CLEANDEPS, "job flag value changed");
_Static_assert(TDNF_JOB_FORCEBEST == SOLVER_FORCEBEST, "job flag value changed");
_Static_assert(sizeof(TDNF_PKG_ID) == sizeof(Id), "package handle width changed");
_Static_assert(sizeof(TDNF_STR_ID) == sizeof(Id), "string handle width changed");
_Static_assert(((Id)-1 < 0) == ((TDNF_PKG_ID)-1 < 0),
               "package handle signedness diverged from libsolv");
_Static_assert(((Id)-1 < 0) == ((TDNF_STR_ID)-1 < 0),
               "string handle signedness diverged from libsolv");
_Static_assert(TDNF_REPO_REUSE_REPODATA == REPO_REUSE_REPODATA,
               "repo flag value changed");

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
/*
 * Package-handle accessors.
 *
 * Reading a field out of a TDNF_PKG_ID is the only place client/ still
 * has to know how the handle is represented, so every such read is
 * routed through this section. Replacing the representation is then a
 * change confined here rather than a change to each caller.
 *
 * They live here, rather than in either caller, because querynative.c
 * and goal.c both need them. Promoting them from static grows libtdnf's
 * exported surface, so the new names are recorded in
 * scripts/abi-baseline.json as a deliberate act rather than a side
 * effect -- that is what the ABI audit exists to force.
 *
 * Field strings returned by TDNFPkgHandleGetFields and
 * TDNFPkgHandleGetName are borrowed from the sack and stay valid for as
 * long as it does; callers must not free them. The NEVRA is different
 * and is documented at TDNFPkgHandleGetRepoNevra.
 */

uint32_t
TDNFPkgHandleGetFields(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    PTDNF_PKG_FIELDS pFields
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;
    TDNF_PKG_FIELDS stFields = {0};

    if(!pPool || !pFields)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv || !pSolv->repo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    stFields.pszRepo = pSolv->repo->name;
    stFields.pszName = pool_id2str(pPool, pSolv->name);
    stFields.pszArch = pool_id2str(pPool, pSolv->arch);
    stFields.pszEvr = solvable_lookup_str(pSolv, SOLVABLE_EVR);

    if(IsNullOrEmptyString(stFields.pszRepo) ||
       IsNullOrEmptyString(stFields.pszName) ||
       IsNullOrEmptyString(stFields.pszArch) ||
       IsNullOrEmptyString(stFields.pszEvr))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pFields = stFields;

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPkgHandleGetName(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    const char **ppszName
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;
    const char *pszName = NULL;

    if(!pPool || !ppszName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszName = pool_id2str(pPool, pSolv->name);
    if(IsNullOrEmptyString(pszName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppszName = pszName;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Unlike the other accessors this one returns an ALLOCATED NEVRA that
 * the caller owns and must free. The underlying pool_solvable2str hands
 * back a slot in a small fixed-size ring buffer that later pool string
 * operations recycle, so handing that pointer out would give this file
 * two different lifetime contracts and invite a caller to hold a
 * dangling one. Copying costs a malloc and removes the trap; a future
 * non-libsolv implementation would have to build the string anyway.
 * The repo name is borrowed as usual.
 */
uint32_t
TDNFPkgHandleGetRepoNevra(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    const char **ppszRepo,
    char **ppszNevra
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;
    const char *pszRepo = "";
    const char *pszTmpNevra = NULL;
    char *pszNevra = NULL;

    if(!pPool || !ppszRepo || !ppszNevra)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* An unnamed repo is reported as the empty string rather than
       refused: the caller uses this to build a display ref. */
    if(pSolv->repo && pSolv->repo->name)
    {
        pszRepo = pSolv->repo->name;
    }

    pszTmpNevra = pool_solvable2str(pPool, pSolv);
    if(IsNullOrEmptyString(pszTmpNevra))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszTmpNevra, &pszNevra);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszRepo = pszRepo;
    *ppszNevra = pszNevra;

cleanup:
    return dwError;

error:
    TDNF_SAFE_FREE_MEMORY(pszNevra);
    goto cleanup;
}

/* Both operands must be non-NULL; there is no error channel here, so a
   NULL is a caller bug and is left to fault rather than be papered over
   with an arbitrary ordering. */
int
TDNFPkgHandleEvrCompare(
    Pool *pPool,
    const char *pszEvrLeft,
    const char *pszEvrRight
    )
{
    /* Compares in the sack's EVR ordering, which is not string equality:
       an omitted epoch and an explicit "0:" compare equal. */
    return pool_evrcmp_str(pPool, pszEvrLeft, pszEvrRight, EVRCMP_COMPARE);
}

/*
 * Repo name of a package handle, with exactly the validation the job
 * builder needs: the handle must resolve, belong to a repo, and that
 * repo must be named. Deliberately stricter than
 * TDNFPkgHandleGetRepoNevra, which tolerates an unnamed repo because it
 * is only building a display string.
 */
uint32_t
TDNFPkgHandleGetRepoName(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    const char **ppszRepo
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;

    if(!pPool || !ppszRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv || !pSolv->repo || IsNullOrEmptyString(pSolv->repo->name))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppszRepo = pSolv->repo->name;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Whether the handle names an already-installed package. This is repo
 * *identity*, not a repo name, so it cannot be answered by comparing
 * strings -- the installed repo is whichever one the pool has adopted
 * as such.
 */
uint32_t
TDNFPkgHandleIsInstalled(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    int *pnIsInstalled
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;

    if(!pPool || !pnIsInstalled)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv || !pSolv->repo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pnIsInstalled = (pSolv->repo == pPool->installed);

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * On-disk location of a package handle, ALLOCATED for the caller to
 * free. It is not borrowed on purpose: the underlying
 * solvable_get_location() returns a slot in a 16-slot ring buffer that
 * later pool string operations recycle, so a borrowed pointer silently
 * rots once seventeen of them are live. That was a real bug (#281).
 *
 * A solvable with no location at all yields NULL rather than an error,
 * which is how callers distinguish "not a downloadable file" from a
 * failure.
 */
uint32_t
TDNFPkgHandleGetLocation(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    char **ppszLocation
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;
    unsigned int nMediaNr = 0;
    char *pszLocation = NULL;

    if(!pPool || !ppszLocation)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFSafeAllocateString(
                  solvable_get_location(pSolv, &nMediaNr),
                  &pszLocation);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszLocation = pszLocation;

cleanup:
    return dwError;

error:
    TDNF_SAFE_FREE_MEMORY(pszLocation);
    goto cleanup;
}

/*
 * Name handle of a package handle.
 *
 * Returns the interned name id rather than a string so that callers
 * comparing a package's name against a set of names do not have to
 * strcmp: pool_str2id() interns once up front and the comparison is
 * then integer equality, which is what the job builders already do.
 * TDNFPkgHandleGetName is the accessor to reach for when a string is
 * actually wanted.
 */
uint32_t
TDNFPkgHandleGetNameId(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    TDNF_STR_ID *pIdName
    )
{
    uint32_t dwError = 0;
    Solvable *pSolv = NULL;

    if(!pPool || !pIdName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pIdName = pSolv->name;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Every installed package, as handles.
 *
 * The list is materialised rather than exposed as a cursor because the
 * callers push jobs while iterating and a cursor would hand them back a
 * live Solvable, which is the dereference this is meant to remove.
 *
 * An absent installed repo is an error, not an empty set. The loops this
 * replaces indexed straight into pPool->installed and would have
 * segfaulted, so nothing can be relying on a defined answer; reporting
 * it is preferable to silently behaving as though nothing is installed,
 * which would turn a broken sack into a plausible-looking transaction.
 */
uint32_t
TDNFInstalledGetPkgIds(
    Pool *pPool,
    PTDNF_ID_LIST pIdList
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID p = 0;
    Solvable *s = NULL;

    if(!pPool || !pIdList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(!pPool->installed)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    FOR_REPO_SOLVABLES(pPool->installed, p, s)
    {
        dwError = TDNFIdListPush(pIdList, p);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}

/* Whether any installed package carries this name handle. Same absent-repo
   contract as TDNFInstalledGetPkgIds. */
uint32_t
TDNFInstalledHasName(
    Pool *pPool,
    TDNF_STR_ID idName,
    int *pnFound
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID p = 0;
    Solvable *s = NULL;
    int nFound = 0;

    if(!pPool || !pnFound)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(!pPool->installed)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    FOR_REPO_SOLVABLES(pPool->installed, p, s)
    {
        if(s->name == idName)
        {
            nFound = 1;
            break;
        }
    }

    *pnFound = nFound;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Every package the sack knows about, installed or not, as handles.
 *
 * The counterpart to TDNFInstalledGetPkgIds. It is named for the pool
 * rather than against it: the Pool type is already in the signature, so
 * spelling it in the name reveals nothing that was hidden, and "pool"
 * is the accurate word for "every package known" as opposed to the
 * installed subset.
 *
 * The body delegates to libsolv's FOR_POOL_SOLVABLES rather than
 * reimplementing it, so the set and the order are exactly the macro's
 * by construction and there is no duplicated invariant to keep in sync.
 */
uint32_t
TDNFPoolGetPkgIds(
    Pool *pPool,
    PTDNF_ID_LIST pIdList
    )
{
    uint32_t dwError = 0;
    TDNF_PKG_ID p = 0;
    Pool *pool = NULL;

    if(!pPool || !pIdList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* FOR_POOL_SOLVABLES takes no pool argument -- it expands to code
       referring to a variable that must be spelled exactly "pool". That
       invisibility is why this macro escaped the dereference count for
       several increments; the alias is what the macro needs, not a
       second handle. */
    pool = pPool;

    FOR_POOL_SOLVABLES(p)
    {
        dwError = TDNFIdListPush(pIdList, p);
        BAIL_ON_TDNF_ERROR(dwError);
    }


cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * The string-handle space.
 *
 * A5-2b deliberately keeps these apart from the package-handle
 * accessors above. Both spaces are int32_t and both are called "Id" by
 * libsolv, so nothing but naming stops a caller passing one where the
 * other is meant -- and a package handle used as a string handle
 * silently reads whatever name happens to sit at that index rather
 * than failing. Folding them into one family of accessors would remove
 * the only distinction there is.
 */

/*
 * Intern a string, returning its handle.
 *
 * The create flag is 1, matching every call site this replaces: the
 * names come from configuration and may legitimately not be in the
 * pool yet, and a handle is wanted for the name either way.
 *
 * Returns 0 only for a NULL string -- the empty string interns to
 * STRID_EMPTY, which is 1. Callers that guard on a zero result are
 * therefore guarding against a NULL entry in their own array, not
 * against "not found", and two arrays walked with a shared index
 * cannot get out of step here.
 */
uint32_t
TDNFStrIdFromString(
    Pool *pPool,
    const char *pszStr,
    TDNF_STR_ID *pIdStr
    )
{
    uint32_t dwError = 0;

    if(!pPool || !pIdStr)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pIdStr = pool_str2id(pPool, pszStr, 1);

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Resolve a string handle to its text.
 *
 * The returned pointer is BORROWED and interned: it lives as long as
 * the pool and must not be freed. This is safe to hold, unlike
 * pool_solvable2str() and solvable_get_location(), which return pool
 * scratch from a 16-slot ring buffer that later calls overwrite --
 * borrowing one of those shipped a real bug (#281).
 *
 * A zero or negative handle is rejected rather than resolved. libsolv
 * would answer ID_NULL with the empty string, which reads as a package
 * legitimately named "", and every caller here treats an empty name as
 * an error anyway.
 */
uint32_t
TDNFStrIdToString(
    Pool *pPool,
    TDNF_STR_ID idStr,
    const char **ppszStr
    )
{
    uint32_t dwError = 0;
    const char *pszStr = NULL;

    if(!pPool || !ppszStr)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(idStr <= 0)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszStr = pool_id2str(pPool, idStr);
    if(IsNullOrEmptyString(pszStr))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppszStr = pszStr;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Is this package handle one the pool could resolve?
 *
 * A range check, not an existence check: handles below nsolvables may
 * still refer to a freed or never-populated slot. It answers the
 * question the job builder actually asks -- "can I hand this to an
 * accessor without libsolv indexing out of its array" -- and is
 * reported through pnValid rather than as an error because an
 * out-of-range handle is an expected input there, mapped by the caller
 * to its own error code.
 */
uint32_t
TDNFPkgHandleIsValid(
    Pool *pPool,
    TDNF_PKG_ID dwPkgId,
    int *pnValid
    )
{
    uint32_t dwError = 0;

    if(!pPool || !pnValid)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pnValid = (dwPkgId > 0 && dwPkgId < pPool->nsolvables);

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Repo lifecycle and the installed-repo handle.
 *
 * These are the last libsolv calls that lived outside this file. They
 * are lifecycle rather than package reads, so they do not fit the
 * accessor shapes above: they hand back a Repo * that the caller then
 * passes on. That is deliberate plumbing, not a leak -- the callers
 * never dereference what they receive, and the handle becomes an opaque
 * typedef when Pool and Repo do.
 */
uint32_t
TDNFPoolGetInstalledRepo(
    Pool *pPool,
    Repo **ppRepo
    )
{
    uint32_t dwError = 0;

    if(!pPool || !ppRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* Unlike the query helpers, an absent installed repo is returned as
       NULL rather than an error: the one caller passes it straight to
       SolvReadInstalledRpms, which has its own contract for it. */
    *ppRepo = pPool->installed;

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPoolCreateRepo(
    Pool *pPool,
    const char *pszName,
    Repo **ppRepo
    )
{
    uint32_t dwError = 0;
    Repo *pRepo = NULL;

    if(!pPool || IsNullOrEmptyString(pszName) || !ppRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pRepo = repo_create(pPool, pszName);
    if(!pRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppRepo = pRepo;

cleanup:
    return dwError;

error:
    goto cleanup;
}

/*
 * Frees the repo and its solvables (repo_free's reuse_ids = 1).
 *
 * Null-tolerant, so callers can free unconditionally in an error path
 * the way TDNF_SAFE_FREE_MEMORY lets them. Not exposed as a macro
 * because it cannot null the caller's pointer through a value argument,
 * and a freed Repo * left live is exactly the mistake worth not
 * inviting.
 */
void
TDNFRepoFree(
    Repo *pRepo
    )
{
    if(pRepo)
    {
        repo_free(pRepo, 1);
    }
}

/*
 * The package handles held by a SolvPackageList, in list order.
 *
 * SolvPackageList is tdnf's own struct, but it carries its selection in
 * an embedded libsolv Queue, so reading one is a libsolv dereference
 * wearing a tdnf name. That is precisely why it stayed invisible to the
 * dereference metric for the whole confinement effort: nothing in
 * `pPkgList->queuePackages.elements[i]` spells a libsolv identifier.
 *
 * Copies rather than lending the array out, because Queue.elements is
 * reallocated by queue_insertn and a borrowed pointer would dangle the
 * moment the list grew.
 */
uint32_t
TDNFPkgListGetIds(
    PSolvPackageList pPkgList,
    PTDNF_ID_LIST pIdList
    )
{
    uint32_t dwError = 0;
    int i = 0;

    if(!pPkgList || !pIdList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for(i = 0; i < pPkgList->queuePackages.count; i++)
    {
        dwError = TDNFIdListPush(pIdList,
                                 pPkgList->queuePackages.elements[i]);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}
