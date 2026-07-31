/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

static
uint32_t
TDNFGoalSolveNative(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase, int nStampFlags, int nStampedJobCount, int nReInstall,
    PTDNF_SOLVED_PKG_INFO *ppInfo,
    int nPrepareOnly,
    int nRefuteUnsat,
    int nDropProtected,
    void **ppHandle
);

static
uint32_t
TDNFGoalCaptureNativeSolve(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase, int nStampFlags, int nStampedJobCount,
    int nPrepareOnly,
    int nRefuteUnsat,
    int nDropProtected,
    void **ppHandle
);

static
uint32_t
TDNFGoalBuildNativeSolverRepoInputs(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 *ppRepos,
    uint32_t *pdwRepoCount
);

static
void
TDNFGoalFreeNativeSolverRepoInputs(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 pRepos,
    uint32_t dwRepoCount
);

static
uint32_t
TDNFGoalBuildNativeSolverJobs(
    PTDNF pTdnf, const TDNF_ID_LIST *pQueueJobs, int nStampFlags, int nStampedJobCount,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppJobs, uint32_t *pdwJobCount,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppEraseJobs, uint32_t *pdwEraseJobCount,
    char ***pppszInstallOnlyPkgs, char ***pppszUserInstalledPkgs,
    char ***pppszLockedPkgs, uint32_t **ppdwLockedQueuePairs,
    char ***pppszCmdLinePaths,
    int *pnUpdateAll, int *pnDistSyncAll,
    uint32_t *pdwGlobalQueuePair, int *pnHasGlobalQueuePair
);
static
void
TDNFGoalFreeNativeSolverJobs(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs,
    uint32_t dwJobCount
);

static
int
TDNFGoalIsNativeSolverPackage(
    Pool *pPool,
    Solvable *pSolvable
);

static
uint32_t
TDNFGoalBuildNativeSolverHiddenAvailable(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppHiddenAvailable,
    uint32_t *pdwHiddenAvailableCount
);

static
uint32_t
TDNFReportProblemsNative(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase,
    int nStampFlags,
    int nStampedJobCount,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
);

static
uint32_t
TDNFGoalFindProtectedInTransaction(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase,
    int nStampFlags,
    int nStampedJobCount,
    const char **ppszName,
    const char **ppszAction
);

static
const char *
TDNFFindProtectedPkg(
    char **ppszProtectedPkgs,
    PTDNF_PKG_INFO pPkgs
);

#define TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(_tdnf, _jobs, _allow_erasing, _auto_erase, _flags, _stamped_count, _prepare_only, _refute_unsat, _drop_protected, _native, _error) \
    do {                                                                 \
        uint32_t _saved_error = (_error);                                \
        (_error) = TDNFGoalCaptureNativeSolve((_tdnf), (_jobs), (_allow_erasing), (_auto_erase), (_flags), (_stamped_count), (_prepare_only), (_refute_unsat), (_drop_protected), (_native)); \
        if ((_error)) { TDNFTransactionPlanStateClear((_tdnf)->pTransactionPlanState); (_error) = _saved_error; BAIL_ON_TDNF_ERROR(_error); } \
        (_error) = _saved_error;                                         \
        TDNFTransactionPlanRequestTraceFinalize((_tdnf)->pRequestTrace, (_jobs)->pnElements, (_jobs)->dwCount, SOLVER_CLEANDEPS, SOLVER_FORCEBEST); \
    } while (0)

