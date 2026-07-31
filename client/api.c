/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"
#include "../llconf/nodes.h"

uid_t gEuid;

static int instanceLockFd = -1;

static void TdnfExitHandler(void);
static void IsTdnfAlreadyRunning(void);
static uint32_t TDNFApplyRpmDefine(PTDNF pTdnf, const char *pszValue);

static void TdnfExitHandler(void)
{
    if (gEuid)
    {
        return;
    }

    tdnfLockFree(TDNF_INSTANCE_LOCK_FILE, instanceLockFd);
}

static void IsTdnfAlreadyRunning(void)
{
    if (gEuid)
    {
        return;
    }

    instanceLockFd = tdnfLockAcquire(TDNF_INSTANCE_LOCK_FILE);
    if (instanceLockFd < 0)
    {
        pr_err("Failed to acquire tdnfInstance lock\n");
    }
}

uint32_t TDNFInit(void)
{
    return 0;
}

void TDNFUninit(void)
{
}

//Check all available packages
uint32_t
TDNFCheckPackages(
    PTDNF pTdnf
    )
{
    uint32_t dwError = 0;
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo = NULL;
    PTDNF_CMD_ARGS pArgs = NULL;
    int nCmdCountOrig = 0;
    char **ppszCmdsOrig = NULL;
    const char *ppszCheckCmds[] = {"check", "*", NULL};

    if(!pTdnf || !pTdnf->pArgs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pArgs = pTdnf->pArgs;
    nCmdCountOrig = pArgs->nCmdCount;
    ppszCmdsOrig = pArgs->ppszCmds;

    //We dont intend to follow through on this install command
    pArgs->nAssumeNo = 1;

    //pass all packages available to resolve with install operation
    pArgs->nCmdCount = 2;
    pArgs->ppszCmds = (char **)ppszCheckCmds;

    dwError = TDNFResolve(pTdnf, ALTER_INSTALL, &pSolvedPkgInfo);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    if(pArgs)
    {
        pArgs->nCmdCount = nCmdCountOrig;
        pArgs->ppszCmds = ppszCmdsOrig;
    }
    if(pSolvedPkgInfo)
    {
       TDNFFreeSolvedPackageInfo(pSolvedPkgInfo);
    }
    return dwError;

error:
    goto cleanup;
}

//All alter commands such as install/update/erase
uint32_t
TDNFAlterCommand(
    PTDNF pTdnf,
    PTDNF_SOLVED_PKG_INFO pSolvedInfo
    )
{
    uint32_t dwError = 0;

    if(!pTdnf || !pSolvedInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRpmExecTransaction(pTdnf, pSolvedInfo);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFAlterHistoryCommand(
    PTDNF pTdnf,
    PTDNF_SOLVED_PKG_INFO pSolvedInfo,
    PTDNF_HISTORY_ARGS pHistoryArgs
    )
{
    uint32_t dwError = 0;
    if(!pTdnf || !pSolvedInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRpmExecHistoryTransaction(pTdnf, pSolvedInfo, pHistoryArgs);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;

error:
    goto cleanup;
}

/**
 * Use case : tdnf check --skipconflicts --skipobsoletes
 *            tdnf check --skipconflicts
 *            tdnf check --skipobsoletes
 *            tdnf check
 * Description: This will verify if "tdnf check" command
 *              is given with --skipconflicts or --skipobsoletes
 *              or with both option, then set the problem type
 *              variable accordingly.
 * Arguments:
 *     pTdnf: Handler for TDNF command
 *     pdwSkipProblem: enum value which tells which kind of problem is set
 *
 * Return:
 *         0 : if success
 *         non zero: if error occurs
 *
 */
uint32_t
TDNFGetSkipProblemOption(
    PTDNF pTdnf,
    TDNF_SKIPPROBLEM_TYPE *pdwSkipProblem
    )
{
    uint32_t dwError = 0;
    struct cnfnode *cn = NULL;

    if (!pTdnf || !pTdnf->pArgs || !pdwSkipProblem)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pdwSkipProblem = SKIPPROBLEM_NONE;

    for (cn = pTdnf->pArgs->cn_setopts->first_child; cn; cn = cn->next) {
        if (strcasecmp(cn->name, "skipconflicts") == 0){
            *pdwSkipProblem |= SKIPPROBLEM_CONFLICTS;
        }
        if (strcasecmp(cn->name, "skipobsoletes") == 0){
            *pdwSkipProblem |= SKIPPROBLEM_OBSOLETES;
        }
    }

    if (pTdnf->pArgs->nSkipBroken)
    {
        *pdwSkipProblem |= SKIPPROBLEM_BROKEN;
    }

cleanup:
    return dwError;

error:
    if (pdwSkipProblem)
    {
       *pdwSkipProblem = SKIPPROBLEM_NONE;
    }
    goto cleanup;
}

//check a local rpm folder for dependency issues.
uint32_t
TDNFCheckLocalPackages(
    PTDNF pTdnf,
    const char* pszLocalPath
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    const char *pszNativeArch = NULL;
    const char *pszErrorPath = NULL;
    char *pszNativeArchOwned = NULL;
    void *pHandle = NULL;
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem = SKIPPROBLEM_NONE;

    if(!pTdnf || !pTdnf->pArgs || !pTdnf->pSack || !pszLocalPath)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pr_info("Checking all packages from: %s\n", pszLocalPath);

    if(!IsNullOrEmptyString(pTdnf->pArgs->pszArch))
    {
        pszNativeArch = pTdnf->pArgs->pszArch;
    }
    else
    {
        dwError = TDNFGetKernelArch(&pszNativeArchOwned);
        BAIL_ON_TDNF_ERROR(dwError);
        pszNativeArch = pszNativeArchOwned;
    }
    if(IsNullOrEmptyString(pszNativeArch))
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* The universe is the directory and nothing else: the installed packages
       and the configured repositories take no part in the check. */
    dwError = TDNFRepoMdNativeSolverCheckLocal(pszLocalPath, pszNativeArch,
                                               &dwCount, &pHandle,
                                               &pszErrorPath);
    if(dwError && pszErrorPath)
    {
        /* Name the entry that could not be classified, as the walk did. */
        pr_err("ReadRpms: Error while operating on '%s', '%s'\n",
               pszErrorPath,
               strerror(dwError > ERROR_TDNF_SYSTEM_BASE ?
                        (int)(dwError - ERROR_TDNF_SYSTEM_BASE) : 0));
    }
    BAIL_ON_TDNF_ERROR(dwError);

    pr_info("Found %u packages\n", dwCount);

    if(pHandle)
    {
        dwError = TDNFGetSkipProblemOption(pTdnf, &dwSkipProblem);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFReportNativeSolverProblems(pHandle, dwSkipProblem);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    if(pHandle)
    {
        TDNFRepoMdNativeSolverLiveSolveRelease(pHandle);
    }
    TDNF_SAFE_FREE_MEMORY(pszNativeArchOwned);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFCheckUpdates(
    PTDNF pTdnf,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount
    )
{
    uint32_t dwError = 0;
    dwError = TDNFList(
                  pTdnf,
                  SCOPE_UPGRADES,
                  ppszPackageNameSpecs,
                  ppPkgInfo,
                  pdwCount);
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = 0;
    }
    return dwError;
}


//Clean cache data
uint32_t
TDNFClean(
    PTDNF pTdnf,
    uint32_t nCleanType
    )
{
    uint32_t dwError = 0;
    PTDNF_REPO_DATA pRepo = NULL;

    if(!pTdnf)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(nCleanType == CLEANTYPE_PLUGINS)
    {
        dwError = ERROR_TDNF_CLEAN_UNSUPPORTED;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for (pRepo = pTdnf->pRepos; pRepo; pRepo = pRepo->pNext)
    {
        if (strcmp(pRepo->pszId, CMDLINE_REPO_NAME) == 0)
        {
            continue;
        }
        pr_info("cleaning %s:", pRepo->pszId);
        if (nCleanType & CLEANTYPE_METADATA)
        {
            pr_info(" metadata");
            dwError = TDNFRepoRemoveCache(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if (nCleanType & CLEANTYPE_DBCACHE)
        {
            pr_info(" dbcache");
            dwError = TDNFRemoveSolvCache(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if (nCleanType & CLEANTYPE_PACKAGES)
        {
            pr_info(" packages");
            dwError = TDNFRemoveRpmCache(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if (nCleanType & CLEANTYPE_KEYS)
        {
            pr_info(" keys");
            dwError = TDNFRemoveKeysCache(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if (nCleanType & CLEANTYPE_EXPIRE_CACHE)
        {
            pr_info(" expire-cache");
            dwError = TDNFRemoveLastRefreshMarker(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
            dwError = TDNFRemoveMirrorList(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
            dwError = TDNFRemoveSnapshot(pTdnf, pRepo);
            BAIL_ON_TDNF_ERROR(dwError);
        }

        /* remove the top level repo cache dir if it's not empty */
        dwError = TDNFRepoRemoveCacheDir(pTdnf, pRepo);
        if (dwError == ERROR_TDNF_SYSTEM_BASE + ENOTEMPTY)
        {
            /* if we did a 'clean all' the directory should be empty now. If
               not we either missed something or someone other than us
               put a file there, so warn about it, but don't bail out.
               If we did clean just one part it's not expected to be empty
               unless the other parts were already cleaned.
            */
            if (nCleanType == CLEANTYPE_ALL)
            {
                pr_err("Cache directory for %s not removed because it's not empty.\n", pRepo->pszId);
            }
            dwError = 0;
        }
        BAIL_ON_TDNF_ERROR(dwError);

        pr_info("\n");
    }
cleanup:
    return dwError;

error:
    goto cleanup;
}

//Show count of installed
//not a tdnf command just confidence check
//equivalent to rpm -qa | wc -l
uint32_t
TDNFCountCommand(
    PTDNF pTdnf,
    uint32_t* pdwCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwRepoCount = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;

    if(!pTdnf || !pTdnf->pSack || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeListConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  SCOPE_ALL,
                  NULL,
                  DETAIL_LIST,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *pdwCount = dwCount;
cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    if(pPkgInfo)
    {
        TDNFFreePackageInfoArray(pPkgInfo, dwCount);
    }
    return dwError;
error:
    if(pdwCount)
    {
        *pdwCount = 0;
    }
    goto cleanup;
}

//Lists info on each installed package
//Returns a sum of installed size
uint32_t
TDNFInfo(
    PTDNF pTdnf,
    TDNF_SCOPE nScope,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount
    )
{
    return TDNFListInternal(pTdnf, nScope,
                    ppszPackageNameSpecs,
                    ppPkgInfo, pdwCount,
                    DETAIL_INFO
                    );
}

uint32_t
TDNFList(
    PTDNF pTdnf,
    TDNF_SCOPE nScope,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount
    )
{
    return TDNFListInternal(pTdnf, nScope,
                    ppszPackageNameSpecs,
                    ppPkgInfo, pdwCount,
                    DETAIL_LIST);
}

uint32_t
TDNFListInternal(
    PTDNF pTdnf,
    TDNF_SCOPE nScope,
    char** ppszPackageNameSpecs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* pdwCount,
    TDNF_PKG_DETAIL nDetail
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;

    if(!pTdnf || !pTdnf->pSack || !ppszPackageNameSpecs ||
       !ppPkgInfo || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeListConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  nScope,
                  ppszPackageNameSpecs,
                  nDetail,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfo = pPkgInfo;
    *pdwCount = dwCount;

cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
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

//initialize tdnf and return an opaque handle
//to be used in subsequent calls.
uint32_t
TDNFOpenHandle(
    PTDNF_CMD_ARGS pArgs,
    PTDNF* ppTdnf
    )
{
    uint32_t dwError = 0;
    PTDNF pTdnf = NULL;
    PSolvSack pSack = NULL;
    char *pszConfFile = NULL;
    char *pszConfFileInstallRoot = NULL;
    struct cnfnode *cn = NULL;

    if(!pArgs || !ppTdnf)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    gEuid = geteuid();

    IsTdnfAlreadyRunning();

    GlobalSetQuiet(pArgs->nQuiet);
    GlobalSetJson(pArgs->nJsonOutput);

    dwError = TDNFAllocateMemory(1, sizeof(TDNF), (void**)&pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    pTdnf->pArgs = pArgs;
    pTdnf->pRpmConfig = tdnf_rpm_config_create(pArgs->pszInstallRoot);
    if (!pTdnf->pRpmConfig)
    {
        pr_err("Failed to initialize native rpm configuration: %s\n",
               tdnf_rpm_config_last_error());
        dwError = ERROR_TDNF_RPMRC_FAIL;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* if using --installroot, we prefer the tdnf.conf from the
    installroot unless a tdnf.conf location is explicitely set */
    if(IsNullOrEmptyString(pArgs->pszConfFile) &&
       !IsNullOrEmptyString(pArgs->pszInstallRoot) &&
       strcmp(pArgs->pszInstallRoot, "/"))
    {
        /* no conf file explicitely set in args,
        but using --installroot */

        int nExists = 0;

        /* prepend installroot to tdnf.conf location */
        dwError = TDNFJoinPath(&pszConfFileInstallRoot,
                            pArgs->pszInstallRoot,
                            TDNF_CONF_FILE,
                            NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFIsFileOrSymlink(pszConfFileInstallRoot, &nExists);
        BAIL_ON_TDNF_ERROR(dwError);

        /* if we find tdnf.conf inside the install root use it,
        otherwise use tdnf.conf from the host */
        dwError = TDNFAllocateString(
                   nExists ? pszConfFileInstallRoot : TDNF_CONF_FILE,
                   &pszConfFile);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else
    {
        dwError = TDNFAllocateString(
                   pArgs->pszConfFile ?
                         pArgs->pszConfFile : TDNF_CONF_FILE,
                   &pszConfFile);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFReadConfig(
                  pTdnf,
                  pszConfFile,
                  TDNF_CONF_GROUP);
    BAIL_ON_TDNF_ERROR(dwError);

    for (cn = pTdnf->pArgs->cn_setopts->first_child; cn; cn = cn->next) {
        /* set macros from command line */
        if (strcmp(cn->name, "rpmdefine") == 0) {
            dwError = TDNFApplyRpmDefine(pTdnf, cn->value);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    dwError = TDNFConfigExpandVars(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    GlobalSetDnfCheckUpdateCompat(pTdnf->pConf->nCheckUpdateCompat);

    dwError = TDNFLoadPlugins(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvInitSack(
                  &pSack,
                  pTdnf->pConf->pszCacheDir,
                  pTdnf->pArgs->pszInstallRoot,
                  pTdnf->pArgs->pszArch);
    BAIL_ON_TDNF_ERROR(dwError);

    if(!pArgs->nAllDeps)
    {
        dwError = SolvReadInstalledRpms(
                      pSack->pPool->installed,
                      pTdnf->pConf->pszCacheDir,
                      pTdnf->pRpmConfig);
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    dwError = TDNFLoadRepoData(
                  pTdnf,
                  &pTdnf->pRepos);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoListFinalize(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFInitCmdLineRepo(pTdnf, pSack);
    BAIL_ON_TDNF_ERROR(dwError);

    pool_addfileprovides(pSack->pPool);
    pool_createwhatprovides(pSack->pPool);

    pTdnf->pSack = pSack;
    *ppTdnf = pTdnf;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszConfFile);
    TDNF_SAFE_FREE_MEMORY(pszConfFileInstallRoot);
    return dwError;

error:
    if(pTdnf)
    {
        TDNFCloseHandle(pTdnf);
    }
    if(ppTdnf)
    {
        *ppTdnf = NULL;
    }
    if(pSack)
    {
        SolvFreeSack(pSack);
    }
    goto cleanup;
}

static uint32_t
TDNFApplyRpmDefine(
    PTDNF pTdnf,
    const char *pszValue
    )
{
    uint32_t dwError = 0;

    if (!pTdnf || !pTdnf->pRpmConfig || IsNullOrEmptyString(pszValue))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (tdnf_rpm_config_apply_define(pTdnf->pRpmConfig, pszValue) != 0)
    {
        pr_err("Invalid rpmdefine '%s': %s\n",
               pszValue, tdnf_rpm_config_last_error());
        dwError = ERROR_TDNF_RPMRC_FAIL;
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}

static uint32_t
TDNFAddCmdLinePackages(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueGoal,
    TDNF_ALTERTYPE nAlterType,
    int *pnUnresolved
)
{
    uint32_t dwError = 0;
    PTDNF_CMD_ARGS pCmdArgs = NULL;
    PSolvSack pSack;
    int nIsFile;
    int nIsRemote;
    int nCmdIndex;
    char *pszPkgName;
    char *pszCopyOfPkgName = NULL;
    char* pszRPMPath = NULL;
    Id id;
    uint32_t dwSolvableId = 0;
    uint32_t nTraceStart = 0;

    if(!pTdnf || !pnUnresolved)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *pnUnresolved = 0;
    pCmdArgs = pTdnf->pArgs;
    pSack = pTdnf->pSack;

    for(nCmdIndex = 1; nCmdIndex < pCmdArgs->nCmdCount; ++nCmdIndex)
    {
        pszPkgName = pCmdArgs->ppszCmds[nCmdIndex];
        if (fnmatch("*.rpm", pszPkgName, 0) != 0)
        {
            continue;
        }

        if (fnmatch("*.src.rpm", pszPkgName, 0) == 0 ||
            fnmatch("*.nosrc.rpm", pszPkgName, 0) == 0) {
            if (!pCmdArgs->nSource && !pCmdArgs->nBuildDeps) {
                pr_err("package '%s' appears to be a source rpm - use --source to install, or --builddeps to install its build depenfdencies\n", pszPkgName);
                dwError = ERROR_TDNF_INVALID_PARAMETER;
            }
        } else {
            if (pCmdArgs->nSource || pCmdArgs->nBuildDeps) {
                pr_err("package '%s' appears not to be a source rpm but --source or --builddeps was used\n", pszPkgName);
                dwError = ERROR_TDNF_INVALID_PARAMETER;
            }
        }
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFIsFileOrSymlink(pszPkgName, &nIsFile);
        BAIL_ON_TDNF_ERROR(dwError);

        if (nIsFile)
        {
            pszRPMPath = realpath(pszPkgName, NULL);
            if (pszRPMPath == NULL)
            {
                dwError = ERROR_TDNF_SYSTEM_BASE + errno;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
        else
        {
            dwError = TDNFUriIsRemote(pszPkgName, &nIsRemote);
            if (dwError == ERROR_TDNF_URL_INVALID)
            {
                if (TDNFTransactionPlanStateIsEnabled(pTdnf->pTransactionPlanState))
                {
                    TDNFTransactionPlanRequestTraceRecordRequestOutcome(
                        pTdnf->pRequestTrace,
                        nCmdIndex - 1,
                        TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_NO_CANDIDATE);
                    (*pnUnresolved)++;
                }
                dwError = 0;
                continue;
            }
            BAIL_ON_TDNF_ERROR(dwError);
            if (!nIsRemote)
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

                dwError = TDNFDownloadPackageToCache(pTdnf, pszPkgName,
                              basename(pszCopyOfPkgName), pRepo, &pszRPMPath);
                BAIL_ON_TDNF_ERROR(dwError);

                TDNF_SAFE_FREE_MEMORY(pszCopyOfPkgName);
           }
        }
        dwSolvableId = 0;
        dwError = TDNFRepoMdNativeAddRpm(
                      pTdnf->pSolvCmdLineRepo,
                      pszRPMPath,
                      REPO_REUSE_REPODATA|REPO_NO_INTERNALIZE|
                      RPM_ADD_WITH_HDRID|RPM_ADD_WITH_SHA256SUM,
                      &dwSolvableId);
        BAIL_ON_TDNF_ERROR(dwError);
        id = (Id)dwSolvableId;
        nTraceStart = pQueueGoal->dwCount;
        dwError = TDNFIdListPush(pQueueGoal, id);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNFTransactionPlanRequestTraceRecordGoalRange(pTdnf->pRequestTrace, pQueueGoal->pnElements, nTraceStart,
            pQueueGoal->dwCount, nAlterType, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER, nCmdIndex - 1);
    }

    repo_internalize(pTdnf->pSolvCmdLineRepo);
    pool_addfileprovides(pSack->pPool);
    pool_createwhatprovides(pSack->pPool);

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszRPMPath);
    TDNF_SAFE_FREE_MEMORY(pszCopyOfPkgName);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFProvides(
    PTDNF pTdnf,
    const char* pszSpec,
    PTDNF_PKG_INFO* ppPkgInfo
    )
{
    uint32_t dwError = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;

    if(!pTdnf || !pTdnf->pSack || IsNullOrEmptyString(pszSpec) ||
       !ppPkgInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeProvidesConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  pszSpec,
                  &pPkgInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfo = pPkgInfo;
cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = ERROR_TDNF_NO_DATA;
    }
    if(ppPkgInfo)
    {
      *ppPkgInfo = NULL;
    }
    TDNFFreePackageInfo(pPkgInfo);
    goto cleanup;
}

uint32_t
TDNFRepoList(
    PTDNF pTdnf,
    TDNF_REPOLISTFILTER nFilter,
    PTDNF_REPO_DATA* ppReposAll
    )
{
    uint32_t dwError = 0;
    PTDNF_REPO_DATA pReposAll = NULL;
    PTDNF_REPO_DATA pRepoTemp = NULL;
    PTDNF_REPO_DATA pRepoCurrent = NULL;

    PTDNF_REPO_DATA pRepos = NULL;

    if(!pTdnf || !pTdnf->pRepos || !ppReposAll)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pRepos = pTdnf->pRepos;

    while(pRepos)
    {
        int nAdd = 0;
        if(nFilter == REPOLISTFILTER_ALL)
        {
            nAdd = 1;
        }
        else if(nFilter == REPOLISTFILTER_ENABLED && pRepos->nEnabled)
        {
            nAdd = 1;
        }
        else if(nFilter == REPOLISTFILTER_DISABLED && !pRepos->nEnabled)
        {
            nAdd = 1;
        }
        if(nAdd)
        {
            dwError = TDNFCloneRepo(pRepos, &pRepoTemp);
            BAIL_ON_TDNF_ERROR(dwError);

            if(!pReposAll)
            {
                pReposAll = pRepoTemp;
                pRepoCurrent = pReposAll;
            }
            else
            {
                pRepoCurrent->pNext = pRepoTemp;
                pRepoCurrent = pRepoCurrent->pNext;
            }
            pRepoTemp = NULL;
        }

        pRepos = pRepos->pNext;
    }

    *ppReposAll = pReposAll;

cleanup:
    return dwError;

error:
    if(ppReposAll)
    {
        *ppReposAll = NULL;
    }
    if(pReposAll)
    {
        TDNFFreeRepos(pReposAll);
    }
    goto cleanup;
}

static int
_rm_rpms(
    const char *pszFilePath,
    const struct stat *sbuf,
    int type,
    struct FTW *ftwb
    )
{
    uint32_t dwError = 0;
    char *pszKeepFile = NULL;
    struct stat statKeep = {0};

    UNUSED(sbuf);
    UNUSED(type);
    UNUSED(ftwb);

    if (strcmp(&pszFilePath[strlen(pszFilePath)-4], ".rpm") == 0)
    {
        dwError = TDNFAllocateStringPrintf(&pszKeepFile, "%s.reposync-keep", pszFilePath);
        BAIL_ON_TDNF_ERROR(dwError);

        if (stat(pszKeepFile, &statKeep))
        {
            if (errno == ENOENT)
            {
                pr_info("deleting %s\n", pszFilePath);
                if(remove(pszFilePath) < 0)
                {
                    pr_crit("unable to remove %s: %s\n", pszFilePath, strerror(errno));
                }
            }
            else
            {
                dwError = errno;
                BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
            }
        }
        else
        {
            /* marker file can be removed now */
            /* coverity[toctou] */
            if(remove(pszKeepFile) < 0)
            {
                pr_crit("unable to remove %s: %s\n", pszKeepFile, strerror(errno));
            }
        }
    }
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszKeepFile);
    return (int)dwError;
error:
    goto cleanup;
}

uint32_t
TDNFRepoSync(
    PTDNF pTdnf,
    PTDNF_REPOSYNC_ARGS pReposyncArgs
    )
{
    uint32_t dwError = 0;
    int ret;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    PTDNF_REPO_DATA pRepo = NULL;
    char *pszRepoDir = NULL;
    char *pszRootPath = NULL;
    char *pszUrl = NULL;
    char *pszDir = NULL;
    char *pszFilePath = NULL;
    char *pszKeepFile = NULL;
    tdnf_rpm_file *pRpmFile = NULL;
    uint32_t dwRepoCount = 0;
    uint32_t dwNativeRepoCount = 0;
    uint32_t dwPkgInfoCount = 0;

    if(!pTdnf || !pTdnf->pSack || !pReposyncArgs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* count enabled repos */
    for (pRepo = pTdnf->pRepos; pRepo; pRepo = pRepo->pNext)
    {
        if ((strcmp(pRepo->pszId, CMDLINE_REPO_NAME) == 0) ||
            (!pRepo->nEnabled))
        {
            continue;
        }
        dwRepoCount++;
    }

    if (dwRepoCount > 1 && pReposyncArgs->nNoRepoPath)
    {
        pr_crit("cannot use norepopath with multiple repos\n");
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pReposyncArgs->nDelete && pReposyncArgs->nNoRepoPath)
    {
        /* prevent accidental deletion of packages */
        pr_crit("cannot use the delete option with norepopath\n");
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pReposyncArgs->nSourceOnly && pReposyncArgs->ppszArchs)
    {
        pr_crit("cannot use the source option with arch\n");
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    /* generate list of packages, result will be
       in pPkgInfos */
    dwError = TDNFNativeQueryBuildRepoInputs(
                  pTdnf,
                  &pRepos,
                  &dwNativeRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeListConfig(
                  pRepos,
                  dwNativeRepoCount,
                  pTdnf->pRpmConfig,
                  SCOPE_ALL,
                  NULL,
                  DETAIL_LOCATION,
                  &pPkgInfos,
                  &dwPkgInfoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if (pReposyncArgs->pszDownloadPath == NULL)
    {
        pszRootPath = getcwd(NULL, 0);
        if (!pszRootPath)
        {
            BAIL_ON_TDNF_SYSTEM_ERROR(errno);
        }
    }
    else
    {
        dwError = TDNFNormalizePath(pReposyncArgs->pszDownloadPath, &pszRootPath);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pReposyncArgs->nNewestOnly && pPkgInfos)
    {
        TDNFPkgInfoFilterNewest(pTdnf->pSack, pPkgInfos);
    }

    /* iterate through all packages */
    for (pPkgInfo = pPkgInfos; pPkgInfo; pPkgInfo = pPkgInfo->pNext)
    {
        if (strcmp(pPkgInfo->pszRepoName, SYSTEM_REPO_NAME) == 0)
        {
            continue;
        }
        if (pReposyncArgs->ppszArchs)
        {
            int result = 0;
            TDNFStringMatchesOneOf(pPkgInfo->pszArch, pReposyncArgs->ppszArchs, &result);
            if (result == 0)
            {
                continue;
            }
        }
        else if (pReposyncArgs->nSourceOnly)
        {
            if (strcmp(pPkgInfo->pszArch, "src") != 0)
            {
                continue;
            }
        }

        if (!pReposyncArgs->nPrintUrlsOnly)
        {
            PTDNF_REPO_DATA pPkgRepo = NULL;
            int nKeepPackage = 1;

            if (!pReposyncArgs->nNoRepoPath)
            {
                dwError = TDNFJoinPath(&pszDir,
                                       pszRootPath && strcmp(pszRootPath, "/") ? pszRootPath : "",
                                       pPkgInfo->pszRepoName,
                                       NULL);
                BAIL_ON_TDNF_ERROR(dwError);
            }
            else
            {
                dwError = TDNFAllocateString(pszRootPath, &pszDir);
                BAIL_ON_TDNF_ERROR(dwError);
            }

            dwError = TDNFUtilsMakeDir(pszDir);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFFindRepoById(pTdnf, pPkgInfo->pszRepoName, &pPkgRepo);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFDownloadPackageToTree(pTdnf,
                            pPkgInfo->pszLocation, pPkgInfo->pszName,
                            pPkgRepo, pszDir,
                            &pszFilePath);
            BAIL_ON_TDNF_ERROR(dwError);

            /* if gpgcheck option is given, check for a valid signature. If that fails,
               delete the package */
            if (pReposyncArgs->nGPGCheck)
            {
                TDNF_REPO_DATA stRepoForCheck = *pPkgRepo;
                int nPolicyRejected = 0;

                /*
                 * reposync --gpgcheck is an explicit request, independent of
                 * the repository's normal install gpgcheck setting.
                 */
                stRepoForCheck.nGPGCheck = 1;
                dwError = TDNFGPGCheckPackageEx(
                              pTdnf,
                              &stRepoForCheck,
                              pszFilePath,
                              &pRpmFile,
                              &nPolicyRejected);
                tdnf_rpm_file_close(pRpmFile);
                pRpmFile = NULL;
                if(nPolicyRejected)
                {
                    pr_crit("checking package %s failed: %d, deleting\n",
                            pszFilePath, dwError);
                    if(remove(pszFilePath) < 0)
                    {
                        dwError = errno;
                        pr_crit("unable to remove %s: %s\n",
                                pszFilePath, strerror(dwError));
                        BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
                    }
                    nKeepPackage = 0;
                    dwError = 0;
                }
                else if (dwError)
                {
                    BAIL_ON_TDNF_ERROR(dwError);
                }
            }

            if (pReposyncArgs->nDelete && nKeepPackage)
            {
                /* if "delete" option is given, create a marker file to protect
                   what we just downloaded. Later all *.rpm files that do not
                   have a marker file will be deleted */
                dwError = TDNFAllocateStringPrintf(&pszKeepFile, "%s.reposync-keep", pszFilePath);
                BAIL_ON_TDNF_ERROR(dwError);

                dwError = TDNFTouchFile(pszKeepFile);
                BAIL_ON_TDNF_ERROR(dwError);
                TDNF_SAFE_FREE_MEMORY(pszKeepFile);
            }
            dwError = 0;

            TDNF_SAFE_FREE_MEMORY(pszDir);
            TDNF_SAFE_FREE_MEMORY(pszFilePath);
        }
        else
        {
            /* print URLs only */

            dwError = TDNFFindRepoById(pTdnf, pPkgInfo->pszRepoName, &pRepo);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFCreatePackageUrl(
                                           pRepo,
                                           pPkgInfo->pszLocation,
                                           &pszUrl);
            BAIL_ON_TDNF_ERROR(dwError);

            pr_info("%s\n", pszUrl);

            TDNF_SAFE_FREE_MEMORY(pszUrl);
        }
    }

    if (pReposyncArgs->nDelete)
    {
        /* go through all packages in the destination directory,
           delete those that were not just downloaded as indicated by the
           marker file */
        for (pRepo = pTdnf->pRepos; pRepo; pRepo = pRepo->pNext)
        {
            if ((strcmp(pRepo->pszId, CMDLINE_REPO_NAME) == 0) ||
                (!pRepo->nEnabled))
            {
                continue;
            }

            /* no need to check nNoRepoPath since we wouldn't get here */
            dwError = TDNFJoinPath(&pszRepoDir,
                                   pszRootPath && strcmp(pszRootPath, "/") ? pszRootPath : "",
                                   pRepo->pszId,
                                   NULL);
            BAIL_ON_TDNF_ERROR(dwError);

            ret = nftw(pszRepoDir, _rm_rpms, 10, FTW_DEPTH|FTW_PHYS);
            if (ret < 0)
            {
                dwError = errno;
                BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
            }
            else
            {
                dwError = ret;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
    }

    if (pReposyncArgs->nDownloadMetadata)
    {
        for (pRepo = pTdnf->pRepos; pRepo; pRepo = pRepo->pNext)
        {
            if ((strcmp(pRepo->pszId, CMDLINE_REPO_NAME) == 0) ||
                (!pRepo->nEnabled))
            {
                continue;
            }

            if (!pReposyncArgs->nNoRepoPath)
            {
                const char *pszBasePath = pReposyncArgs->pszMetaDataPath ?
                                pReposyncArgs->pszMetaDataPath : pszRootPath;

                dwError = TDNFJoinPath(&pszRepoDir,
                                       pszBasePath && strcmp(pszBasePath, "/") ? pszBasePath : "",
                                       pRepo->pszId,
                                       NULL);
                BAIL_ON_TDNF_ERROR(dwError);
            }
            else
            {
                dwError = TDNFAllocateString(
                            pReposyncArgs->pszMetaDataPath ?
                                pReposyncArgs->pszMetaDataPath : pszRootPath,
                            &pszRepoDir);
                BAIL_ON_TDNF_ERROR(dwError);
            }

            dwError = TDNFUtilsMakeDir(pszRepoDir);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFDownloadMetadata(pTdnf, pRepo, pszRepoDir,
                                           pReposyncArgs->nPrintUrlsOnly);
            BAIL_ON_TDNF_ERROR(dwError);

            TDNF_SAFE_FREE_MEMORY(pszRepoDir);
        }
    }

cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwNativeRepoCount);
    tdnf_rpm_file_close(pRpmFile);
    TDNF_SAFE_FREE_MEMORY(pszDir);
    TDNF_SAFE_FREE_MEMORY(pszRepoDir);
    TDNF_SAFE_FREE_MEMORY(pszRootPath);
    TDNF_SAFE_FREE_MEMORY(pszKeepFile);
    TDNF_SAFE_FREE_MEMORY(pszFilePath);
    TDNFFreePackageInfoArray(pPkgInfos, dwPkgInfoCount);
    return dwError;
error:
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = ERROR_TDNF_NO_DATA;
    }
    goto cleanup;
}

uint32_t
TDNFRepoQuery(
    PTDNF pTdnf,
    PTDNF_REPOQUERY_ARGS pRepoqueryArgs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    uint32_t dwCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;

    if(!pTdnf || !pTdnf->pSack || !pRepoqueryArgs ||
       !ppPkgInfo || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* check if args make sense. extra packages are installed by definition */
    if (pRepoqueryArgs->nExtras &&
        (pRepoqueryArgs->nInstalled || pRepoqueryArgs->nAvailable ||
         pRepoqueryArgs->nDuplicates))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* duplicate packages are also installed by definition */
    if (pRepoqueryArgs->nDuplicates &&
        (pRepoqueryArgs->nInstalled || pRepoqueryArgs->nAvailable))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* userinstalled implies installed */
    if (pRepoqueryArgs->nUserInstalled)
    {
        pRepoqueryArgs->nInstalled = 1;
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeRepoQueryConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  pRepoqueryArgs,
                  &pPkgInfo,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(pRepoqueryArgs->nUserInstalled)
    {
        dwError = TDNFNativeQueryFilterUserInstalled(pTdnf, pPkgInfo, &dwCount);
        BAIL_ON_TDNF_ERROR(dwError);
        if(!dwCount)
        {
            dwError = ERROR_TDNF_NO_DATA;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    if(pRepoqueryArgs->nLocation)
    {
        dwError = TDNFNativeQueryApplyLocationUrls(pTdnf, pPkgInfo, dwCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppPkgInfo = pPkgInfo;
    *pdwCount = dwCount;

cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = ERROR_TDNF_NO_DATA;
    }
    if(pPkgInfo)
    {
        TDNFFreePackageInfoArray(pPkgInfo, dwCount);
    }
    goto cleanup;
}

uint32_t
TDNFResolve(
    PTDNF pTdnf,
    TDNF_ALTERTYPE nAlterType,
    PTDNF_SOLVED_PKG_INFO* ppSolvedPkgInfo
    )
{
    uint32_t dwError = 0;
    TDNF_ID_LIST queueGoal = {0};
    char** ppszPkgsNotResolved = NULL;
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo = NULL;
    uint64_t qwAvailCacheBytes = 0;
    char **ppszPkgNames = NULL;
    char **ppszPkgFiles = NULL;
    struct cnfnode *pSetOpt = NULL;
    int i = 0;
    int iFiles = 0;
    int iPkgs = 0;
    int nCmdLineUnresolved = 0;

    if(pTdnf)
    {
        TDNFTransactionPlanStateClear(pTdnf->pTransactionPlanState);
        TDNFTransactionPlanRequestTraceDestroy(pTdnf->pRequestTrace);
        pTdnf->pRequestTrace = NULL;
    }
    if(!pTdnf || !ppSolvedPkgInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNF_TRANSACTION_PLAN_REJECT_UNSUPPORTED_RESOLVE(pTdnf, dwError);
    /* Plan v1 cannot identify advisory filters without inventing explicit
       package requests that the caller did not make. */
    if (nAlterType == ALTER_UPGRADEALL &&
        TDNFTransactionPlanStateIsEnabled(pTdnf->pTransactionPlanState))
    {
        for (pSetOpt = pTdnf->pArgs->cn_setopts->first_child;
             pSetOpt;
             pSetOpt = pSetOpt->next)
        {
            if (!strcasecmp(pSetOpt->name, "security") ||
                !strcasecmp(pSetOpt->name, "sec-severity") ||
                !strcasecmp(pSetOpt->name, "reboot-required"))
            {
                dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }

    }
    if (nAlterType == ALTER_INSTALL ||
        nAlterType == ALTER_REINSTALL ||
        nAlterType == ALTER_ERASE)
    {
        if(pTdnf->pArgs->nCmdCount <= 1)
        {
            dwError = ERROR_TDNF_PACKAGE_REQUIRED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    TDNFIdListInit(&queueGoal);

    if(!pTdnf->pArgs->nBuildDeps && !pTdnf->pArgs->nSource &&
       !pTdnf->pArgs->nNoDeps)
    {
        pTdnf->pRequestTrace = TDNFTransactionPlanRequestTraceCreate(nAlterType,
            (const char *const *)(pTdnf->pArgs->ppszCmds + 1),
            pTdnf->pArgs->nCmdCount > 1 ? pTdnf->pArgs->nCmdCount - 1 : 0);
    }

    TDNF_TRANSACTION_PLAN_CHECK_TRACE(pTdnf, dwError);
    TDNF_TRANSACTION_PLAN_REJECT_REPOFROMDIR(pTdnf, dwError);

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    if(nAlterType == ALTER_INSTALL || nAlterType == ALTER_REINSTALL)
    {
        dwError = TDNFAddCmdLinePackages(pTdnf, &queueGoal,
                                         nAlterType, &nCmdLineUnresolved);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  pTdnf->pArgs->nCmdCount,
                  sizeof(char*),
                  (void**)&ppszPkgNames);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  pTdnf->pArgs->nCmdCount,
                  sizeof(char*),
                  (void**)&ppszPkgFiles);
    BAIL_ON_TDNF_ERROR(dwError);

    for (i = 1; i < pTdnf->pArgs->nCmdCount; i++) {
        char *pszPkgName = pTdnf->pArgs->ppszCmds[i];
        if (fnmatch("*.rpm", pszPkgName, 0) == 0) {
            ppszPkgFiles[iFiles++] = pszPkgName;
        } else {
            ppszPkgNames[iPkgs++] = pszPkgName;
        }
    }

    dwError = TDNFAllocateMemory(
                  pTdnf->pArgs->nCmdCount,
                  sizeof(char*),
                  (void**)&ppszPkgsNotResolved);
    BAIL_ON_TDNF_ERROR(dwError);

    if (!pTdnf->pArgs->nBuildDeps) {
        dwError = TDNFPrepareAllPackages(
                      pTdnf,
                      &nAlterType,
                      ppszPkgsNotResolved,
                      &queueGoal);
    } else {
        dwError = TDNFResolveBuildDependencies(
                        pTdnf,
                        ppszPkgNames,
                        ppszPkgsNotResolved,
                        &queueGoal);
    }
    BAIL_ON_TDNF_ERROR(dwError);

    i = 0;
    while(ppszPkgsNotResolved[i])
    {
        i++;
    }

    if (!pTdnf->pArgs->nSource && !pTdnf->pArgs->nNoDeps) {
        dwError = TDNFGoal(
                      pTdnf,
                      &queueGoal,
                      &pSolvedPkgInfo,
                      nAlterType, i + nCmdLineUnresolved);
    } else {
        dwError = TDNFGoalNoDeps(
                      pTdnf,
                      &queueGoal,
                      &pSolvedPkgInfo);
    }
    BAIL_ON_TDNF_ERROR(dwError);

    pSolvedPkgInfo->nNeedAction =
        pSolvedPkgInfo->pPkgsToInstall ||
        pSolvedPkgInfo->pPkgsToUpgrade ||
        pSolvedPkgInfo->pPkgsToDowngrade ||
        pSolvedPkgInfo->pPkgsToRemove  ||
        pSolvedPkgInfo->pPkgsUnNeeded ||
        pSolvedPkgInfo->pPkgsToReinstall ||
        pSolvedPkgInfo->pPkgsObsoleted;

    pSolvedPkgInfo->nNeedDownload =
        pSolvedPkgInfo->pPkgsToInstall ||
        pSolvedPkgInfo->pPkgsToUpgrade ||
        pSolvedPkgInfo->pPkgsToDowngrade ||
        pSolvedPkgInfo->pPkgsToReinstall;

    dwError = TDNFGetAvailableCacheBytes(pTdnf->pConf, &qwAvailCacheBytes);
    BAIL_ON_TDNF_ERROR(dwError);

    if (pSolvedPkgInfo->nNeedDownload)
    {
        dwError = TDNFCheckDownloadCacheBytes(pSolvedPkgInfo, qwAvailCacheBytes);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNF_TRANSACTION_PLAN_PUBLISH(pTdnf, dwError);
    pSolvedPkgInfo->ppszPkgsNotResolved = ppszPkgsNotResolved;
    *ppSolvedPkgInfo = pSolvedPkgInfo;

cleanup:
    TDNF_SAFE_FREE_MEMORY(ppszPkgNames);
    TDNF_SAFE_FREE_MEMORY(ppszPkgFiles);

    TDNFIdListFree(&queueGoal);
    return dwError;

error:
    TDNF_TRANSACTION_PLAN_HANDLE_RESOLVE_ERROR(pTdnf);
    if(ppSolvedPkgInfo)
    {
        *ppSolvedPkgInfo = NULL;
    }
    if(pSolvedPkgInfo)
    {
        TDNFFreeSolvedPackageInfo(pSolvedPkgInfo);
    }
    TDNF_SAFE_FREE_STRINGARRAY(ppszPkgsNotResolved);
    goto cleanup;
}

uint32_t
TDNFSearchCommand(
    PTDNF pTdnf,
    PTDNF_CMD_ARGS pCmdArgs,
    PTDNF_PKG_INFO* ppPkgInfo,
    uint32_t* punCount
    )
{
    uint32_t dwError = 0;
    int nStartArgIndex = 1;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    uint32_t unCount  = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    if(!pTdnf || !pCmdArgs || !ppPkgInfo || !punCount || !pTdnf->pSack)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pCmdArgs->nCmdCount > 1)
    {
        if(!strncasecmp(pCmdArgs->ppszCmds[1], "all", 3))
        {
            nStartArgIndex = 2;
        }
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeSearchConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  pCmdArgs->ppszCmds,
                  nStartArgIndex,
                  pCmdArgs->nCmdCount,
                  &pPkgInfo,
                  &unCount);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppPkgInfo = pPkgInfo;
    *punCount = unCount;

cleanup:
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    if(dwError == ERROR_TDNF_NO_MATCH)
    {
        dwError = ERROR_TDNF_NO_SEARCH_RESULTS;
    }
    if(ppPkgInfo)
    {
        *ppPkgInfo = NULL;
    }
    if(punCount)
    {
        *punCount = 0;
    }
    TDNFFreePackageInfoArray(pPkgInfo, unCount);

    goto cleanup;
}

//TODO: Refactor UpdateInfoSummary into one function
uint32_t
TDNFUpdateInfo(
    PTDNF pTdnf,
    char** ppszPackageNameSpecs,
    PTDNF_UPDATEINFO* ppUpdateInfo
    )
{
    uint32_t dwError = 0;
    uint32_t dwRebootRequired = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    char **ppszLines = NULL;
    uint32_t dwLineCount = 0;
    PTDNF_UPDATEINFO pUpdateInfos = NULL;
    char*  pszSeverity = NULL;
    uint32_t dwSecurity = 0;

    if(!pTdnf || !pTdnf->pSack || !pTdnf->pSack->pPool ||
       !ppUpdateInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRefresh(pTdnf);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFGetSecuritySeverityOption(
                  pTdnf,
                  &dwSecurity,
                  &pszSeverity);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFGetRebootRequiredOption(
                  pTdnf,
                  &dwRebootRequired);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeUpdateInfoLinesConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  ppszPackageNameSpecs,
                  dwSecurity,
                  pszSeverity,
                  dwRebootRequired,
                  &ppszLines,
                  &dwLineCount);
    if(dwError == ERROR_TDNF_NO_DATA)
    {
        pr_info("\n0 updates.\n");
    }
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQueryBuildUpdateInfo(ppszLines, dwLineCount, &pUpdateInfos);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppUpdateInfo = pUpdateInfos;

cleanup:
    TDNFFreeStringArray(ppszLines);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    TDNF_SAFE_FREE_MEMORY(pszSeverity);
    return dwError;

error:
    if(ppUpdateInfo)
    {
        *ppUpdateInfo = NULL;
    }
    if(pUpdateInfos)
    {
        TDNFFreeUpdateInfo(pUpdateInfos);
    }
    goto cleanup;
}

uint32_t
TDNFHistoryResolve(
    PTDNF pTdnf,
    PTDNF_HISTORY_ARGS pHistoryArgs,
    PTDNF_SOLVED_PKG_INFO *ppSolvedPkgInfo)
{
    uint32_t dwError = 0;
    int rc = 0;
    char **ppszPkgsNotResolved = NULL;
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo = NULL;
    struct history_ctx *ctx = NULL;
    struct history_delta *hd = NULL;
    struct history_flags_delta *hfd = NULL;
    struct history_nevra_map *hnm = NULL;
    TDNF_ID_LIST qInstall = {0};
    TDNF_ID_LIST qErase = {0};
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    uint32_t dwUnresolvedCount = 0;
    char **ppszMatches = NULL;
    uint32_t dwMatchCount = 0;
    uint32_t nTraceStart = 0;
    int nHistoryOutcome = 0;

    if(pTdnf)
    {
        TDNFTransactionPlanStateClear(pTdnf->pTransactionPlanState);
        TDNFTransactionPlanRequestTraceDestroy(pTdnf->pRequestTrace);
        pTdnf->pRequestTrace = NULL;
    }
    if(!pTdnf || !pHistoryArgs || !ppSolvedPkgInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pHistoryArgs->nCommand == HISTORY_CMD_ROLLBACK)
    {
        if (pHistoryArgs->nTo <= 0)
        {
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }
    else if (pHistoryArgs->nCommand == HISTORY_CMD_UNDO ||
             pHistoryArgs->nCommand == HISTORY_CMD_REDO)
    {
        if (pHistoryArgs->nFrom <= 1 || /* cannot undo or redo the base set */
            pHistoryArgs->nFrom > pHistoryArgs->nTo)
        {
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }
    else if (pHistoryArgs->nCommand != HISTORY_CMD_INIT)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pHistoryArgs->nCommand != HISTORY_CMD_INIT)
    {
        pTdnf->pRequestTrace =
            TDNFTransactionPlanRequestTraceCreateHistory();
        TDNF_TRANSACTION_PLAN_CHECK_TRACE(pTdnf, dwError);
    }

    /* no need to refresh cache when initializing db */
    if (pHistoryArgs->nCommand != HISTORY_CMD_INIT)
    {
        TDNF_TRANSACTION_PLAN_REJECT_REPOFROMDIR(pTdnf, dwError);
        dwError = TDNFRefresh(pTdnf);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &ctx,
                                pHistoryArgs->nCommand != HISTORY_CMD_INIT);
    BAIL_ON_TDNF_ERROR(dwError);

    rc = history_sync_config(ctx, pTdnf->pRpmConfig);
    if (rc != 0)
    {
        dwError = ERROR_TDNF_HISTORY_ERROR;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    switch (pHistoryArgs->nCommand)
    {
        case HISTORY_CMD_INIT:
            goto cleanup;
        case HISTORY_CMD_ROLLBACK:
            hd = history_get_delta(ctx, pHistoryArgs->nTo);
            hfd = history_get_flags_delta(ctx, history_get_current_transaction_id(ctx), pHistoryArgs->nTo);
            break;
        case HISTORY_CMD_UNDO:
            hd = history_get_delta_range(ctx, pHistoryArgs->nFrom - 1, pHistoryArgs->nTo);
            hfd = history_get_flags_delta(ctx, pHistoryArgs->nTo, pHistoryArgs->nFrom - 1);
            break;
        case HISTORY_CMD_REDO:
            hd = history_get_delta_range(ctx, pHistoryArgs->nTo, pHistoryArgs->nFrom - 1);
            hfd = history_get_flags_delta(ctx, pHistoryArgs->nFrom - 1, pHistoryArgs->nTo);
            break;
        default:
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
    }

    if (hd == NULL)
    {
        dwError = ERROR_TDNF_HISTORY_ERROR;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (hd->added_count > 0)
    {
        dwError = TDNFAllocateMemory(
                      hd->added_count+1, /* only added pkgs, plus a NULL ptr */
                      sizeof(char*),
                      (void**)&ppszPkgsNotResolved);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    hnm = history_nevra_map(ctx);
    if (hnm == NULL)
    {
        dwError = ERROR_TDNF_HISTORY_ERROR;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    TDNFIdListInit(&qInstall);
    TDNFIdListInit(&qErase);

    for (int i = 0; i < hd->added_count; i++)
    {
        const char *pszPkgName = history_get_nevra(hnm, hd->added_ids[i]);
        if (pszPkgName)
        {
            TDNF_ID_LIST qResult = {0};

            nHistoryOutcome = TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED;
            if (strncmp(pszPkgName, "gpg-pubkey-", 11) == 0)
            {
                continue;
            }

            nTraceStart = qInstall.dwCount;
            TDNFIdListInit(&qResult);

            dwError = TDNFRepoMdNativeFindNevraMatchesConfig(
                          pRepos,
                          dwRepoCount,
                          pTdnf->pRpmConfig,
                          pszPkgName,
                          SOLV_NEVRA_UNINSTALLED,
                          &ppszMatches,
                          &dwMatchCount);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFNativeQueryResolvePackageRefArrayToQueue(
                          pTdnf->pSack,
                          ppszMatches,
                          dwMatchCount,
                          0,
                          &qResult);
            BAIL_ON_TDNF_ERROR(dwError);

            if (qResult.dwCount == 0)
            {
                dwError = TDNFAddNotResolved(ppszPkgsNotResolved, pszPkgName);
                BAIL_ON_TDNF_ERROR(dwError);
                nHistoryOutcome =
                    TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_NO_CANDIDATE;
                dwUnresolvedCount++;
            }
            else
            {
                TDNF_ID_LIST qInstalled = {0};
                TDNFIdListInit(&qInstalled);

                /* find if pkg is already installed */
                TDNFFreeStringArray(ppszMatches);
                ppszMatches = NULL;
                dwMatchCount = 0;

                dwError = TDNFRepoMdNativeFindNevraMatchesConfig(
                              pRepos,
                              dwRepoCount,
                              pTdnf->pRpmConfig,
                              pszPkgName,
                              SOLV_NEVRA_INSTALLED,
                              &ppszMatches,
                              &dwMatchCount);
                BAIL_ON_TDNF_ERROR(dwError);

                dwError = TDNFNativeQueryResolvePackageRefArrayToQueue(
                              pTdnf->pSack,
                              ppszMatches,
                              dwMatchCount,
                              1,
                              &qInstalled);
                BAIL_ON_TDNF_ERROR(dwError);

                if (qInstalled.dwCount == 0)
                {
                    /* We may have found multiples if they occur in multiple
                       repos. Take the first one. */
                    dwError = TDNFIdListPush(&qInstall, qResult.pnElements[0]);
                    BAIL_ON_TDNF_ERROR(dwError);
                    nHistoryOutcome = TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_QUEUED;
                }
                TDNFIdListFree(&qInstalled);
            }
            TDNFFreeStringArray(ppszMatches);
            ppszMatches = NULL;
            dwMatchCount = 0;
            TDNFIdListFree(&qResult);
            TDNFTransactionPlanRequestTraceRecordHistoryGoal(pTdnf->pRequestTrace, pszPkgName,
                TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_INSTALL, TDNF_TRANSACTION_PLAN_CAPTURE_JOB_INSTALL,
                qInstall.pnElements, nTraceStart, qInstall.dwCount, nHistoryOutcome);
        }
        else
        {
            dwError = ERROR_TDNF_HISTORY_ERROR;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    for (int i = 0; i < hd->removed_count; i++)
    {
        const char *pszPkgName = history_get_nevra(hnm, hd->removed_ids[i]);
        if (pszPkgName)
        {
            if (strncmp(pszPkgName, "gpg-pubkey-", 11) == 0)
                continue;

            nTraceStart = qErase.dwCount;
            dwError = TDNFRepoMdNativeFindNevraMatchesConfig(
                          pRepos,
                          dwRepoCount,
                          pTdnf->pRpmConfig,
                          pszPkgName,
                          SOLV_NEVRA_INSTALLED,
                          &ppszMatches,
                          &dwMatchCount);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFNativeQueryResolvePackageRefArrayToQueue(
                          pTdnf->pSack,
                          ppszMatches,
                          dwMatchCount,
                          1,
                          &qErase);
            BAIL_ON_TDNF_ERROR(dwError);
            nHistoryOutcome = qErase.dwCount == nTraceStart
                ? TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED
                : TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_QUEUED;

            TDNFFreeStringArray(ppszMatches);
            ppszMatches = NULL;
            dwMatchCount = 0;
            TDNFTransactionPlanRequestTraceRecordHistoryGoal(pTdnf->pRequestTrace, pszPkgName,
                TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_ERASE, TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ERASE,
                qErase.pnElements, nTraceStart, qErase.dwCount, nHistoryOutcome);
        }
        else
        {
            dwError = ERROR_TDNF_HISTORY_ERROR;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    dwError = TDNFHistoryGoalWithUnresolved(
                  pTdnf,
                  &qInstall,
                  &qErase,
                  dwUnresolvedCount,
                  &pSolvedPkgInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    pSolvedPkgInfo->nNeedAction =
        pSolvedPkgInfo->pPkgsToInstall ||
        pSolvedPkgInfo->pPkgsToUpgrade ||
        pSolvedPkgInfo->pPkgsToDowngrade ||
        pSolvedPkgInfo->pPkgsToRemove  ||
        pSolvedPkgInfo->pPkgsUnNeeded ||
        pSolvedPkgInfo->pPkgsToReinstall ||
        pSolvedPkgInfo->pPkgsObsoleted;

    pSolvedPkgInfo->nNeedDownload =
        pSolvedPkgInfo->pPkgsToInstall ||
        pSolvedPkgInfo->pPkgsToUpgrade ||
        pSolvedPkgInfo->pPkgsToDowngrade ||
        pSolvedPkgInfo->pPkgsToReinstall;

    /* if there is no action, maybe there is a flags change */
    if (!pSolvedPkgInfo->nNeedAction)
    {
        pSolvedPkgInfo->nNeedAction = hfd && hfd->count > 0;
    }

    TDNF_TRANSACTION_PLAN_PUBLISH(pTdnf, dwError);
    pSolvedPkgInfo->ppszPkgsNotResolved = ppszPkgsNotResolved;
    *ppSolvedPkgInfo = pSolvedPkgInfo;

cleanup:
    history_free_nevra_map(hnm);
    history_free_delta(hd);
    history_free_flags_delta(hfd);
    destroy_history_ctx(ctx);
    TDNFFreeStringArray(ppszMatches);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    TDNFIdListFree(&qInstall);
    TDNFIdListFree(&qErase);
    return dwError;

error:
    TDNF_TRANSACTION_PLAN_HANDLE_RESOLVE_ERROR(pTdnf);
    if(pSolvedPkgInfo)
    {
        TDNFFreeSolvedPackageInfo(pSolvedPkgInfo);
    }
    if(ppszPkgsNotResolved)
    {
        TDNFFreeStringArray(ppszPkgsNotResolved);
    }
    goto cleanup;
}

uint32_t
TDNFHistoryList(
    PTDNF pTdnf,
    PTDNF_HISTORY_ARGS pHistoryArgs,
    PTDNF_HISTORY_INFO *ppHistoryInfo)
{
    uint32_t dwError = 0;
    struct history_transaction *tas = NULL;
    struct history_nevra_map *hnm = NULL;
    int count = 0;
    PTDNF_HISTORY_INFO pHistoryInfo = NULL;
    PTDNF_HISTORY_INFO_ITEM pHistoryInfoItems = NULL;
    struct history_ctx *ctx = NULL;
    int rc = 0;

    if(!pTdnf || !pHistoryArgs || !ppHistoryInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pHistoryArgs->nFrom < 0 || pHistoryArgs->nTo < 0)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pHistoryArgs->nFrom != 0 && pHistoryArgs->nTo != 0)
    {
        if (pHistoryArgs->nFrom > pHistoryArgs->nTo)
        {
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &ctx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    rc = history_get_transactions(ctx, &tas, &count,
                             pHistoryArgs->nReverse,
                             pHistoryArgs->nFrom, pHistoryArgs->nTo);
    if (rc != 0)
    {
        dwError = ERROR_TDNF_HISTORY_ERROR;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  count,
                  sizeof(TDNF_HISTORY_INFO_ITEM),
                  (void**)&pHistoryInfoItems);
    BAIL_ON_TDNF_ERROR(dwError);

    if (pHistoryArgs->nInfo)
    {
        hnm = history_nevra_map(ctx);
    }

    for(int i = 0; i < count; i++)
    {
        pHistoryInfoItems[i].nId = tas[i].id;
        pHistoryInfoItems[i].nType = tas[i].type;
        dwError = TDNFAllocateString(tas[i].cmdline ?
            tas[i].cmdline :
            "(none)",
            &pHistoryInfoItems[i].pszCmdLine);
        BAIL_ON_TDNF_ERROR(dwError);
        pHistoryInfoItems[i].timeStamp = tas[i].timestamp;
        pHistoryInfoItems[i].nAddedCount = tas[i].delta.added_count;
        pHistoryInfoItems[i].nRemovedCount = tas[i].delta.removed_count;

        if (!hnm)
            continue;

        if (tas[i].delta.added_count > 0)
        {
            dwError = TDNFAllocateMemory(tas[i].delta.added_count,
                                         sizeof(char *),
                                         (void **)&pHistoryInfoItems[i].ppszAddedPkgs);
            BAIL_ON_TDNF_ERROR(dwError);
            for (int j = 0; j < tas[i].delta.added_count; j++)
            {
                dwError = TDNFAllocateString(history_get_nevra(hnm, tas[i].delta.added_ids[j]),
                        &pHistoryInfoItems[i].ppszAddedPkgs[j]);
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }

        if (tas[i].delta.removed_count > 0)
        {
            dwError = TDNFAllocateMemory(tas[i].delta.removed_count,
                                         sizeof(char *),
                                         (void **)&pHistoryInfoItems[i].ppszRemovedPkgs);
            BAIL_ON_TDNF_ERROR(dwError);
            for (int j = 0; j < tas[i].delta.removed_count; j++)
            {
                dwError = TDNFAllocateString(history_get_nevra(hnm, tas[i].delta.removed_ids[j]),
                        &pHistoryInfoItems[i].ppszRemovedPkgs[j]);
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
    }

    dwError = TDNFAllocateMemory(
                  count,
                  sizeof(TDNF_HISTORY_INFO),
                  (void**)&pHistoryInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    pHistoryInfo->nItemCount = count;
    pHistoryInfo->pItems = pHistoryInfoItems;
    *ppHistoryInfo = pHistoryInfo;

cleanup:
    history_free_nevra_map(hnm);
    history_free_transactions(tas, count);
    destroy_history_ctx(ctx);
    return dwError;

error:
    if (pHistoryInfoItems)
    {
        TDNFFreeHistoryInfoItems(pHistoryInfoItems, count);
    }
    goto cleanup;
}

uint32_t
TDNFGetPackageUrls(
    PTDNF pTdnf,
    PTDNF_SOLVED_PKG_INFO pSolvedPkgInfo,
    char ***pppszUrls,
    int *pnCount)
{
    uint32_t dwError = 0;
    PTDNF_PKG_INFO pInfo = NULL;
    PTDNF_REPO_DATA pRepo = NULL;
    char **ppszUrls = NULL;
    char *pszUrl = NULL;
    int nCount = 0;
    int nIndex = 0;

    /* lists that require downloading RPMs */
    PTDNF_PKG_INFO *apLists[] = {
        &pSolvedPkgInfo->pPkgsToInstall,
        &pSolvedPkgInfo->pPkgsToUpgrade,
        &pSolvedPkgInfo->pPkgsToDowngrade,
        &pSolvedPkgInfo->pPkgsToReinstall,
    };

    if (!pTdnf || !pSolvedPkgInfo || !pppszUrls || !pnCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for (int i = 0; i < (int)(sizeof(apLists)/sizeof(apLists[0])); i++)
    {
        for (pInfo = *apLists[i]; pInfo; pInfo = pInfo->pNext)
        {
            /* skip local packages (absolute path) */
            if (!IsNullOrEmptyString(pInfo->pszLocation) &&
                pInfo->pszLocation[0] != '/')
            {
                nCount++;
            }
        }
    }

    dwError = TDNFAllocateMemory(nCount + 1, sizeof(char *), (void **)&ppszUrls);
    BAIL_ON_TDNF_ERROR(dwError);

    for (int i = 0; i < (int)(sizeof(apLists)/sizeof(apLists[0])); i++)
    {
        for (pInfo = *apLists[i]; pInfo; pInfo = pInfo->pNext)
        {
            if (IsNullOrEmptyString(pInfo->pszLocation) ||
                pInfo->pszLocation[0] == '/')
            {
                continue;
            }

            dwError = TDNFFindRepoById(pTdnf, pInfo->pszRepoName, &pRepo);
            BAIL_ON_TDNF_ERROR(dwError);

            dwError = TDNFCreatePackageUrl(pRepo, pInfo->pszLocation, &pszUrl);
            BAIL_ON_TDNF_ERROR(dwError);

            ppszUrls[nIndex++] = pszUrl;
            pszUrl = NULL;
        }
    }

    *pppszUrls = ppszUrls;
    *pnCount = nCount;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszUrl);
    return dwError;

error:
    TDNFFreeStringArray(ppszUrls);
    goto cleanup;
}

uint32_t
TDNFHistoryGetId(
    PTDNF pTdnf,
    int *pnId)
{
    uint32_t dwError = 0;
    struct history_ctx *ctx = NULL;

    if (!pTdnf || !pnId)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &ctx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    *pnId = history_get_current_transaction_id(ctx);

cleanup:
    destroy_history_ctx(ctx);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFMark(
    PTDNF pTdnf,
    char** ppszPackageNameSpecs,
    uint32_t dwValue
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;
    PTDNF_PKG_INFO pPkgInfos = NULL;
    struct history_ctx *ctx = NULL;
    char *pszCmdLine = NULL;

    if(!pTdnf || !pTdnf->pSack || !ppszPackageNameSpecs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdNativeListConfig(
                  NULL,
                  0,
                  pTdnf->pRpmConfig,
                  SCOPE_INSTALLED,
                  ppszPackageNameSpecs,
                  DETAIL_LIST,
                  &pPkgInfos,
                  &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if (dwCount > 0)
    {
        dwError = TDNFJoinArrayToString(&(pTdnf->pArgs->ppszArgv[1]),
                                        " ",
                                        pTdnf->pArgs->nArgc,
                                        &pszCmdLine);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFGetHistoryCtx(pTdnf, &ctx, 1);
        BAIL_ON_TDNF_ERROR(dwError);

        history_add_transaction(ctx, pszCmdLine);
        BAIL_ON_TDNF_ERROR(dwError);

        for (dwIndex = 0; dwIndex < dwCount; dwIndex++)
        {
            int rc;

            pr_info("marking %s as %sinstalled\n",
                    pPkgInfos[dwIndex].pszName,
                    dwValue ? "auto" : "user");

            rc = history_set_auto_flag(ctx, pPkgInfos[dwIndex].pszName, dwValue);
            if (rc != 0)
            {
                dwError = ERROR_TDNF_HISTORY_ERROR;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
    }
    else
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszCmdLine);
    destroy_history_ctx(ctx);
    if(pPkgInfos)
    {
        TDNFFreePackageInfoArray(pPkgInfos, dwCount);
    }
    return dwError;
error:
    goto cleanup;
}

//api calls to free memory allocated by tdnfclientlib
void
TDNFCloseHandle(
    PTDNF pTdnf
    )
{
    if(pTdnf)
    {
        if(pTdnf->pRepos)
        {
            TDNFFreeReposInternal(pTdnf->pRepos);
        }
        if(pTdnf->pConf)
        {
            TDNFFreeConfig(pTdnf->pConf);
        }
        if(pTdnf->pSack)
        {
            SolvFreeSack(pTdnf->pSack);
        }
        tdnf_rpm_config_destroy(pTdnf->pRpmConfig);
        TDNFFreePlugins(pTdnf->pPlugins);
        TDNF_SAFE_FREE_STRINGARRAY(pTdnf->ppszRepoFromDirIds);
        TDNF_SAFE_FREE_STRINGARRAY(pTdnf->ppszHiddenRefs);
        pTdnf->dwHiddenRefCount = 0;
        TDNFTransactionPlanRequestTraceDestroy(pTdnf->pRequestTrace);
        TDNFTransactionPlanStateDestroy(pTdnf->pTransactionPlanState);
        TDNFFreeMemory(pTdnf);
    }
    TdnfExitHandler();
}

const char*
TDNFGetVersion(void)
{
    return PACKAGE_VERSION;
}

const char*
TDNFGetPackageName(void)
{
    return PACKAGE_NAME;
}
