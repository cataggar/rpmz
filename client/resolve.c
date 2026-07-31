/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

static uint32_t
TDNFResolveListPackages(
    PTDNF pTdnf,
    TDNF_SCOPE nScope,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfos,
    uint32_t* pdwCount
    );

static uint32_t
TDNFResolveCollectCmdLineRpmPaths(
    PTDNF pTdnf,
    char*** pppszPaths,
    uint32_t* pdwCount
    );

uint32_t
TDNFAddNotResolved(
    char** ppszPkgsNotResolved,
    const char* pszPkgName
    )
{
    uint32_t dwError = 0 ;
    int nIndex = 0;

    if(!ppszPkgsNotResolved ||
       IsNullOrEmptyString(pszPkgName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    while(ppszPkgsNotResolved[nIndex++]);

    dwError = TDNFAllocateString(
                  pszPkgName,
                  &ppszPkgsNotResolved[--nIndex]);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPrepareAllPackages(
    PTDNF pTdnf,
    TDNF_ALTERTYPE* pAlterType,
    char** ppszPkgsNotResolved,
    PTDNF_ID_LIST queueGoal
    )
{
    uint32_t dwError = 0;
    PTDNF_CMD_ARGS pCmdArgs = NULL;
    int nPkgIndex = 0;
    char* pszPkgName = NULL;
    char*  pszSeverity = NULL;
    uint32_t dwSecurity = 0;
    char** ppszPkgArray = NULL;
    uint32_t dwCount = 0;
    uint32_t dwRebootRequired = 0;
    uint32_t dwTraceRequestRef = 0;
    TDNF_ALTERTYPE nAlterType = 0;
    int nTraceStart = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    uint32_t dwPkgInfoCount = 0;

    if(!pTdnf || !pTdnf->pSack ||
       !pTdnf->pArgs || !ppszPkgsNotResolved || !queueGoal || !pAlterType)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    pCmdArgs = pTdnf->pArgs;
    nAlterType = *pAlterType;

    if(nAlterType == ALTER_DOWNGRADEALL)
    {
        dwError = TDNFFilterPackages(pTdnf, nAlterType,
                       ppszPkgsNotResolved, queueGoal);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else if (nAlterType == ALTER_AUTOERASEALL)
    {
        nTraceStart = queueGoal->dwCount;
        dwError = TDNFGetAutoInstalledOrphans(pTdnf, queueGoal);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNFTransactionPlanRequestTraceRecordGoalRange(pTdnf->pRequestTrace, queueGoal->pnElements, nTraceStart, queueGoal->dwCount,
            ALTER_AUTOERASEALL, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_CLEANUP, 0);
    }

    dwError = TDNFGetSecuritySeverityOption(
                  pTdnf,
                  &dwSecurity,
                  &pszSeverity);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFGetRebootRequiredOption(
                  pTdnf,
                  &dwRebootRequired);
    BAIL_ON_TDNF_ERROR(dwError);

    if ((nAlterType == ALTER_UPGRADEALL ||
         nAlterType == ALTER_UPGRADE) &&
        (dwSecurity || pszSeverity || dwRebootRequired))
    {
        *pAlterType = ALTER_UPGRADE;
        dwError = TDNFGetUpdatePkgs(pTdnf, &ppszPkgArray, &dwCount);
        BAIL_ON_TDNF_ERROR(dwError);
        for(nPkgIndex = 0; (uint32_t)nPkgIndex < dwCount; ++nPkgIndex)
        {
            dwTraceRequestRef = nAlterType == ALTER_UPGRADEALL ? 0 :
                                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST;
            for(int nCmdIndex = 1;
                nAlterType == ALTER_UPGRADE && nCmdIndex < pCmdArgs->nCmdCount;
                nCmdIndex++)
            {
                if(dwTraceRequestRef == TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST &&
                   !fnmatch(pCmdArgs->ppszCmds[nCmdIndex],
                            ppszPkgArray[nPkgIndex], 0))
                    dwTraceRequestRef = nCmdIndex - 1;
            }
            dwError = TDNFPrepareSinglePkg(pTdnf, ppszPkgArray[nPkgIndex],
                          *pAlterType, ppszPkgsNotResolved, queueGoal,
                          dwTraceRequestRef);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }
    else
    {
       for(int nCmdIndex = 1; nCmdIndex < pCmdArgs->nCmdCount; ++nCmdIndex)
       {
           pszPkgName = pCmdArgs->ppszCmds[nCmdIndex];

           if(TDNFIsGlob(pszPkgName))
           {
               int nIsInstalled = (nAlterType == ALTER_ERASE ||
                                   nAlterType == ALTER_AUTOERASE ||
                                   nAlterType == ALTER_UPGRADE ||
                                   nAlterType == ALTER_DOWNGRADE ||
                                   nAlterType == ALTER_REINSTALL);
               char* ppszPkgSpec[2] = {pszPkgName, NULL};

               if(pPkgInfos)
               {
                   TDNFFreePackageInfoArray(pPkgInfos, dwPkgInfoCount);
                   pPkgInfos = NULL;
                   dwPkgInfoCount = 0;
               }
               dwError = TDNFResolveListPackages(
                             pTdnf,
                             nIsInstalled ? SCOPE_INSTALLED : SCOPE_AVAILABLE,
                             ppszPkgSpec,
                             &pPkgInfos,
                             &dwPkgInfoCount);
               if(dwError == ERROR_TDNF_NO_MATCH)
               {
                   dwError = 0;
               }
               BAIL_ON_TDNF_ERROR(dwError);
               if(dwPkgInfoCount == 0)
               {
                   dwError = TDNFAddNotResolved(ppszPkgsNotResolved, pszPkgName);
                   BAIL_ON_TDNF_ERROR(dwError);
                   TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                       pTdnf->pRequestTrace,
                       nCmdIndex - 1,
                       TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_NO_CANDIDATE);
               }
               else
               {
                   nPkgIndex = 0;
                   for(nPkgIndex = 0; (uint32_t)nPkgIndex < dwPkgInfoCount; nPkgIndex++)
                   {
                       dwError = TDNFPrepareSinglePkg(pTdnf, pPkgInfos[nPkgIndex].pszName, nAlterType,
                                     ppszPkgsNotResolved, queueGoal, nCmdIndex - 1);
                       BAIL_ON_TDNF_ERROR(dwError);
                   }
               }
           }
           else
           {
               if (fnmatch("*.rpm", pszPkgName, 0) == 0) {
                   continue;
               }

               dwError = TDNFPrepareSinglePkg(pTdnf, pszPkgName, nAlterType,
                             ppszPkgsNotResolved, queueGoal, nCmdIndex - 1);
               BAIL_ON_TDNF_ERROR(dwError);
           }
       }
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszSeverity);
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwPkgInfoCount);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFFilterPackages(
    PTDNF pTdnf,
    TDNF_ALTERTYPE nAlterType,
    char** ppszPkgsNotResolved,
    PTDNF_ID_LIST queueGoal)
{
    uint32_t dwError = 0;
    uint32_t dwPkgIndex = 0;
    uint32_t dwSize = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;

    if(!pTdnf || !pTdnf->pSack || !queueGoal || !ppszPkgsNotResolved)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFResolveListPackages(
                  pTdnf,
                  SCOPE_INSTALLED,
                  NULL,
                  &pPkgInfos,
                  &dwSize);
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = 0;
    }
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwPkgIndex = 0; dwPkgIndex < dwSize; dwPkgIndex++)
    {
        dwError = TDNFPrepareSinglePkg(pTdnf, pPkgInfos[dwPkgIndex].pszName, nAlterType,
                      ppszPkgsNotResolved, queueGoal, 0);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwSize);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFGetAutoInstalledOrphans(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueGoal)
{
    uint32_t dwError = 0;
    struct history_ctx *pHistoryCtx = NULL;
    char **ppszAutoRefs = NULL;
    char **ppszOrphanRefs = NULL;
    uint32_t dwAutoRefCount = 0;
    uint32_t dwOrphanCount = 0;

    if(!pTdnf || !pTdnf->pSack || !pQueueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &pHistoryCtx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQuerySerializeAutoInstalledRefs(
                  pTdnf,
                  pHistoryCtx,
                  &ppszAutoRefs,
                  &dwAutoRefCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(!dwAutoRefCount)
    {
        goto cleanup;
    }

    dwError = TDNFRepoMdNativeAutoInstalledOrphanLinesConfig(
                  pTdnf->pRpmConfig,
                  ppszAutoRefs,
                  &ppszOrphanRefs,
                  &dwOrphanCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryResolvePackageRefArrayToQueue(
                  pTdnf->pSack,
                  ppszOrphanRefs,
                  dwOrphanCount,
                  1,
                  pQueueGoal);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFFreeStringArray(ppszAutoRefs);
    TDNFFreeStringArray(ppszOrphanRefs);
    if(pHistoryCtx)
    {
        destroy_history_ctx(pHistoryCtx);
    }
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFPrepareSinglePkg(
    PTDNF pTdnf,
    const char* pszPkgName,
    TDNF_ALTERTYPE nAlterType,
    char** ppszPkgsNotResolved,
    PTDNF_ID_LIST queueGoal,
    uint32_t dwRequestRef
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    int nTraceStart = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    char* ppszPkgSpec[2] = {(char*)pszPkgName, NULL};

    if(!pTdnf ||
       !pTdnf->pSack ||
       !ppszPkgsNotResolved ||
       IsNullOrEmptyString(pszPkgName) ||
       !queueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    nTraceStart = queueGoal->dwCount;

    //Check if this is a known package. If not add to unresolved
    dwError = TDNFResolveListPackages(
                  pTdnf,
                  pTdnf->pArgs->nSource ? SCOPE_SOURCE : SCOPE_ALL,
                  ppszPkgSpec,
                  &pPkgInfos,
                  &dwCount);
    if (dwError == ERROR_TDNF_NO_MATCH)
    {
        pr_err("%s package not found or not installed\n", pszPkgName);
        if (pTdnf->pArgs->nSkipBroken)
        {
            dwError = 0;
        }
    }
    BAIL_ON_TDNF_ERROR(dwError);

    if (dwCount == 0)
    {
        dwError = ERROR_TDNF_NO_SEARCH_RESULTS;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(nAlterType == ALTER_REINSTALL)
    {
        dwError = TDNFMatchForReinstall(
                      pTdnf->pSack,
                      pszPkgName,
                      queueGoal);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(nAlterType == ALTER_ERASE ||
        nAlterType == ALTER_AUTOERASE)
    {
        if(pPkgInfos)
        {
            TDNFFreePackageInfoArray(pPkgInfos, dwCount);
            pPkgInfos = NULL;
            dwCount = 0;
        }

        dwError = TDNFResolveListPackages(
                      pTdnf,
                      SCOPE_INSTALLED,
                      ppszPkgSpec,
                      &pPkgInfos,
                      &dwCount);
        if(dwError == ERROR_TDNF_NO_MATCH)
        {
            dwError = ERROR_TDNF_ERASE_NEEDS_INSTALL;
        }
        BAIL_ON_TDNF_ERROR(dwError);
        if(dwCount == 0)
        {
            dwError = ERROR_TDNF_ERASE_NEEDS_INSTALL;
            BAIL_ON_TDNF_ERROR(dwError);
        }

        dwError = TDNFAddPackagesForErase(
                      pTdnf->pSack,
                      queueGoal,
                      pszPkgName);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else if (nAlterType == ALTER_INSTALL)
    {
        int nSource = pTdnf->pArgs->nSource;
        int nInstallOnly = 0;

        if (pTdnf->pConf->ppszInstallOnlyPkgs) {
            for (int i = 0; pTdnf->pConf->ppszInstallOnlyPkgs[i]; i++) {
                if (strcmp(pTdnf->pConf->ppszInstallOnlyPkgs[i], pszPkgName) == 0) {
                    nInstallOnly = 1;
                }
            }
        }

        dwError = TDNFAddPackagesForInstall(
                      pTdnf->pSack,
                      queueGoal,
                      pszPkgName,
                      nSource,
                      nInstallOnly);
        if (dwError == ERROR_TDNF_ALREADY_INSTALLED)
        {
            /* the package may have been already installed as a dependency,
               but now the user wants it on its own */
            dwError = TDNFMarkAutoInstalledSinglePkg(pTdnf, pszPkgName);
            BAIL_ON_TDNF_ERROR(dwError);
            /* if TDNFMarkAutoInstalledSinglePkg() was successful, restore
               the original error */
            dwError = ERROR_TDNF_ALREADY_INSTALLED;
        }
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else if (nAlterType == ALTER_UPGRADE)
    {
        dwError = TDNFAddPackagesForUpgrade(
                      pTdnf->pSack,
                      queueGoal,
                      pszPkgName);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else if (nAlterType == ALTER_DOWNGRADE ||
             nAlterType == ALTER_DOWNGRADEALL)
    {
        dwError = TDNFAddPackagesForDowngrade(
                      pTdnf,
                      pTdnf->pSack,
                      queueGoal,
                      pszPkgName);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    if(!dwError)
    {
        TDNFTransactionPlanRequestTraceRecordGoalRange(pTdnf->pRequestTrace, queueGoal->pnElements, nTraceStart, queueGoal->dwCount, nAlterType,
            TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER, dwRequestRef);
    }
    if (dwError)
    {
        pr_err("Error while processing package: '%s'\n", pszPkgName);
    }

    if (pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwCount);
    }
    return dwError;

error:
    if (dwError == ERROR_TDNF_ALREADY_INSTALLED)
    {
        int nShowAlreadyInstalled = 1;
        //dont show already installed errors in the check path
        if(pTdnf && pTdnf->pArgs)
        {
            if(!strcmp(pTdnf->pArgs->ppszCmds[0], "check"))
            {
                nShowAlreadyInstalled = 0;
            }
        }
        dwError = 0;
        if(dwRequestRef != TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST)
        {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                pTdnf->pRequestTrace,
                dwRequestRef,
                TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED);
        }
        if(nShowAlreadyInstalled)
        {
            pr_err("Package %s is already installed.\n", pszPkgName);
        }
    }
    else if (dwError == ERROR_TDNF_NO_UPGRADE_PATH)
    {
        dwError = 0;
        if(dwRequestRef != TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST)
        {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                pTdnf->pRequestTrace,
                dwRequestRef,
                TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED);
        }
        pr_err("There is no upgrade path for %s.\n", pszPkgName);
    }
    else if (dwError == ERROR_TDNF_NO_DOWNGRADE_PATH)
    {
        dwError = 0;
        if(dwRequestRef != TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST)
        {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                pTdnf->pRequestTrace,
                dwRequestRef,
                TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED);
        }
        pr_err("There is no downgrade path for %s.\n", pszPkgName);
    }
    else if (dwError == ERROR_TDNF_NO_SEARCH_RESULTS)
    {
        dwError = TDNFAddNotResolved(ppszPkgsNotResolved, pszPkgName);
        if (dwError)
        {
            pr_err("Error while adding not resolved packages: '%s'\n", pszPkgName);
        }
        else if(dwRequestRef != TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST)
        {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                pTdnf->pRequestTrace,
                dwRequestRef,
                TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_NO_CANDIDATE);
        }
    }
    else if (dwError == ERROR_TDNF_ERASE_NEEDS_INSTALL)
    {
        dwError = 0;
        if(dwRequestRef != TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST)
        {
            TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                pTdnf->pRequestTrace,
                dwRequestRef,
                TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED);
        }
        //TODO: maybe restore solvedinfo based processing here.
    }
    else if (dwError == ERROR_TDNF_NO_MATCH)
    {
        pr_err("Package '%s' not found\n", pszPkgName);
    }
    goto cleanup;
}

uint32_t
TDNFResolveBuildDependencies(
    PTDNF pTdnf,
    char **ppszPackageNameSpecs,
    char **ppszPkgsNotResolved,
    PTDNF_ID_LIST queueGoal
    )
{
    uint32_t dwError = 0;
    int i;
    const char *pszDep = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    uint32_t dwPkgCount = 0;
    char **ppszGoalRefs = NULL;
    char **ppszGoalDeps = NULL;
    char **ppszPkgRefs = NULL;
    char **ppszPkgDeps = NULL;
    char **ppszCmdLineRpmPaths = NULL;
    uint32_t dwGoalRefCount = 0;
    uint32_t dwGoalDepCount = 0;
    uint32_t dwPkgRefCount = 0;
    uint32_t dwPkgDepCount = 0;
    uint32_t dwCmdLineRpmPathCount = 0;

    if(!pTdnf || !pTdnf->pSack || !ppszPackageNameSpecs || !ppszPkgsNotResolved || !queueGoal)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(queueGoal->dwCount > 0)
    {
        dwError = TDNFResolveCollectCmdLineRpmPaths(
                      pTdnf,
                      &ppszCmdLineRpmPaths,
                      &dwCmdLineRpmPathCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if((queueGoal->dwCount > 0 && !dwCmdLineRpmPathCount) || ppszPackageNameSpecs[0])
    {
        dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (queueGoal->dwCount > 0) {
        if(dwCmdLineRpmPathCount)
        {
            dwError = TDNFRepoMdNativeRequiresForCmdLineRpmPaths(
                          (const char *const *)ppszCmdLineRpmPaths,
                          dwCmdLineRpmPathCount,
                          &ppszGoalDeps,
                          &dwGoalDepCount);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        else
        {
            dwError = TDNFNativeQuerySerializeQueuePackageRefs(
                          pTdnf->pSack,
                          queueGoal,
                          &ppszGoalRefs,
                          &dwGoalRefCount);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFRepoMdNativeRequiresForPackageRefsConfig(
                          pRepos,
                          dwRepoCount,
                          pTdnf->pRpmConfig,
                          ppszGoalRefs,
                          &ppszGoalDeps,
                          &dwGoalDepCount);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }
    TDNFIdListEmpty(queueGoal);

    if (ppszPackageNameSpecs[0]) {
        dwError = TDNFRepoMdNativeListConfig(
                      pRepos,
                      dwRepoCount,
                      pTdnf->pRpmConfig,
                      SCOPE_SOURCE,
                      ppszPackageNameSpecs,
                      DETAIL_LIST,
                      &pPkgInfos,
                      &dwPkgCount);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFNativeQuerySerializePackageInfoRefs(
                      pPkgInfos,
                      dwPkgCount,
                      &ppszPkgRefs,
                      &dwPkgRefCount);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFRepoMdNativeRequiresForPackageRefsConfig(
                      pRepos,
                      dwRepoCount,
                      pTdnf->pRpmConfig,
                      ppszPkgRefs,
                      &ppszPkgDeps,
                      &dwPkgDepCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for(i = 0; i < (int)dwGoalDepCount; i++)
    {
        pszDep = ppszGoalDeps[i];
        if(!pszDep || strncmp(pszDep, "rpmlib(", 7) == 0)
        {
            continue;
        }

        dwError = TDNFPrepareSinglePkg(pTdnf, pszDep, ALTER_INSTALL,
                      ppszPkgsNotResolved, queueGoal,
                      TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for(i = 0; i < (int)dwPkgDepCount; i++)
    {
        pszDep = ppszPkgDeps[i];
        if(!pszDep || strncmp(pszDep, "rpmlib(", 7) == 0)
        {
            continue;
        }

        dwError = TDNFPrepareSinglePkg(pTdnf, pszDep, ALTER_INSTALL,
                      ppszPkgsNotResolved, queueGoal,
                      TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    TDNFFreeStringArray(ppszGoalRefs);
    TDNFFreeStringArray(ppszGoalDeps);
    TDNFFreeStringArray(ppszPkgRefs);
    TDNFFreeStringArray(ppszPkgDeps);
    TDNFFreeStringArray(ppszCmdLineRpmPaths);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwPkgCount);
    }
    return dwError;
error:
    goto cleanup;
}

static uint32_t
TDNFResolveListPackages(
    PTDNF pTdnf,
    TDNF_SCOPE nScope,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfos,
    uint32_t* pdwCount
    )
{
    uint32_t dwError = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    uint32_t dwCount = 0;

    if(!pTdnf || !ppPkgInfos || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(nScope != SCOPE_INSTALLED)
    {
        dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdNativeListConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  nScope,
                  ppszPackageNameSpecs,
                  DETAIL_LIST,
                  &pPkgInfos,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfos = pPkgInfos;
    *pdwCount = dwCount;

cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    if(ppPkgInfos)
    {
        *ppPkgInfos = NULL;
    }
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwCount);
    }
    goto cleanup;
}

static uint32_t
TDNFResolveCollectCmdLineRpmPaths(
    PTDNF pTdnf,
    char*** pppszPaths,
    uint32_t* pdwCount
    )
{
    uint32_t dwError = 0;
    PTDNF_CMD_ARGS pCmdArgs = NULL;
    char **ppszPaths = NULL;
    char *pszRPMPath = NULL;
    char *pszCopyOfPkgName = NULL;
    uint32_t dwPathCount = 0;
    uint32_t dwPathIndex = 0;

    if(!pTdnf || !pTdnf->pArgs || !pppszPaths || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pppszPaths = NULL;
    *pdwCount = 0;

    pCmdArgs = pTdnf->pArgs;
    for(int nCmdIndex = 1; nCmdIndex < pCmdArgs->nCmdCount; nCmdIndex++)
    {
        if(fnmatch("*.rpm", pCmdArgs->ppszCmds[nCmdIndex], 0) == 0)
        {
            dwPathCount++;
        }
    }

    if(!dwPathCount)
    {
        goto cleanup;
    }

    dwError = TDNFAllocateMemory(
                  dwPathCount + 1,
                  sizeof(char*),
                  (void**)&ppszPaths);
    BAIL_ON_TDNF_ERROR(dwError);

    for(int nCmdIndex = 1; nCmdIndex < pCmdArgs->nCmdCount; nCmdIndex++)
    {
        char *pszPkgName = pCmdArgs->ppszCmds[nCmdIndex];
        int nIsFile = 0;
        int nIsRemote = 0;

        if(fnmatch("*.rpm", pszPkgName, 0) != 0)
        {
            continue;
        }

        dwError = TDNFIsFileOrSymlink(pszPkgName, &nIsFile);
        BAIL_ON_TDNF_ERROR(dwError);

        if(nIsFile)
        {
            pszRPMPath = realpath(pszPkgName, NULL);
            if(!pszRPMPath)
            {
                dwError = ERROR_TDNF_SYSTEM_BASE + errno;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
        else
        {
            dwError = TDNFUriIsRemote(pszPkgName, &nIsRemote);
            if(dwError == ERROR_TDNF_URL_INVALID)
            {
                dwError = 0;
                continue;
            }
            BAIL_ON_TDNF_ERROR(dwError);

            if(!nIsRemote)
            {
                dwError = TDNFPathFromUri(pszPkgName, &pszRPMPath);
                BAIL_ON_TDNF_ERROR(dwError);
            }
            else
            {
                PTDNF_REPO_DATA pRepo = NULL;

                dwError = TDNFAllocateString(pszPkgName, &pszCopyOfPkgName);
                BAIL_ON_TDNF_ERROR(dwError);

                dwError = TDNFFindRepoById(pTdnf, CMDLINE_REPO_NAME, &pRepo);
                BAIL_ON_TDNF_ERROR(dwError);

                dwError = TDNFDownloadPackageToCache(
                              pTdnf,
                              pszPkgName,
                              basename(pszCopyOfPkgName),
                              pRepo,
                              &pszRPMPath);
                BAIL_ON_TDNF_ERROR(dwError);

                TDNF_SAFE_FREE_MEMORY(pszCopyOfPkgName);
            }
        }

        ppszPaths[dwPathIndex++] = pszRPMPath;
        pszRPMPath = NULL;
    }

    *pppszPaths = ppszPaths;
    *pdwCount = dwPathIndex;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszRPMPath);
    TDNF_SAFE_FREE_MEMORY(pszCopyOfPkgName);
    return dwError;
error:
    if(pppszPaths)
    {
        *pppszPaths = NULL;
    }
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    if(ppszPaths)
    {
        TDNFFreeStringArray(ppszPaths);
    }
    goto cleanup;
}