static uint32_t
TDNFAddUserInstalledToJobs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs
    )
{
    uint32_t dwError = 0;
    struct history_ctx *pHistoryCtx = NULL;
    uint32_t nTraceStart = 0;

    if(!pTdnf || !pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &pHistoryCtx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    nTraceStart = pQueueJobs->dwCount;
    dwError = SolvAddUserInstalledToJobs(pQueueJobs,
                                         pTdnf->pSack->pPool,
                                         pHistoryCtx);
    BAIL_ON_TDNF_ERROR(dwError);
    TDNFTransactionPlanRequestTraceRecordPackageJobRange(pTdnf->pRequestTrace, pQueueJobs->pnElements,
        nTraceStart, pQueueJobs->dwCount, TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
        TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
cleanup:
    if (pHistoryCtx)
    {
        destroy_history_ctx(pHistoryCtx);
    }
    return dwError;
error:
    goto cleanup;
}

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN
uint32_t
TDNFSolv(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    char** ppszExcludes,
    uint32_t dwExcludeCount,
    int nAllowErasing,
    int nAutoErase,
    int nReInstall, int nUnresolved,
    PTDNF_SOLVED_PKG_INFO* ppInfo
    )
{
    uint32_t dwError = 0;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem = SKIPPROBLEM_NONE;
    int nFlags = 0;
    int nStampedJobCount = 0;
    void *pNativeSolve = NULL;

    if(!pTdnf || !ppInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNFTransactionPlanRequestTraceRecordPolicies(pTdnf->pRequestTrace, (const char *const *)ppszExcludes,
        (const char *const *)pTdnf->pConf->ppszInstallOnlyPkgs, (const char *const *)pTdnf->pConf->ppszPkgLocks,
        (const char *const *)pTdnf->pConf->ppszMinVersions,
        (const char *const *)pTdnf->pConf->ppszProtectedPkgs, nAllowErasing);
    if(pTdnf->pArgs->nBest)
    {
        nFlags = nFlags | SOLVER_FORCEBEST;
    }
    if (nAutoErase)
    {
        nFlags = nFlags | SOLVER_CLEANDEPS;
    }

    nStampedJobCount = pQueueJobs->dwCount;
    /* Stamp the solver flags onto the 'how' half of every job queued so far.
       Everything appended after this point carries its own flags, which is
       what nStampedJobCount records for the native job builder. */
    for (uint32_t dwJob = 0; dwJob < pQueueJobs->dwCount; dwJob += 2)
    {
        pQueueJobs->pnElements[dwJob] |= nFlags;
    }

    if (dwExcludeCount != 0 && ppszExcludes)
    {
        if (!pTdnf->pSack || !pTdnf->pSack->pPool)
        {
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        dwError = SolvAddExcludes(pTdnf->pSack->pPool, ppszExcludes);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFSolvAddInstallOnlyPkgs(pTdnf, pQueueJobs, pTdnf->pSack->pPool);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFSolvAddPkgLocks(pTdnf, pQueueJobs, pTdnf->pSack->pPool);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFSolvAddMinVersions(pTdnf, pTdnf->pSack->pPool);
    BAIL_ON_TDNF_ERROR(dwError);

    if(nAllowErasing && pTdnf->pConf->ppszProtectedPkgs)
    {
        dwError = TDNFSolvAddProtectPkgs(pTdnf, pQueueJobs, pTdnf->pSack->pPool);
        if (dwError == ERROR_TDNF_PROTECTED)
        {
            /* Nothing has been solved yet, so the plan describes the
               request and the packages it names. */
            TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(pTdnf, pQueueJobs, nAllowErasing, nAutoErase, nFlags, nStampedJobCount, 1, 0, 0, &pNativeSolve, dwError);
            TDNF_TRANSACTION_PLAN_CAPTURE_TERMINAL_PROBLEM(
                pTdnf, pNativeSolve, nUnresolved,
                TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_PROTECTED_PACKAGE,
                ppszExcludes, nAllowErasing, nAutoErase, dwError);
        }
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* --debugsolver used to dump libsolv's internal testcase into ./debugdata.
       There is no libsolv solve left to dump and the native solver has no
       equivalent, so the flag is still parsed and accepted -- scripts passing
       it keep working -- but says so rather than silently doing nothing.
       Deleting this block is all it takes to retire the notice; deleting the
       option entry in tools/cli/lib/parseargs.zig and its help.txt line as
       well is all it takes to retire the flag. */
    if(pTdnf->pArgs->nDebugSolver)
    {
        pr_err("--debugsolver: solver debug data is no longer produced; "
               "the native solver has no libsolv testcase to write\n");
    }

    dwError = TDNFGoalSolveNative(pTdnf, pQueueJobs, nAllowErasing, nAutoErase,
                                  nFlags, nStampedJobCount, nReInstall, &pInfo,
                                  0, 0, 0,
                                  TDNFTransactionPlanStateIsEnabled(
                                      pTdnf->pTransactionPlanState)
                                      ? &pNativeSolve : NULL);
    if(dwError == ERROR_TDNF_PROTECTED ||
       (dwError == ERROR_TDNF_CALL_NOT_SUPPORTED &&
        pTdnf->pConf->ppszProtectedPkgs))
    {
        /* The second case is the native solver refusing a policy combination
           outright -- today, skip-broken together with protected packages.
           libsolv did not honour protection during the solve either: it
           produced a transaction regardless and
           TDNFSolvCheckProtectPkgsInTrans rejected it afterwards. Asking the
           same question here keeps that answer: if the transaction the
           request would have had removes a protected package, that is what
           the user is told. If it does not, the refusal stands untouched. */
        const char *pszProtected = NULL;
        const char *pszAction = NULL;
        uint32_t dwFind = 0;

        dwFind = TDNFGoalFindProtectedInTransaction(pTdnf, pQueueJobs,
                                                    nAllowErasing, nAutoErase,
                                                    nFlags, nStampedJobCount,
                                                    &pszProtected, &pszAction);
        if(pszProtected)
        {
            pr_err("package %s would be %s but it is protected\n",
                   pszProtected, pszAction);
            dwError = ERROR_TDNF_PROTECTED;
        }
        else if(dwError == ERROR_TDNF_PROTECTED)
        {
            pr_err("a protected package blocks this transaction but it could "
                   "not be named (%u)\n", dwFind);
        }
    }

    if(dwError == ERROR_TDNF_SOLV_FAILED)
    {
        /* The request has no solution. Which problems the user is shown
           depends on the skip options, and a skip option that hides every
           problem leaves nothing to print -- but it does not make the request
           solvable, so the failure stands. */
        uint32_t dwReported = 0;

        dwError = TDNFGetSkipProblemOption(pTdnf, &dwSkipProblem);
        BAIL_ON_TDNF_ERROR(dwError);
        dwReported = TDNFReportProblemsNative(pTdnf, pQueueJobs, nAllowErasing,
                                              nAutoErase, nFlags, nStampedJobCount,
                                              dwSkipProblem);
        if(!dwReported)
        {
            pr_err("The request cannot be resolved. Every problem found was "
                   "hidden by a skip option.\n");
            dwReported = ERROR_TDNF_SOLV_FAILED;
        }
        dwError = dwReported;
        TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(pTdnf, pQueueJobs, nAllowErasing, nAutoErase, nFlags, nStampedJobCount, 0, 1, 0, &pNativeSolve, dwError);
        TDNF_TRANSACTION_PLAN_CAPTURE_FAILED_SOLVE(
            pTdnf, pNativeSolve, nUnresolved, ppszExcludes,
            nAllowErasing, nAutoErase, dwError);
    }
    else if(dwError == ERROR_TDNF_PROTECTED)
    {
        /* The capture solve drops the protected names for the same reason
           TDNFGoalFindProtectedInTransaction does: it reproduces the very
           transaction whose protected removal is being reported, while the
           captured environment still records the protection policy so the
           offending action is recognised as protected. */
        TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(pTdnf, pQueueJobs, nAllowErasing, nAutoErase, nFlags, nStampedJobCount, 0, 0, 1, &pNativeSolve, dwError);
        TDNF_TRANSACTION_PLAN_CAPTURE_TERMINAL_PROBLEM(
            pTdnf, pNativeSolve, nUnresolved,
            TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_PROTECTED_PACKAGE,
            ppszExcludes, nAllowErasing, nAutoErase, dwError);
    }
    else if(dwError == ERROR_TDNF_INSTALLONLY_LIMIT_EXCEEDED)
    {
        TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(pTdnf, pQueueJobs, nAllowErasing, nAutoErase, nFlags, nStampedJobCount, 0, 0, 0, &pNativeSolve, dwError);
        TDNF_TRANSACTION_PLAN_CAPTURE_TERMINAL_PROBLEM(
            pTdnf, pNativeSolve, nUnresolved,
            TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_INSTALLONLY_LIMIT,
            ppszExcludes, nAllowErasing, nAutoErase, dwError);
    }
    TDNFTransactionPlanRequestTraceFinalize(pTdnf->pRequestTrace, pQueueJobs->pnElements,
        pQueueJobs->dwCount, SOLVER_CLEANDEPS, SOLVER_FORCEBEST);
    BAIL_ON_TDNF_ERROR(dwError);

    /* The plan describes the transaction tdnf is about to run, which is the
       one the native solver just produced, so the capture needs the solve to
       still be alive. A solve that returned at all tolerated every problem it
       reports, and what it dropped instead it reports as skipped jobs, so
       nothing here has to tell the plan that problems were accepted. */
    TDNF_TRANSACTION_PLAN_CAPTURE_SOLVED(
        pTdnf, pNativeSolve, 0,
        nUnresolved, UINT32_MAX, ppszExcludes, nAllowErasing, nAutoErase,
        dwError);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppInfo = pInfo;

cleanup:
    TDNFRepoMdNativeSolverLiveSolveRelease(pNativeSolve);
    return dwError;

error:
    if(!TDNFTransactionPlanStateHasPendingProblem(
           pTdnf ? pTdnf->pTransactionPlanState : NULL))
    {
        TDNFTransactionPlanStateClear(
            pTdnf ? pTdnf->pTransactionPlanState : NULL);
    }
    TDNF_SAFE_FREE_MEMORY(pInfo);
    if(ppInfo)
    {
        *ppInfo = NULL;
    }
    goto cleanup;
}

uint32_t
TDNFGoalNoDeps(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueuePkgList,
    PTDNF_SOLVED_PKG_INFO* ppInfo
    )
{
    uint32_t dwError = 0;
    PSolvPackageList pPkgList = NULL;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;

    if(!pTdnf || !ppInfo || !pQueuePkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvIdsToPackageList(pQueuePkgList->pnElements,
                                   pQueuePkgList->dwCount,
                                   &pPkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFPopulatePkgInfos(pTdnf->pSack, pPkgList, &pPkgInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(TDNF_SOLVED_PKG_INFO),
                  (void**)&pInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    pInfo->pPkgsToInstall = pPkgInfo;
    *ppInfo = pInfo;

cleanup:
    return dwError;
error:
    if(pPkgInfo) {
        TDNFFreePackageInfo(pPkgInfo);
    }
    TDNF_SAFE_FREE_MEMORY(pInfo);
    goto cleanup;
}

uint32_t
TDNFGoal(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueuePkgList,
    PTDNF_SOLVED_PKG_INFO* ppInfo,
    TDNF_ALTERTYPE nAlterType, int nUnresolved
    )
{
    uint32_t dwError = 0;
    TDNF_ID_LIST queueJobs = {0};
    int nAllowErasing = 0;
    char** ppszExcludes = NULL;
    uint32_t dwExcludeCount = 0;
    uint32_t nTraceStart = 0;

    if(!pTdnf || !ppInfo || !pQueuePkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFPkgsToExclude(pTdnf, &dwExcludeCount, &ppszExcludes);
    BAIL_ON_TDNF_ERROR(dwError);

    TDNFIdListInit(&queueJobs);
    if (nAlterType == ALTER_UPGRADEALL)
    {
        nTraceStart = queueJobs.dwCount;
        dwError = TDNFIdListPush2(&queueJobs, SOLVER_UPDATE|SOLVER_SOLVABLE_ALL, 0);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNFTransactionPlanRequestTraceRecordAllJob(pTdnf->pRequestTrace, nTraceStart / 2,
            TDNF_TRANSACTION_PLAN_CAPTURE_JOB_UPDATE, queueJobs.pnElements[nTraceStart], 0,
            TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER, 0);
    }
    else if(nAlterType == ALTER_DISTRO_SYNC)
    {
        nTraceStart = queueJobs.dwCount;
        dwError = TDNFIdListPush2(&queueJobs, SOLVER_DISTUPGRADE|SOLVER_SOLVABLE_ALL, 0);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNFTransactionPlanRequestTraceRecordAllJob(pTdnf->pRequestTrace, nTraceStart / 2,
            TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DIST_SYNC, queueJobs.pnElements[nTraceStart], 0,
            TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER, 0);
    }
    else
    {
        if (pQueuePkgList->dwCount == 0 &&
            !TDNFTransactionPlanStateIsEnabled(pTdnf->pTransactionPlanState))
        {
            dwError = ERROR_TDNF_ALREADY_INSTALLED;
            BAIL_ON_TDNF_ERROR(dwError);
        }

        for (uint32_t i = 0; i < pQueuePkgList->dwCount; i++)
        {
            Id dwId = pQueuePkgList->pnElements[i];
            TDNFAddGoal(pTdnf, nAlterType, &queueJobs, dwId,
                        dwExcludeCount, ppszExcludes);
        }
    }

    nAllowErasing =
        pTdnf->pArgs->nAllowErasing ||
        nAlterType == ALTER_ERASE ||
        nAlterType == ALTER_AUTOERASE ||
        nAlterType == ALTER_AUTOERASEALL;
    if(nAllowErasing)
    {
        TDNFAddUserInstalledToJobs(pTdnf, &queueJobs);
        BAIL_ON_TDNF_ERROR(dwError);
        /* TODO: deal with no db error? */
    }

    dwError = TDNFSolv(pTdnf, &queueJobs, ppszExcludes, dwExcludeCount,
                       nAllowErasing,
                       (pTdnf->pConf->nCleanRequirementsOnRemove &&
                                !pTdnf->pArgs->nNoAutoRemove) ||
                                nAlterType == ALTER_AUTOERASE,
                                nAlterType == ALTER_REINSTALL ||
                                (nAlterType == ALTER_DISTRO_SYNC && pTdnf->pConf->nDistroSyncReinstallChanged),
                       nUnresolved, ppInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    if (nAlterType == ALTER_INSTALL)
    {
        dwError = TDNFAddUserInstall(pTdnf, pQueuePkgList, *ppInfo);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    TDNF_SAFE_FREE_STRINGARRAY(ppszExcludes);
    TDNFIdListFree(&queueJobs);
    return dwError;

error:
    goto cleanup;
}

static
uint32_t
TDNFReportProblemsNative(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase,
    int nStampFlags,
    int nStampedJobCount,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    void *pHandle = NULL;

    if(!pTdnf || !pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* Reproduce the request that libsolv found unsatisfiable and retain the
       native solver's structured problems. There is no libsolv fallback: if
       this cannot be rendered natively the error propagates. */
    dwError = TDNFGoalSolveNative(pTdnf, pQueueJobs, nAllowErasing, nAutoErase,
                                  nStampFlags, nStampedJobCount, 0 /*nReInstall*/,
                                  NULL /*ppInfo*/, 0 /*nPrepareOnly*/,
                                  1 /*nRefuteUnsat*/, 0 /*nDropProtected*/,
                                  &pHandle);
    BAIL_ON_TDNF_ERROR(dwError);

    if(!pHandle)
    {
        pr_err("native-solver: unable to render solver diagnostics\n");
        dwError = ERROR_TDNF_SOLV_FAILED;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdNativeSolverRefutedProblemCount(pHandle, &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(dwCount == 0)
    {
        pr_err("native-solver: unable to render solver diagnostics\n");
        dwError = ERROR_TDNF_SOLV_FAILED;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFReportNativeSolverProblems(pHandle, dwSkipProblem);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    if(pHandle)
    {
        TDNFRepoMdNativeSolverLiveSolveRelease(pHandle);
    }
    return dwError;

error:
    goto cleanup;
}

/* Name the protected package a transaction would remove, in the wording
   TDNFSolvCheckProtectPkgsInTrans used when it inspected libsolv's tentative
   transaction. *ppszName is NULL when the transaction removes no protected
   package -- and when it could not be produced at all, in which case the
   returned error says why.

   A native solve that honours protection has no transaction to inspect:
   refusing to produce one is how it reports the problem. Protection is a
   solve policy for it (TDNFSolvAddProtectPkgs turns protected names into jobs
   and the native solver mirrors that), so solving again with the protected
   names dropped reproduces the very transaction being reported. That is also
   what libsolv did -- it only ever heard protection as USERINSTALLED hints
   and produced the transaction anyway, which the check then rejected.

   pPkgsObsoleted is consulted before pPkgsToRemove because libsolv asked for
   SOLVER_TRANSACTION_SHOW_OBSOLETES first: an obsoleted package was never
   reported as a plain removal. */
static
uint32_t
TDNFGoalFindProtectedInTransaction(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase,
    int nStampFlags,
    int nStampedJobCount,
    const char **ppszName,
    const char **ppszAction
    )
{
    uint32_t dwError = 0;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;
    const char *pszName = NULL;
    const char *pszAction = NULL;

    if(!pTdnf || !pQueueJobs || !pTdnf->pConf || !ppszName || !ppszAction)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGoalSolveNative(pTdnf, pQueueJobs, nAllowErasing, nAutoErase,
                                  nStampFlags, nStampedJobCount, 0 /*nReInstall*/,
                                  &pInfo, 0 /*nPrepareOnly*/, 0 /*nRefuteUnsat*/,
                                  1 /*nDropProtected*/, NULL /*ppHandle*/);
    BAIL_ON_TDNF_ERROR(dwError);

    pszName = TDNFFindProtectedPkg(pTdnf->pConf->ppszProtectedPkgs,
                                   pInfo ? pInfo->pPkgsObsoleted : NULL);
    if(pszName)
    {
        pszAction = "obsoleted";
    }
    else
    {
        pszName = TDNFFindProtectedPkg(pTdnf->pConf->ppszProtectedPkgs,
                                       pInfo ? pInfo->pPkgsToRemove : NULL);
        if(pszName)
        {
            pszAction = "removed";
        }
    }

cleanup:
    if(ppszName)
    {
        *ppszName = pszName;
    }
    if(ppszAction)
    {
        *ppszAction = pszAction;
    }
    if(pInfo)
    {
        TDNFFreeSolvedPackageInfo(pInfo);
    }
    return dwError;

error:
    pszName = NULL;
    pszAction = NULL;
    goto cleanup;
}

/* The configured protected name matching the first package in pPkgs, or NULL.
   The configured string is returned rather than the package's own name because
   that is what the libsolv check printed. */
static
const char *
TDNFFindProtectedPkg(
    char **ppszProtectedPkgs,
    PTDNF_PKG_INFO pPkgs
    )
{
    PTDNF_PKG_INFO pPkg = NULL;
    int i = 0;

    if(!ppszProtectedPkgs)
    {
        return NULL;
    }

    for(pPkg = pPkgs; pPkg; pPkg = pPkg->pNext)
    {
        if(IsNullOrEmptyString(pPkg->pszName))
        {
            continue;
        }
        for(i = 0; ppszProtectedPkgs[i]; i++)
        {
            if(!strcmp(ppszProtectedPkgs[i], pPkg->pszName))
            {
                return ppszProtectedPkgs[i];
            }
        }
    }
    return NULL;
}

/* Print the native solver's retained diagnostics the way SolvReportProblems
   printed libsolv's: skip-filter them, number only the survivors, contiguously
   from 1, and print the summary only when at least one problem was reported.
   The handle stays owned by the caller. */
uint32_t
TDNFReportNativeSolverProblems(
    void *pHandle,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t total_prblms = 0;
    uint32_t i = 0;

    if(!pHandle)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdNativeSolverRefutedProblemCount(pHandle, &dwCount);
    BAIL_ON_TDNF_ERROR(dwError);

    for(i = 0; i < dwCount; i++)
    {
        uint32_t nReported = 0;
        const char *pszMessage = NULL;

        dwError = TDNFRepoMdNativeSolverRefutedProblem(pHandle, i, dwSkipProblem,
                                                       &nReported, &pszMessage);
        BAIL_ON_TDNF_ERROR(dwError);
        if(nReported && pszMessage)
        {
            pr_err("%u. %s\n", ++total_prblms, pszMessage);
        }
    }

    if(total_prblms > 0)
    {
        dwError = ERROR_TDNF_SOLV_FAILED;
        pr_err("Found %u problem(s) while resolving\n", total_prblms);
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}

static
uint32_t
TDNFGoalCaptureNativeSolve(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase, int nStampFlags, int nStampedJobCount,
    int nPrepareOnly,
    int nRefuteUnsat,
    int nDropProtected,
    void **ppHandle
    )
{
    uint32_t dwError = 0;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;

    if(!ppHandle || *ppHandle ||
       !TDNFTransactionPlanStateIsEnabled(
           pTdnf ? pTdnf->pTransactionPlanState : NULL))
    {
        goto cleanup;
    }
    dwError = TDNFGoalSolveNative(pTdnf, pQueueJobs, nAllowErasing, nAutoErase,
                                  nStampFlags, nStampedJobCount, 0,
                                  (nPrepareOnly || nRefuteUnsat) ? NULL : &pInfo,
                                  nPrepareOnly, nRefuteUnsat, nDropProtected,
                                  ppHandle);
    BAIL_ON_TDNF_ERROR(dwError);
cleanup:
    if(pInfo)
    {
        TDNFFreeSolvedPackageInfo(pInfo);
    }
    return dwError;
error:
    *ppHandle = NULL;
    TDNFTransactionPlanStateClear(
        pTdnf ? pTdnf->pTransactionPlanState : NULL);
    goto cleanup;
}

static
uint32_t
TDNFGoalSolveNative(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nAllowErasing,
    int nAutoErase, int nStampFlags, int nStampedJobCount, int nReInstall,
    PTDNF_SOLVED_PKG_INFO *ppInfo,
    int nPrepareOnly,
    int nRefuteUnsat,
    int nDropProtected,
    void **ppHandle
    )
{
    uint32_t dwError = 0;
    uint32_t dwRepoCount = 0, dwJobCount = 0, dwEraseJobCount = 0;
    uint32_t dwHiddenAvailableCount = 0;
    int nUpdateAll = 0, nDistSyncAll = 0;
    uint32_t dwGlobalQueuePair = 0;
    int nHasGlobalQueuePair = 0;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 pRepos = NULL;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs = NULL, pEraseJobs = NULL, pHiddenAvailable = NULL;
    char **ppszInstallOnlyPkgs = NULL;
    char **ppszUserInstalledPkgs = NULL;
    char **ppszLockedPkgs = NULL;
    uint32_t *pdwLockedQueuePairs = NULL;
    char **ppszCmdLinePaths = NULL;
    const char *pszNativeArch = NULL;
    char *pszNativeArchOwned = NULL;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;
    if(!pTdnf || !pTdnf->pArgs || !pTdnf->pConf || !pTdnf->pSack ||
       !pTdnf->pSack->pPool || !pTdnf->pRpmConfig || !pQueueJobs ||
       (!nPrepareOnly && !nRefuteUnsat && !ppInfo) ||
       ((nPrepareOnly || nRefuteUnsat) && !ppHandle))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
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
    dwError = TDNFGoalBuildNativeSolverRepoInputs(
                  pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);
    dwError = TDNFGoalBuildNativeSolverJobs(
                  pTdnf,
                  pQueueJobs,
                  nStampFlags, nStampedJobCount,
                  &pJobs,
                  &dwJobCount,
                  &pEraseJobs,
                  &dwEraseJobCount,
                  &ppszInstallOnlyPkgs,
                  &ppszUserInstalledPkgs,
                  &ppszLockedPkgs,
                  &pdwLockedQueuePairs,
                  &ppszCmdLinePaths,
                  &nUpdateAll,
                  &nDistSyncAll,
                  &dwGlobalQueuePair,
                  &nHasGlobalQueuePair);
    BAIL_ON_TDNF_ERROR(dwError);
    if(!nAllowErasing && dwEraseJobCount)
    {
        dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    dwError = TDNFGoalBuildNativeSolverHiddenAvailable(
                  pTdnf, &pHiddenAvailable, &dwHiddenAvailableCount);
    BAIL_ON_TDNF_ERROR(dwError);
    dwError = TDNFRepoMdNativeSolverLiveSolve(
                  pRepos, dwRepoCount, pJobs, dwJobCount,
                  pEraseJobs, dwEraseJobCount, pHiddenAvailable, dwHiddenAvailableCount,
                  pTdnf->pArgs->nAllDeps, pTdnf->pArgs->nBest, nAutoErase, pTdnf->pArgs->nSkipBroken, nAllowErasing,
                  nUpdateAll, nDistSyncAll,
                  (const char *const *)ppszLockedPkgs,
                  pdwLockedQueuePairs,
                  dwGlobalQueuePair,
                  nHasGlobalQueuePair,
                  (const char *const *)ppszInstallOnlyPkgs,
                  (uint32_t)pTdnf->pConf->nInstallOnlyLimit,
                  nDropProtected ? NULL :
                      (const char *const *)pTdnf->pConf->ppszProtectedPkgs,
                  (const char *const *)ppszUserInstalledPkgs,
                  (const char *const *)ppszCmdLinePaths, nReInstall,
                  pTdnf->pRpmConfig, pszNativeArch, nPrepareOnly,
                  nRefuteUnsat, (nPrepareOnly || nRefuteUnsat) ? NULL : &pInfo,
                  ppHandle);
    if(dwError && !IsNullOrEmptyString(TDNFRepoMdLastError()))
    {
        pr_err("native-solver: %s\n", TDNFRepoMdLastError());
    }
    BAIL_ON_TDNF_ERROR(dwError);
    if(!nPrepareOnly && !nRefuteUnsat)
    {
        *ppInfo = pInfo;
        pInfo = NULL;
    }
cleanup:
    if(pInfo)
    {
        TDNFFreeSolvedPackageInfo(pInfo);
    }
    TDNF_SAFE_FREE_MEMORY(pszNativeArchOwned);
    TDNF_SAFE_FREE_MEMORY(ppszLockedPkgs);
    TDNF_SAFE_FREE_MEMORY(pdwLockedQueuePairs);
    TDNF_SAFE_FREE_MEMORY(ppszCmdLinePaths);
    TDNF_SAFE_FREE_MEMORY(ppszUserInstalledPkgs);
    TDNF_SAFE_FREE_MEMORY(ppszInstallOnlyPkgs);
    TDNFGoalFreeNativeSolverJobs(pHiddenAvailable, dwHiddenAvailableCount);
    TDNFGoalFreeNativeSolverJobs(pJobs, dwJobCount + dwEraseJobCount);
    TDNFGoalFreeNativeSolverRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    goto cleanup;
}

static
uint32_t
TDNFGoalBuildNativeSolverRepoInputs(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 *ppRepos,
    uint32_t *pdwRepoCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 pRepos = NULL;
    PTDNF_REPO_DATA pRepoData = NULL;

    if(!pTdnf || !ppRepos || !pdwRepoCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for(pRepoData = pTdnf->pRepos; pRepoData; pRepoData = pRepoData->pNext)
    {
        if(pRepoData->nEnabled &&
           (pRepoData->nHasMetaData ||
            TDNF_REPO_RPM_DIRECTORY(pRepoData)) &&
           pRepoData->pRepo &&
           !IsNullOrEmptyString(pRepoData->pszId))
        {
            dwCount++;
        }
    }
    /* No enabled repository with metadata is a valid universe: the installed
       set alone, which is what --disablerepo=* produces. */
    if(dwCount)
    {
        dwError = TDNFAllocateMemory(
                      dwCount, sizeof(*pRepos), (void **)&pRepos);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwCount = 0;
    for(pRepoData = pTdnf->pRepos; pRepoData; pRepoData = pRepoData->pNext)
    {
        if(!pRepoData->nEnabled ||
           (!pRepoData->nHasMetaData &&
            !TDNF_REPO_RPM_DIRECTORY(pRepoData)) ||
           !pRepoData->pRepo ||
           IsNullOrEmptyString(pRepoData->pszId))
        {
            continue;
        }
        pRepos[dwCount].pszDirectory = TDNF_REPO_RPM_DIRECTORY(pRepoData);
        if(!pRepos[dwCount].pszDirectory)
        {
            dwError = TDNFGetCachePath(
                          pTdnf, pRepoData, NULL, NULL,
                          (char **)&pRepos[dwCount].pszCacheDir);
            BAIL_ON_TDNF_ERROR(dwError);
        }

        pRepos[dwCount].pszId = pRepoData->pszId;
        pRepos[dwCount].pszSnapshotFile = pRepoData->pszSnapshotFile;
        pRepos[dwCount].nPriority = pRepoData->nPriority;
        pRepos[dwCount].dwCost =
            TDNF_REPOMD_NATIVE_SOLVER_DEFAULT_REPOSITORY_COST;
        dwCount++;
    }

    *ppRepos = pRepos;
    *pdwRepoCount = dwCount;

cleanup:
    return dwError;
error:
    TDNFGoalFreeNativeSolverRepoInputs(pRepos, dwCount);
    goto cleanup;
}

static
void
TDNFGoalFreeNativeSolverRepoInputs(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 pRepos,
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

static
uint32_t
TDNFGoalBuildNativeSolverJobs(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueJobs,
    int nStampFlags, int nStampedJobCount,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppJobs,
    uint32_t *pdwJobCount,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppEraseJobs,
    uint32_t *pdwEraseJobCount,
    char ***pppszInstallOnlyPkgs,
    char ***pppszUserInstalledPkgs,
    char ***pppszLockedPkgs,
    uint32_t **ppdwLockedQueuePairs,
    char ***pppszCmdLinePaths,
    int *pnUpdateAll,
    int *pnDistSyncAll,
    uint32_t *pdwGlobalQueuePair,
    int *pnHasGlobalQueuePair
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;
    uint32_t dwInstallCount = 0;
    uint32_t dwEraseCount = 0;
    uint32_t dwLockedCount = 0;
    uint32_t dwInstallOnlyCount = 0;
    uint32_t dwUserInstalledCount = 0;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs = NULL;
    char **ppszLockedPkgs = NULL;
    uint32_t *pdwLockedQueuePairs = NULL;
    char **ppszCmdLinePaths = NULL;
    char **ppszInstallOnlyPkgs = NULL;
    char **ppszUserInstalledPkgs = NULL;
    Pool *pPool = NULL;
    unsigned int nMediaNr = 0;
    int nUpdateAll = 0;
    int nDistSyncAll = 0;
    uint32_t dwGlobalQueuePair = 0;
    int nHasGlobalQueuePair = 0;

    if(!pTdnf || !pTdnf->pArgs || !pTdnf->pConf || !pTdnf->pSack ||
       !pTdnf->pSack->pPool || !pQueueJobs || !ppJobs || !pdwJobCount ||
       !ppEraseJobs || !pdwEraseJobCount || !pppszInstallOnlyPkgs ||
       !pppszUserInstalledPkgs || !pppszLockedPkgs || !pppszCmdLinePaths ||
       !ppdwLockedQueuePairs || !pdwGlobalQueuePair ||
       !pnHasGlobalQueuePair ||
       !pnUpdateAll || !pnDistSyncAll ||
       pQueueJobs->dwCount % 2 != 0 || nStampedJobCount % 2 != 0 ||
       nStampedJobCount < 0 || (uint32_t)nStampedJobCount > pQueueJobs->dwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pPool = pTdnf->pSack->pPool;
    dwCount = (uint32_t)pQueueJobs->dwCount / 2;
    /* One spare element throughout: an empty job queue is a real request --
       `history undo` and `history rollback` reach an already-satisfied target
       -- and TDNFAllocateMemory rejects a zero-element allocation. */
    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*pJobs),
                  (void **)&pJobs);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*ppszLockedPkgs),
                  (void **)&ppszLockedPkgs);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*pdwLockedQueuePairs),
                  (void **)&pdwLockedQueuePairs);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*ppszCmdLinePaths),
                  (void **)&ppszCmdLinePaths);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*ppszInstallOnlyPkgs),
                  (void **)&ppszInstallOnlyPkgs);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  dwCount + 1,
                  sizeof(*ppszUserInstalledPkgs),
                  (void **)&ppszUserInstalledPkgs);
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwIndex = 0; dwIndex < dwCount; dwIndex++)
    {
        /* XOR removes exactly the bits the flag stamp above set; wrong shapes
           stay set. Jobs appended after it carry no policy bits, so XORing
           them would wrongly *add* cleandeps. Those late erases are the
           install-only evictions TDNFSolvCheckInstallOnlyLimitInTrans pushes
           from the retry loop, which the native solver derives itself. */
        int nStamped = (int)(dwIndex * 2) < nStampedJobCount;
        Id rawHow = pQueueJobs->pnElements[dwIndex * 2];
        Id how = nStamped ? rawHow ^ nStampFlags : rawHow;
        Id dwPkgId = pQueueJobs->pnElements[dwIndex * 2 + 1];
        Solvable *pSolvable = NULL;
        PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJob = NULL;
        int nInstall = how == (SOLVER_SOLVABLE | SOLVER_INSTALL),
            nErase = nStamped && how == (SOLVER_SOLVABLE | SOLVER_ERASE),
            nUserInstalled = how == (SOLVER_SOLVABLE | SOLVER_USERINSTALLED) ||
                rawHow == (SOLVER_SOLVABLE | SOLVER_USERINSTALLED),
            nAllowUninstall = rawHow == (SOLVER_SOLVABLE | SOLVER_ALLOWUNINSTALL),
            nLocked = rawHow == (SOLVER_SOLVABLE_NAME | SOLVER_LOCK),
            nInstallOnly =
                rawHow == (SOLVER_SOLVABLE_NAME | SOLVER_MULTIVERSION),
            nUpdateAllJob = how == (SOLVER_SOLVABLE_ALL | SOLVER_UPDATE),
            nDistSyncAllJob = how == (SOLVER_SOLVABLE_ALL | SOLVER_DISTUPGRADE);
        if(!nStamped && how == (SOLVER_SOLVABLE | SOLVER_ERASE)) continue;
        if((nUpdateAllJob || nDistSyncAllJob) && !dwPkgId && !nUpdateAll && !nDistSyncAll)
        {
            nUpdateAll = nUpdateAllJob;
            nDistSyncAll = nDistSyncAllJob;
            dwGlobalQueuePair = dwIndex;
            nHasGlobalQueuePair = 1;
            continue;
        }
        if(nLocked)
        {
            const char *pszName = dwPkgId > 0 ? pool_id2str(pPool, dwPkgId) : NULL;
            if(dwPkgId <= 0 || IsNullOrEmptyString(pszName))
            {
                dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
                BAIL_ON_TDNF_ERROR(dwError);
            }
            pdwLockedQueuePairs[dwLockedCount] = dwIndex;
            ppszLockedPkgs[dwLockedCount++] = (char *)pszName;
            continue;
        }
        if(nInstallOnly)
        {
            const char *pszName = dwPkgId > 0 ? pool_id2str(pPool, dwPkgId) : NULL;
            if(dwPkgId <= 0 || IsNullOrEmptyString(pszName))
            {
                dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
                BAIL_ON_TDNF_ERROR(dwError);
            }
            ppszInstallOnlyPkgs[dwInstallOnlyCount++] = (char *)pszName;
            continue;
        }
        if((!nInstall && !nErase && !nUserInstalled && !nAllowUninstall) ||
           dwPkgId <= 0 || dwPkgId >= pPool->nsolvables)
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        pSolvable = pool_id2solvable(pPool, dwPkgId);
        if(!pSolvable || !pSolvable->repo ||
           IsNullOrEmptyString(pSolvable->repo->name) ||
           (nInstall && pSolvable->repo == pPool->installed) ||
           (!nInstall && pSolvable->repo != pPool->installed))
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if(nUserInstalled || nAllowUninstall)
        {
            const char *pszName = pool_id2str(pPool, pSolvable->name);
            if(IsNullOrEmptyString(pszName))
            {
                dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
                BAIL_ON_TDNF_ERROR(dwError);
            }
            if(nUserInstalled)
            {
                ppszUserInstalledPkgs[dwUserInstalledCount++] = (char *)pszName;
            }
            continue;
        }
        pJob = nInstall
            ? &pJobs[dwInstallCount++]
            : &pJobs[dwCount - ++dwEraseCount];
        /* The plan numbers jobs by queue pair, so carry the pair across the
           translation into the native job list. */
        pJob->dwQueuePair = dwIndex;
        pJob->nHasQueuePair = 1;
        pJob->pszRepository = pSolvable->repo->name;
        /* A command-line solvable has no downloadable metadata, so the native
           solver rebuilds it from the .rpm that libsolv itself read. */
        if(pSolvable->repo == pTdnf->pSolvCmdLineRepo ||
           !strcmp(pSolvable->repo->name, CMDLINE_REPO_NAME))
        {
            ppszCmdLinePaths[dwInstallCount - 1] =
                (char *)solvable_get_location(pSolvable, &nMediaNr);
        }
        dwError = SolvGetNevraFromId(
                      pTdnf->pSack,
                      dwPkgId,
                      &pJob->dwEpoch,
                      (char **)&pJob->pszName,
                      (char **)&pJob->pszVersion,
                      (char **)&pJob->pszRelease,
                      (char **)&pJob->pszArch,
                      NULL);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if((nUpdateAll || nDistSyncAll) &&
       dwCount != dwLockedCount + dwInstallOnlyCount + dwUserInstalledCount + 1)
    {
        dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    memmove(
        pJobs + dwInstallCount,
        pJobs + dwCount - dwEraseCount,
        dwEraseCount * sizeof(*pJobs));
    *ppJobs = pJobs;
    *pdwJobCount = dwInstallCount;
    *ppEraseJobs = dwEraseCount ? pJobs + dwInstallCount : NULL;
    *pdwEraseJobCount = dwEraseCount;
    *pppszInstallOnlyPkgs = ppszInstallOnlyPkgs;
    *pppszUserInstalledPkgs = ppszUserInstalledPkgs;
    *pppszLockedPkgs = ppszLockedPkgs;
    *ppdwLockedQueuePairs = pdwLockedQueuePairs;
    *pppszCmdLinePaths = ppszCmdLinePaths;
    *pnUpdateAll = nUpdateAll;
    *pnDistSyncAll = nDistSyncAll;
    *pdwGlobalQueuePair = dwGlobalQueuePair;
    *pnHasGlobalQueuePair = nHasGlobalQueuePair;
cleanup:
    return dwError;
error:
    TDNF_SAFE_FREE_MEMORY(ppszLockedPkgs);
    TDNF_SAFE_FREE_MEMORY(pdwLockedQueuePairs);
    TDNF_SAFE_FREE_MEMORY(ppszCmdLinePaths);
    TDNF_SAFE_FREE_MEMORY(ppszUserInstalledPkgs);
    TDNF_SAFE_FREE_MEMORY(ppszInstallOnlyPkgs);
    TDNFGoalFreeNativeSolverJobs(pJobs, dwCount);
    goto cleanup;
}

static
void
TDNFGoalFreeNativeSolverJobs(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs,
    uint32_t dwJobCount
    )
{
    uint32_t dwIndex = 0;

    if(!pJobs)
    {
        return;
    }
    for(dwIndex = 0; dwIndex < dwJobCount; dwIndex++)
    {
        char *pszName = (char *)pJobs[dwIndex].pszName;
        char *pszVersion = (char *)pJobs[dwIndex].pszVersion;
        char *pszRelease = (char *)pJobs[dwIndex].pszRelease;
        char *pszArch = (char *)pJobs[dwIndex].pszArch;
        TDNF_SAFE_FREE_MEMORY(pszName);
        TDNF_SAFE_FREE_MEMORY(pszVersion);
        TDNF_SAFE_FREE_MEMORY(pszRelease);
        TDNF_SAFE_FREE_MEMORY(pszArch);
        pJobs[dwIndex].pszName = NULL;
        pJobs[dwIndex].pszVersion = NULL;
        pJobs[dwIndex].pszRelease = NULL;
        pJobs[dwIndex].pszArch = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pJobs);
}

static
int
TDNFGoalIsNativeSolverPackage(
    Pool *pPool,
    Solvable *pSolvable
    )
{
    const char *pszName = NULL;

    if(!pPool || !pSolvable)
    {
        return 0;
    }
    pszName = pool_id2str(pPool, pSolvable->name);
    return pszName && strncmp(pszName, "patch:", 6);
}

static
uint32_t
TDNFGoalBuildNativeSolverHiddenAvailable(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppHiddenAvailable,
    uint32_t *pdwHiddenAvailableCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;
    Id dwPkgId = 0;
    Pool *pPool = NULL;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pHiddenAvailable = NULL;

    if(!pTdnf || !pTdnf->pSack || !pTdnf->pSack->pPool ||
       !ppHiddenAvailable || !pdwHiddenAvailableCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    pPool = pTdnf->pSack->pPool;
    if(!pPool->considered)
    {
        goto cleanup;
    }
    for(dwPkgId = 1; dwPkgId < pPool->nsolvables; dwPkgId++)
    {
        Solvable *pSolvable = pool_id2solvable((Pool *)pPool, dwPkgId);
        if(!pSolvable || !pSolvable->repo ||
           MAPTST(pPool->considered, dwPkgId) ||
           pSolvable->repo == pPool->installed ||
           !TDNFGoalIsNativeSolverPackage(pPool, pSolvable))
        {
            continue;
        }
        if(IsNullOrEmptyString(pSolvable->repo->name))
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if(pSolvable->repo == pTdnf->pSolvCmdLineRepo ||
           !strcmp(pSolvable->repo->name, CMDLINE_REPO_NAME))
        {
            continue;
        }
        dwCount++;
    }
    if(!dwCount)
    {
        goto cleanup;
    }

    dwError = TDNFAllocateMemory(
                  dwCount,
                  sizeof(TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB),
                  (void **)&pHiddenAvailable);
    BAIL_ON_TDNF_ERROR(dwError);

    for(dwPkgId = 1; dwPkgId < pPool->nsolvables; dwPkgId++)
    {
        Solvable *pSolvable = pool_id2solvable(pPool, dwPkgId);
        if(!pSolvable || !pSolvable->repo ||
           MAPTST(pPool->considered, dwPkgId) ||
           pSolvable->repo == pPool->installed ||
           !TDNFGoalIsNativeSolverPackage(pPool, pSolvable))
        {
            continue;
        }
        if(IsNullOrEmptyString(pSolvable->repo->name))
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if(pSolvable->repo == pTdnf->pSolvCmdLineRepo ||
           !strcmp(pSolvable->repo->name, CMDLINE_REPO_NAME))
        {
            continue;
        }
        pHiddenAvailable[dwIndex].pszRepository = pSolvable->repo->name;
        dwError = SolvGetNevraFromId(
                      pTdnf->pSack,
                      dwPkgId,
                      &pHiddenAvailable[dwIndex].dwEpoch,
                      (char **)&pHiddenAvailable[dwIndex].pszName,
                      (char **)&pHiddenAvailable[dwIndex].pszVersion,
                      (char **)&pHiddenAvailable[dwIndex].pszRelease,
                      (char **)&pHiddenAvailable[dwIndex].pszArch,
                      NULL);
        BAIL_ON_TDNF_ERROR(dwError);
        dwIndex++;
    }

    *ppHiddenAvailable = pHiddenAvailable;
    *pdwHiddenAvailableCount = dwCount;

cleanup:
    return dwError;
error:
    TDNFGoalFreeNativeSolverJobs(pHiddenAvailable, dwCount);
    goto cleanup;
}

uint32_t
TDNFAddUserInstall(
    PTDNF pTdnf,
    const TDNF_ID_LIST *pQueueGoal,
    PTDNF_SOLVED_PKG_INFO ppInfo
    )
{
    uint32_t dwError = 0;
    int i;
    char **ppszPkgsUserInstall = NULL;

    if (!pTdnf || !pQueueGoal || !ppInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(pQueueGoal->dwCount + 1,
                                 sizeof(char **),
                                 (void **)&ppszPkgsUserInstall);
    BAIL_ON_TDNF_ERROR(dwError);

    for (i = 0; i < (int)pQueueGoal->dwCount; i++)
    {
        dwError = SolvGetPkgNameFromId(
                       pTdnf->pSack,
                       pQueueGoal->pnElements[i],
                       &ppszPkgsUserInstall[i]);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppInfo->ppszPkgsUserInstall = ppszPkgsUserInstall;
cleanup:
    return dwError;
error:
    TDNF_SAFE_FREE_MEMORY(ppszPkgsUserInstall);
    goto cleanup;
}

uint32_t
TDNFMarkAutoInstalledSinglePkg(
    PTDNF pTdnf,
    const char *pszPkgName
)
{
    uint32_t dwError = 0;
    int rc;
    struct history_ctx *pHistoryCtx = NULL;

    if (!pTdnf || !pszPkgName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFGetHistoryCtx(pTdnf, &pHistoryCtx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    rc = history_set_auto_flag(pHistoryCtx, pszPkgName, 0);
    if (rc != 0)
    {
        dwError = ERROR_TDNF_HISTORY_ERROR;
        BAIL_ON_TDNF_ERROR(dwError);
    }
cleanup:
    if (pHistoryCtx)
    {
        destroy_history_ctx(pHistoryCtx);
    }
    return dwError;
error:
    goto cleanup;
}

uint32_t
TDNFMarkAutoInstalled(
    PTDNF pTdnf,
    struct history_ctx *pHistoryCtx,
    PTDNF_SOLVED_PKG_INFO ppInfo,
    int nAutoOnly
    )
{
    uint32_t dwError = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;

    if (!pTdnf || !pHistoryCtx || !ppInfo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* Installs absent from ppszPkgsUserInstall were dependency-selected. */
    for (pPkgInfo = ppInfo->pPkgsToInstall; pPkgInfo; pPkgInfo = pPkgInfo->pNext)
    {
        const char *pszName = pPkgInfo->pszName;
        int nFlag = 1;
        if (ppInfo->ppszPkgsUserInstall)
        {
            for (int i = 0; ppInfo->ppszPkgsUserInstall[i]; i++)
            {
                if (strcmp(pszName,
                           ppInfo->ppszPkgsUserInstall[i]) == 0)
                {
                    nFlag = 0;
                    break;
                }
            }
        }
        /* New installonly versions retain the prior user/auto status. */
        if (nFlag == 1 && pTdnf->pConf && pTdnf->pConf->ppszInstallOnlyPkgs)
        {
            for (int i = 0; pTdnf->pConf->ppszInstallOnlyPkgs[i]; i++)
            {
                if (strcmp(pTdnf->pConf->ppszInstallOnlyPkgs[i], pszName) == 0)
                {
                    int value = 0;
                    int rc = history_get_auto_flag(pHistoryCtx, pszName, &value);
                    if (rc != 0)
                    {
                        dwError = ERROR_TDNF_HISTORY_ERROR;
                        BAIL_ON_TDNF_ERROR(dwError);
                    }
                    if (value == 0)
                    {
                        nFlag = 0;
                        break;
                    }
                }
            }
        }
        if (!nAutoOnly || nFlag == 1)
        {
            int rc = history_set_auto_flag(pHistoryCtx, pszName, nFlag);
            if (rc != 0)
            {
                dwError = ERROR_TDNF_HISTORY_ERROR;
                BAIL_ON_TDNF_ERROR(dwError);
            }
        }
    }
cleanup:
    return dwError;
error:
    goto cleanup;
}

uint32_t
TDNFAddGoal(
    PTDNF pTdnf,
    TDNF_ALTERTYPE nAlterType,
    PTDNF_ID_LIST pQueueJobs,
    Id dwId,
    uint32_t dwCount,
    char** ppszExcludes
    )
{
    uint32_t dwError = 0;
    char** ppszPackagesTemp = NULL;
    char* pszName = NULL;
    uint32_t nTraceStart = 0;

    if(!pTdnf || !pQueueJobs || dwId == 0 || !pTdnf->pSack ||
       !pTdnf->pSack->pPool)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    nTraceStart = pQueueJobs->dwCount;

    if (dwCount != 0 && ppszExcludes)
    {
        dwError = SolvGetPkgNameFromId(
                      pTdnf->pSack,
                      dwId,
                      &pszName);
        BAIL_ON_TDNF_ERROR(dwError);
        ppszPackagesTemp = ppszExcludes;

        while(ppszPackagesTemp && *ppszPackagesTemp)
        {
            if (SolvIsGlob(*ppszPackagesTemp))
            {
                if (!fnmatch(*ppszPackagesTemp, pszName, 0))
                {
                    goto cleanup;
                }
            }
            else if (!strcmp(pszName, *ppszPackagesTemp))
            {
                goto cleanup;
            }
            ++ppszPackagesTemp;
        }
    }

    switch(nAlterType)
    {
        case ALTER_DOWNGRADEALL:
        case ALTER_DOWNGRADE:
            /* Same job as an install: a downgrade is expressed by dwId already
               naming the older solvable (packageutils.c picks it), not by a
               distinct solver bit. The deleted SolvAddPkgDowngradeJob was a
               verbatim copy of SolvAddPkgInstallJob, so this is not a change. */
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_INSTALL, dwId);
            BAIL_ON_TDNF_ERROR(dwError);
            break;
        case ALTER_ERASE:
        case ALTER_AUTOERASE:
        case ALTER_AUTOERASEALL:
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_ERASE, dwId);
            BAIL_ON_TDNF_ERROR(dwError);
            break;
        case ALTER_REINSTALL:
        case ALTER_INSTALL:
        case ALTER_UPGRADE:
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_INSTALL, dwId);
            BAIL_ON_TDNF_ERROR(dwError);
            break;
        default:
            dwError = ERROR_TDNF_INVALID_RESOLVE_ARG;
            BAIL_ON_TDNF_ERROR(dwError);
    }
cleanup:
    if(!dwError)
    {
        TDNFTransactionPlanRequestTraceCommitGoal(pTdnf->pRequestTrace, dwId,
            nAlterType, pQueueJobs->pnElements, nTraceStart, pQueueJobs->dwCount);
    }
    TDNF_SAFE_FREE_MEMORY(pszName);
    return dwError;

error:
    goto cleanup;
}

uint32_t
TDNFSolvAddPkgLocks(PTDNF pTdnf, PTDNF_ID_LIST pQueueJobs, Pool *pPool)
{
    uint32_t dwError = 0;
    int i;
    if(!pTdnf || !pQueueJobs || !pPool) dwError = ERROR_TDNF_INVALID_PARAMETER;
    BAIL_ON_TDNF_ERROR(dwError);
    for (i = 0; pTdnf->pConf->ppszPkgLocks && pTdnf->pConf->ppszPkgLocks[i]; i++)
    {
        char *pszPkg = pTdnf->pConf->ppszPkgLocks[i];
        Id idPkg = pool_str2id(pPool, pszPkg, 1), p;
        Solvable *s;
        if (!idPkg) continue;
        FOR_REPO_SOLVABLES(pPool->installed, p, s)
        {
            if (idPkg == s->name)
            {
                dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE_NAME|SOLVER_LOCK, idPkg);
                BAIL_ON_TDNF_ERROR(dwError);
                TDNFTransactionPlanRequestTraceRecordNameJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                    TDNF_TRANSACTION_PLAN_CAPTURE_JOB_LOCK, pszPkg, SOLVER_SOLVABLE_NAME|SOLVER_LOCK, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
                break;
            }
        }
    }
cleanup:
    return dwError;
error:
    goto cleanup;
}

uint32_t
TDNFSolvAddInstallOnlyPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    Pool *pPool
    )
{
    uint32_t dwError = 0;
    char **ppszPackages = NULL;
    int i;

    if(!pTdnf || !pQueueJobs || !pPool)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppszPackages = pTdnf->pConf->ppszInstallOnlyPkgs;

    for (i = 0; ppszPackages && ppszPackages[i]; i++)
    {
        char *pszPkg = ppszPackages[i];
        Id idPkg = pool_str2id(pPool, pszPkg, 1);
        if (idPkg)
        {
            Id p;
            Solvable *s;
            /* Name multiversion jobs matter only when an instance exists. */
            FOR_REPO_SOLVABLES(pPool->installed, p, s)
            {
                if (idPkg == s->name)
                {
                    dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE_NAME|SOLVER_MULTIVERSION, idPkg);
                    BAIL_ON_TDNF_ERROR(dwError);
                    TDNFTransactionPlanRequestTraceRecordNameJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                        TDNF_TRANSACTION_PLAN_CAPTURE_JOB_MULTIVERSION, pszPkg, SOLVER_SOLVABLE_NAME|SOLVER_MULTIVERSION, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                        TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
                    break;
                }
            }
        }
    }

cleanup:
    return dwError;
error:
    goto cleanup;
}


uint32_t
TDNFSolvAddMinVersions(
    PTDNF pTdnf,
    Pool *pPool
    )
{
    uint32_t dwError = 0;
    char **ppszPackages = NULL;
    char **ppszExcludeLines = NULL;
    uint32_t dwExcludeCount = 0;
    Map *pMapMinVersions = NULL;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    uint32_t i = 0;

    if(!pTdnf || !pPool)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppszPackages = pTdnf->pConf->ppszMinVersions;
    if (!ppszPackages)
    {
        goto cleanup;
    }

    dwError = TDNFAllocateMemory(
                          1,
                          sizeof(Map),
                          (void**)&pMapMinVersions);
    BAIL_ON_TDNF_ERROR(dwError);

    map_init(pMapMinVersions, pPool->nsolvables);

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFRepoMdNativeMinVersionExcludeLinesConfig(
                  pRepos,
                  dwRepoCount,
                  pTdnf->pRpmConfig,
                  ppszPackages,
                  &ppszExcludeLines,
                  &dwExcludeCount);
    BAIL_ON_TDNF_ERROR(dwError);

    for(i = 0; i < dwExcludeCount; i++)
    {
        Id dwPkgId = 0;

        dwError = TDNFNativeQueryResolveSinglePackageRef(
                      pTdnf->pSack,
                      ppszExcludeLines[i],
                      0,
                      &dwPkgId);
        BAIL_ON_TDNF_ERROR(dwError);

        MAPSET(pMapMinVersions, dwPkgId);
    }

    if (!pPool->considered)
    {
        dwError = TDNFAllocateMemory(
                             1,
                             sizeof(Map),
                             (void**)&pPool->considered);
        map_init(pPool->considered, pPool->nsolvables);
        map_setall(pPool->considered);
    }

    map_subtract(pPool->considered, pMapMinVersions);

cleanup:
    TDNFFreeStringArray(ppszExcludeLines);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    if(pMapMinVersions)
    {
        map_free(pMapMinVersions);
        TDNFFreeMemory(pMapMinVersions);
    }
    return dwError;
error:
    goto cleanup;
}

uint32_t
TDNFSolvAddProtectPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    Pool *pPool
    )
{
    uint32_t dwError = 0;
    char **ppszProtectedPkgs = NULL;
    int i, j;
    TDNF_ID_LIST qPkgs = {0};
    Id p;
    Solvable *s;

    if(!pTdnf || !pQueueJobs || !pPool || !pTdnf->pConf)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppszProtectedPkgs = pTdnf->pConf->ppszProtectedPkgs;
    TDNFIdListInit(&qPkgs);
    for (i = 0; ppszProtectedPkgs[i]; i++) {
        Id idPkg = pool_str2id(pPool, ppszProtectedPkgs[i], 1);
        if (idPkg) {
            dwError = TDNFIdListPush(&qPkgs, idPkg);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    /* Direct erases of protected names must be rejected explicitly. */
    for (j = 0; j < (int)pQueueJobs->dwCount; j += 2) {
        Id how = pQueueJobs->pnElements[j];
        if (((how & SOLVER_JOBMASK) == SOLVER_ERASE) && (how & SOLVER_SOLVABLE)) {
            Id what = pQueueJobs->pnElements[j+1];
            s = pool_id2solvable(pPool, what);
            for (i = 0; i < (int)qPkgs.dwCount; i++) {
                if (qPkgs.pnElements[i] == s->name)
                    break;
            }
            if (i < (int)qPkgs.dwCount) {
                const char *pszPkgName = ppszProtectedPkgs[i];
                for (i = 0; i < (int)pQueueJobs->dwCount; i += 2) {
                    if (i == j)
                        continue;
                    how = pQueueJobs->pnElements[i];
                    if (((how & SOLVER_JOBMASK) == SOLVER_INSTALL) && (how & SOLVER_SOLVABLE)) {
                        Id what_add = pQueueJobs->pnElements[i+1];
                        const Solvable *s_add = pool_id2solvable(pPool, what_add);
                        if (s_add->name == s->name) {
                            break;
                        }
                    }
                }
                if (i == (int)pQueueJobs->dwCount) {
                    pr_err("package %s is protected\n", pszPkgName);
                    dwError = ERROR_TDNF_PROTECTED;
                    BAIL_ON_TDNF_ERROR(dwError);
                }
            }
        }
    }

    /* libsolv has no protected flag; allow uninstall only for other names. */
    FOR_REPO_SOLVABLES(pPool->installed, p, s)
    {
        for (i = 0; i < (int)qPkgs.dwCount; i++) {
            if (qPkgs.pnElements[i] == s->name)
                break;
        }
        if (i == (int)qPkgs.dwCount) {
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_ALLOWUNINSTALL, p);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordPackageJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ALLOW_UNINSTALL, p, SOLVER_SOLVABLE|SOLVER_ALLOWUNINSTALL, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        } else {
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_USERINSTALLED, p);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordPackageJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED, p, SOLVER_SOLVABLE|SOLVER_USERINSTALLED, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        }
    }

cleanup:
    TDNFIdListFree(&qPkgs);
    return dwError;
error:
    goto cleanup;
}

