/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"


static uint32_t
TDNFSolvAddPkgLocks(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    PTDNF_PKG_INFO pInstalled,
    uint32_t dwInstalledCount
    );

static uint32_t
TDNFSolvAddInstallOnlyPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    PTDNF_PKG_INFO pInstalled,
    uint32_t dwInstalledCount
    );
/* The _Static_asserts that pin tdnf's job encoding and handle widths to
   libsolv's live in packageutils.c, the one file in client/ that still
   speaks libsolv. Keeping them here would have made goal.c depend on
   <solv/solver.h> for constants it no longer uses. */

/*
 * A package handle's name, without asking the pool for it.
 *
 * Serializing the handle to a native ref and splitting it back out is
 * how the job builder above already reads package identity, so this
 * keeps the two agreeing rather than reaching into libsolv for the one
 * field. Only the name survives; the rest of the split is discarded.
 */
static
uint32_t
GoalGetPkgNameFromHandle(
    PTDNF pTdnf,
    TDNF_PKG_ID dwPkgId,
    char **ppszName
);

/*
 * The recorded local path of a command-line .rpm, ALLOCATED for the
 * caller to free. Single caller in this file; kept static so it adds no
 * exported symbol.
 */
static
uint32_t
TDNFFindCmdLinePkgPath(
    PTDNF pTdnf,
    TDNF_PKG_ID dwPkgId,
    char **ppszPath
);

/*
 * Turn the configured protected names into solver policy, and reject a
 * request that would erase one. Single caller in this file; kept static
 * so it adds no exported symbol.
 */
static
uint32_t
TDNFSolvAddProtectPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs
);

/*
 * The configured protected entry equal to pszName, or NULL. Same contract
 * as TDNFFindProtectedPkg() below; see the definition for why comparing
 * names is what the pool string ids used to stand in for.
 */
static
const char *
GoalFindProtectedName(
    char **ppszProtectedPkgs,
    const char *pszName
);

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
uint32_t
TDNFGoalBuildNativeSolverHiddenAvailable(
    PTDNF pTdnf,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB *ppHiddenAvailable,
    uint32_t *pdwHiddenAvailableCount
);

static
uint32_t
TDNFGoalSplitHiddenRef(
    const char *pszRef,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJob,
    int *pnSkip
);

static
void
TDNFGoalFreeNativeSolverHiddenAvailable(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs,
    uint32_t dwJobCount
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

static
uint32_t
TDNFGoalLoadInstalledPkgs(
    PTDNF pTdnf,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
);

static
int
TDNFGoalNameIsInstalled(
    const char *pszName,
    PTDNF_PKG_INFO pPkgInfo,
    uint32_t dwInstalledCount
);

#define TDNF_GOAL_CAPTURE_NATIVE_OR_RETHROW(_tdnf, _jobs, _allow_erasing, _auto_erase, _flags, _stamped_count, _prepare_only, _refute_unsat, _drop_protected, _native, _error) \
    do {                                                                 \
        uint32_t _saved_error = (_error);                                \
        (_error) = TDNFGoalCaptureNativeSolve((_tdnf), (_jobs), (_allow_erasing), (_auto_erase), (_flags), (_stamped_count), (_prepare_only), (_refute_unsat), (_drop_protected), (_native)); \
        if ((_error)) { TDNFTransactionPlanStateClear((_tdnf)->pTransactionPlanState); (_error) = _saved_error; BAIL_ON_TDNF_ERROR(_error); } \
        (_error) = _saved_error;                                         \
        TDNFTransactionPlanRequestTraceFinalize((_tdnf)->pRequestTrace, (_jobs)->pnElements, (_jobs)->dwCount, TDNF_JOB_CLEANDEPS, TDNF_JOB_FORCEBEST); \
    } while (0)

/*
 * The user-installed jobs, built here rather than in solv/.
 *
 * The loop this replaces lived in solv/tdnfquery.c so that it could walk
 * pPool->installed directly, and it had to spell the job encoding in
 * libsolv's SOLVER_* names because solv/ may not include a client/ header
 * -- with a comment warning that the two spellings must be changed
 * together. Enumerating the installed set through the handle bridge
 * removes both problems at once: the encoding is now written once, in
 * tdnf's own TDNF_JOB_* macros, next to every other job this file pushes.
 *
 * Order is unchanged. TDNFInstalledGetPkgIds() walks the installed repo
 * with the same FOR_REPO_SOLVABLES the deleted loop used, so the handles
 * arrive in the same sequence and the jobs land at the same positions.
 *
 * One behaviour does change, in the safe direction: the old loop indexed
 * straight into pPool->installed and would have segfaulted if there were
 * no installed repo, where TDNFInstalledGetPkgIds() reports the missing
 * sack instead.
 */
static uint32_t
TDNFAddUserInstalledToJobs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs
    )
{
    uint32_t dwError = 0;
    struct history_ctx *pHistoryCtx = NULL;
    uint32_t nTraceStart = 0;
    char *pszName = NULL;
    TDNF_ID_LIST qInstalled = {0};
    int k = 0;

    if(!pTdnf || !pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNFIdListInit(&qInstalled);

    dwError = TDNFGetHistoryCtx(pTdnf, &pHistoryCtx, 1);
    BAIL_ON_TDNF_ERROR(dwError);

    nTraceStart = pQueueJobs->dwCount;

    dwError = TDNFNativeQueryInstalledPkgIds(pTdnf->pSack, &qInstalled);
    BAIL_ON_TDNF_ERROR(dwError);

    for(k = 0; k < (int)qInstalled.dwCount; k++)
    {
        TDNF_PKG_ID p = qInstalled.pnElements[k];
        int nAutoFlag = 0;

        TDNF_SAFE_FREE_MEMORY(pszName);
        dwError = GoalGetPkgNameFromHandle(pTdnf, p, &pszName);
        BAIL_ON_TDNF_ERROR(dwError);

        if(history_get_auto_flag(pHistoryCtx, pszName, &nAutoFlag) != 0)
        {
            dwError = ERROR_TDNF_HISTORY_ERROR;
            BAIL_ON_TDNF_ERROR(dwError);
        }

        /* Auto-installed packages are the solver's to remove; only the
           ones the user asked for are pinned. */
        if(nAutoFlag != 0)
        {
            continue;
        }

        dwError = TDNFIdListPush2(pQueueJobs,
                      TDNF_JOB_SOLVABLE|TDNF_JOB_USERINSTALLED, p);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNFTransactionPlanRequestTraceRecordPackageJobRange(pTdnf->pRequestTrace, pQueueJobs->pnElements,
        nTraceStart, pQueueJobs->dwCount, TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
        TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszName);
    TDNFIdListFree(&qInstalled);
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
    PTDNF_PKG_INFO pInstalledPkgs = NULL;
    uint32_t dwInstalledPkgCount = 0;

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
        nFlags = nFlags | TDNF_JOB_FORCEBEST;
    }
    if (nAutoErase)
    {
        nFlags = nFlags | TDNF_JOB_CLEANDEPS;
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
        if (!pTdnf->pSack)
        {
            dwError = ERROR_TDNF_INVALID_PARAMETER;
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

    /* Locks and install-only names are filtered against the installed set.
       Listing it is only worth doing when something is configured. */
    if((pTdnf->pConf->ppszInstallOnlyPkgs &&
        pTdnf->pConf->ppszInstallOnlyPkgs[0]) ||
       (pTdnf->pConf->ppszPkgLocks && pTdnf->pConf->ppszPkgLocks[0]))
    {
        dwError = TDNFGoalLoadInstalledPkgs(
                      pTdnf, &pInstalledPkgs, &dwInstalledPkgCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFSolvAddInstallOnlyPkgs(pTdnf, pQueueJobs,
                                         pInstalledPkgs, dwInstalledPkgCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFSolvAddPkgLocks(pTdnf, pQueueJobs,
                                  pInstalledPkgs, dwInstalledPkgCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFGoalAddHiddenPackages(
                  pTdnf,
                  dwExcludeCount != 0 ? ppszExcludes : NULL);
    BAIL_ON_TDNF_ERROR(dwError);

    if(nAllowErasing && pTdnf->pConf->ppszProtectedPkgs)
    {
        dwError = TDNFSolvAddProtectPkgs(pTdnf, pQueueJobs);
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
       ((dwError == ERROR_TDNF_CALL_NOT_SUPPORTED ||
         dwError == ERROR_TDNF_SOLV_FAILED) &&
        pTdnf->pConf->ppszProtectedPkgs))
    {
        /* The second case is the native solver refusing a policy combination
           outright -- today, skip-broken together with protected packages.
           libsolv did not honour protection during the solve either: it
           produced a transaction regardless and
           TDNFSolvCheckProtectPkgsInTrans rejected it afterwards. Asking the
           same question here keeps that answer: if the transaction the
           request would have had removes a protected package, that is what
           the user is told. If it does not, the refusal stands untouched.

           The third case is a protected package the request never names:
           protection is a solve policy, so keeping a protected dependent
           installed makes erasing what it requires unsatisfiable, and the
           solve fails as an ordinary dependency problem with no mention of
           protection. Asking the same question sorts the two apart, because
           the probe re-solves with the protected names dropped and only
           names a package when that made the request solvable. A request
           that is unsatisfiable for its own reasons fails the probe too and
           keeps its solver error. */
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
        pQueueJobs->dwCount, TDNF_JOB_CLEANDEPS, TDNF_JOB_FORCEBEST);
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
    if(pInstalledPkgs)
    {
        TDNFFreePackageInfoArray(pInstalledPkgs, dwInstalledPkgCount);
    }
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
    char **ppszPackageRefs = NULL;
    uint32_t dwRefCount = 0;
    PTDNF_PKG_INFO pPkgInfo = NULL;
    PTDNF_SOLVED_PKG_INFO pInfo = NULL;

    if(!pTdnf || !ppInfo || !pQueuePkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* These two reproduce the deleted SolvIdsToPackageList's guards, in its
       order, because both codes are observable and neither is the
       ERROR_TDNF_NO_MATCH the refs path raises for an empty ref set. A queue
       that was never pushed to still has pnElements NULL, which reported
       ERROR_TDNF_INVALID_PARAMETER (1622); a queue that was pushed to and
       then emptied keeps its allocation (TDNFIdListEmpty clears only
       dwCount), so it reported ERROR_TDNF_NO_DATA. An A/B probe of
       `install --nodeps --downloadonly` on an already-installed package
       caught the first case being collapsed into the second. */
    if(!pQueuePkgList->pnElements)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pQueuePkgList->dwCount == 0)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQuerySerializeQueuePackageRefs(
                  pTdnf->pSack,
                  pQueuePkgList,
                  &ppszPackageRefs,
                  &dwRefCount);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFPopulatePkgInfosFromRefs(
                  pTdnf->pSack,
                  ppszPackageRefs,
                  dwRefCount,
                  &pPkgInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(TDNF_SOLVED_PKG_INFO),
                  (void**)&pInfo);
    BAIL_ON_TDNF_ERROR(dwError);

    pInfo->pPkgsToInstall = pPkgInfo;
    *ppInfo = pInfo;

cleanup:
    TDNFFreeStringArray(ppszPackageRefs);
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
        dwError = TDNFIdListPush2(&queueJobs, TDNF_JOB_UPDATE|TDNF_JOB_SOLVABLE_ALL, 0);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNFTransactionPlanRequestTraceRecordAllJob(pTdnf->pRequestTrace, nTraceStart / 2,
            TDNF_TRANSACTION_PLAN_CAPTURE_JOB_UPDATE, queueJobs.pnElements[nTraceStart], 0,
            TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER, 0);
    }
    else if(nAlterType == ALTER_DISTRO_SYNC)
    {
        nTraceStart = queueJobs.dwCount;
        dwError = TDNFIdListPush2(&queueJobs, TDNF_JOB_DISTUPGRADE|TDNF_JOB_SOLVABLE_ALL, 0);
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
            TDNF_PKG_ID dwId = pQueuePkgList->pnElements[i];
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
        /* A root with no history database has nothing to pin, and that has
           always been tolerated here. Every other failure is different: the
           jobs are pushed one package at a time, so bailing part way leaves
           a truncated pin set, and running the solve on it would quietly
           treat explicitly installed packages as automatic and offer to
           erase them. Only the no-database case is absorbed. */
        dwError = TDNFAddUserInstalledToJobs(pTdnf, &queueJobs);
        if(dwError == ERROR_TDNF_HISTORY_NODB)
        {
            dwError = 0;
        }
        BAIL_ON_TDNF_ERROR(dwError);
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
GoalGetPkgNameFromHandle(
    PTDNF pTdnf,
    TDNF_PKG_ID dwPkgId,
    char **ppszName
    )
{
    uint32_t dwError = 0;
    uint32_t dwEpoch = 0;
    char *pszRef = NULL;
    char *pszRepo = NULL;
    char *pszName = NULL;
    char *pszVersion = NULL;
    char *pszRelease = NULL;
    char *pszArch = NULL;

    if(!pTdnf || !ppszName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFNativeQuerySerializePackageId(pTdnf->pSack, dwPkgId, &pszRef);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFNativeQuerySplitPackageRef(pszRef, &pszRepo, &dwEpoch,
                  &pszName, &pszVersion, &pszRelease, &pszArch);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszName = pszName;
    pszName = NULL;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszRef);
    TDNF_SAFE_FREE_MEMORY(pszRepo);
    TDNF_SAFE_FREE_MEMORY(pszName);
    TDNF_SAFE_FREE_MEMORY(pszVersion);
    TDNF_SAFE_FREE_MEMORY(pszRelease);
    TDNF_SAFE_FREE_MEMORY(pszArch);
    return dwError;

error:
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
    int nSkipBrokenSolve = 0;
    if(!pTdnf || !pTdnf->pArgs || !pTdnf->pConf || !pTdnf->pSack ||
       !pTdnf->pRpmConfig || !pQueueJobs ||
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

    /* --skip-broken means two different things, and `check` wants the other
       one. For an alter command it selects a solve that drops the individual
       jobs it cannot satisfy and installs the rest. For `check` there are no
       jobs the user asked for -- TDNFCheckPackages resolves `install *`, so
       every package in the universe is a job -- and dropping the broken ones
       is not a question anyone asked. What --skip-broken means there is the
       reporting filter SKIPPROBLEM_BROKEN, which hides dependency problems
       from the report TDNFSolv prints when the solve fails.

       Requesting the solve as well is not merely redundant: it is quadratic
       in the number of jobs, so the native solver refuses job lists longer
       than max_skip_broken_jobs (64) rather than run it. `check` always
       exceeds that, and the refusal surfaced as
       "Error(1638) : Function not implemented". */
    nSkipBrokenSolve = pTdnf->pArgs->nSkipBroken;
    if(pTdnf->pArgs->nCmdCount > 0 && pTdnf->pArgs->ppszCmds &&
       pTdnf->pArgs->ppszCmds[0] &&
       strcmp(pTdnf->pArgs->ppszCmds[0], "check") == 0)
    {
        nSkipBrokenSolve = 0;
    }

    dwError = TDNFRepoMdNativeSolverLiveSolve(
                  pRepos, dwRepoCount, pJobs, dwJobCount,
                  pEraseJobs, dwEraseJobCount, pHiddenAvailable, dwHiddenAvailableCount,
                  pTdnf->pArgs->nAllDeps, pTdnf->pArgs->nBest, nAutoErase, nSkipBrokenSolve, nAllowErasing,
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
    /* Only the install jobs can have contributed a path, and each entry is an
       owned copy, so free by count -- the array is sparse and a NULL hole would
       stop TDNFFreeStringArray() early. */
    if(ppszCmdLinePaths)
    {
        TDNFFreeStringArrayWithCount(ppszCmdLinePaths, (int)dwJobCount);
        ppszCmdLinePaths = NULL;
    }
    /* Owns its elements: the names come from split refs. The array is
       allocated with a spare zeroed slot, so it is NULL-terminated. */
    TDNFFreeStringArray(ppszUserInstalledPkgs);
    TDNF_SAFE_FREE_MEMORY(ppszInstallOnlyPkgs);
    TDNFGoalFreeNativeSolverHiddenAvailable(pHiddenAvailable, dwHiddenAvailableCount);
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
    /* Job identity is read back from a native ref, so these hold the split
       fields for the pair being translated. They are function-scoped rather
       than loop-scoped so every exit frees whatever the current iteration
       had not yet handed to a job. */
    char *pszJobRef = NULL;
    char *pszJobRepo = NULL;
    char *pszJobName = NULL;
    char *pszJobVersion = NULL;
    char *pszJobRelease = NULL;
    char *pszJobArch = NULL;
    uint32_t dwJobEpoch = 0;
    int nUpdateAll = 0;
    int nDistSyncAll = 0;
    uint32_t dwGlobalQueuePair = 0;
    int nHasGlobalQueuePair = 0;

    /* pSack->pPool is still checked although this function no longer
       reads the pool: dropping the check would let a caller with a
       half-built sack through, which is a behaviour change this
       increment does not want to make on the side. */
    if(!pTdnf || !pTdnf->pArgs || !pTdnf->pConf || !pTdnf->pSack ||
       !pQueueJobs || !ppJobs || !pdwJobCount ||
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
        int32_t rawHow = pQueueJobs->pnElements[dwIndex * 2];
        int32_t how = nStamped ? rawHow ^ nStampFlags : rawHow;
        /* The operand slot is polymorphic, so it is read untyped here and
           given a type below by whichever branch the decoded how word
           selects: a string handle for the name-selected jobs, a package
           handle for the rest, and an ignored zero for the ALL jobs. */
        int32_t nRawWhat = pQueueJobs->pnElements[dwIndex * 2 + 1];
        TDNF_PKG_ID dwPkgId = nRawWhat;
        int nIsInstalled = 0;
        PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJob = NULL;
        int nInstall = how == (TDNF_JOB_SOLVABLE | TDNF_JOB_INSTALL),
            nErase = nStamped && how == (TDNF_JOB_SOLVABLE | TDNF_JOB_ERASE),
            nUserInstalled = how == (TDNF_JOB_SOLVABLE | TDNF_JOB_USERINSTALLED) ||
                rawHow == (TDNF_JOB_SOLVABLE | TDNF_JOB_USERINSTALLED),
            nAllowUninstall = rawHow == (TDNF_JOB_SOLVABLE | TDNF_JOB_ALLOWUNINSTALL),
            nLocked = rawHow == (TDNF_JOB_SOLVABLE_NAME | TDNF_JOB_LOCK),
            nInstallOnly =
                rawHow == (TDNF_JOB_SOLVABLE_NAME | TDNF_JOB_MULTIVERSION),
            nUpdateAllJob = how == (TDNF_JOB_SOLVABLE_ALL | TDNF_JOB_UPDATE),
            nDistSyncAllJob = how == (TDNF_JOB_SOLVABLE_ALL | TDNF_JOB_DISTUPGRADE);
        if(!nStamped && how == (TDNF_JOB_SOLVABLE | TDNF_JOB_ERASE)) continue;
        if((nUpdateAllJob || nDistSyncAllJob) && !nRawWhat && !nUpdateAll && !nDistSyncAll)
        {
            nUpdateAll = nUpdateAllJob;
            nDistSyncAll = nDistSyncAllJob;
            dwGlobalQueuePair = dwIndex;
            nHasGlobalQueuePair = 1;
            continue;
        }
        if(nLocked)
        {
            const char *pszName = NULL;
            if(nRawWhat < 0 || !pTdnf->pConf->ppszPkgLocks ||
               !(pszName = pTdnf->pConf->ppszPkgLocks[nRawWhat]))
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
            const char *pszName = NULL;
            if(nRawWhat < 0 || !pTdnf->pConf->ppszInstallOnlyPkgs ||
               !(pszName = pTdnf->pConf->ppszInstallOnlyPkgs[nRawWhat]))
            {
                dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
                BAIL_ON_TDNF_ERROR(dwError);
            }
            ppszInstallOnlyPkgs[dwInstallOnlyCount++] = (char *)pszName;
            continue;
        }
        if(!nInstall && !nErase && !nUserInstalled && !nAllowUninstall)
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        /* The operand's package identity is read back as a native ref
           rather than re-queried from the pool: the ref carries the repo
           and the NEVRA, which is everything below it needs.

           This also subsumes the separate TDNFPkgHandleIsValid() call it
           replaced -- that helper has since been deleted, having no
           callers left -- but only because the accessor underneath now
           performs
           that same range check itself: an out-of-range handle is refused
           by PkgHandleToSolvable(), and handle 0 survives to produce an
           empty repository, which the split below rejects. Both outcomes
           reach ERROR_TDNF_CALL_NOT_SUPPORTED, which is what the explicit
           check reported. */
        TDNF_SAFE_FREE_MEMORY(pszJobRef);
        if(TDNFNativeQuerySerializePackageId(pTdnf->pSack, dwPkgId, &pszJobRef))
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        TDNF_SAFE_FREE_MEMORY(pszJobRepo);
        TDNF_SAFE_FREE_MEMORY(pszJobName);
        TDNF_SAFE_FREE_MEMORY(pszJobVersion);
        TDNF_SAFE_FREE_MEMORY(pszJobRelease);
        TDNF_SAFE_FREE_MEMORY(pszJobArch);
        if(TDNFNativeQuerySplitPackageRef(pszJobRef, &pszJobRepo, &dwJobEpoch,
               &pszJobName, &pszJobVersion, &pszJobRelease, &pszJobArch))
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        /* solv/tdnfpool.c creates exactly one repo named SYSTEM_REPO_NAME
           and immediately makes it the pool's installed repo, so the name
           test is equivalent to the repo-pointer test it replaced. This is
           the same reasoning the CMDLINE_REPO_NAME test below already
           relies on. */
        nIsInstalled = !strcmp(pszJobRepo, SYSTEM_REPO_NAME);
        /* An install job must name something not yet installed, and an
           erase job must name something that is. */
        if(nInstall ? nIsInstalled : !nIsInstalled)
        {
            dwError = ERROR_TDNF_CALL_NOT_SUPPORTED;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if(nUserInstalled || nAllowUninstall)
        {
            if(nUserInstalled)
            {
                /* Handed over, not borrowed: the name came from the split
                   ref, so the array owns it and is freed element-wise. */
                ppszUserInstalledPkgs[dwUserInstalledCount++] = pszJobName;
                pszJobName = NULL;
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
        /* Cleared at the point of transfer, not at the end of the loop
           body: a bail between here and there would otherwise let both the
           job list and the cleanup label free the same string. */
        pJob->pszRepository = pszJobRepo;
        pszJobRepo = NULL;
        /* A command-line solvable has no downloadable metadata, so the native
           solver rebuilds it from the .rpm that libsolv itself read.
           Testing the repo name alone is equivalent to also comparing against
           pTdnf->pCmdLineRepo: every writer of that slot creates the repo
           as CMDLINE_REPO_NAME, so pointer equality implies name equality. */
        if(!strcmp(pJob->pszRepository, CMDLINE_REPO_NAME))
        {
            /* Allocated, not borrowed: this array outlives the loop.

               The path is looked up rather than re-derived from libsolv.
               A miss is not a fallback case, it is an invariant
               violation: TDNFAddCmdLinePackages empties the table and
               then re-adds every command-line .rpm through
               TDNFRepoMdNativeAddRpm, recording the path as it goes, and
               that is the only thing that ever puts a solvable in this
               repo -- so the table describes exactly the current
               generation of it. Nothing else can be named "cmdline"
               either: all three repo-creation paths
               (client/repolist.c:376, :466 and :692) reject that id as
               reserved. So a miss is reported rather than papered over.

               This error is deliberately NOT remapped to
               ERROR_TDNF_CALL_NOT_SUPPORTED. A handle that names no
               package has already been rejected by the serialization
               above, so the only failure this call site has ever
               propagated is an allocation one, and that is preserved. */
            dwError = TDNFFindCmdLinePkgPath(
                          pTdnf, dwPkgId, &ppszCmdLinePaths[dwInstallCount - 1]);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        /* Ownership moves into the job; the loop's locals are cleared so
           the next iteration does not free strings the job now holds. */
        pJob->dwEpoch = dwJobEpoch;
        pJob->pszName = pszJobName;
        pJob->pszVersion = pszJobVersion;
        pJob->pszRelease = pszJobRelease;
        pJob->pszArch = pszJobArch;
        pszJobName = NULL;
        pszJobVersion = NULL;
        pszJobRelease = NULL;
        pszJobArch = NULL;
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
    TDNF_SAFE_FREE_MEMORY(pszJobRef);
    TDNF_SAFE_FREE_MEMORY(pszJobRepo);
    TDNF_SAFE_FREE_MEMORY(pszJobName);
    TDNF_SAFE_FREE_MEMORY(pszJobVersion);
    TDNF_SAFE_FREE_MEMORY(pszJobRelease);
    TDNF_SAFE_FREE_MEMORY(pszJobArch);
    return dwError;
error:
    TDNF_SAFE_FREE_MEMORY(ppszLockedPkgs);
    TDNF_SAFE_FREE_MEMORY(pdwLockedQueuePairs);
    if(ppszCmdLinePaths)
    {
        TDNFFreeStringArrayWithCount(ppszCmdLinePaths, (int)dwCount);
        ppszCmdLinePaths = NULL;
    }
    /* Owns its elements: the names come from split refs. The array is
       allocated with a spare zeroed slot, so it is NULL-terminated. */
    TDNFFreeStringArray(ppszUserInstalledPkgs);
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
        char *pszRepository = (char *)pJobs[dwIndex].pszRepository;
        TDNF_SAFE_FREE_MEMORY(pszName);
        TDNF_SAFE_FREE_MEMORY(pszVersion);
        TDNF_SAFE_FREE_MEMORY(pszRelease);
        TDNF_SAFE_FREE_MEMORY(pszArch);
        TDNF_SAFE_FREE_MEMORY(pszRepository);
        pJobs[dwIndex].pszName = NULL;
        pJobs[dwIndex].pszVersion = NULL;
        pJobs[dwIndex].pszRelease = NULL;
        pJobs[dwIndex].pszArch = NULL;
        pJobs[dwIndex].pszRepository = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pJobs);
}

/*
 * Both job lists are now built from native ref strings and so own every
 * string they carry, including the repository. This kept its own name only
 * because the two used to differ.
 */
static
void
TDNFGoalFreeNativeSolverHiddenAvailable(
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJobs,
    uint32_t dwJobCount
    )
{
    TDNFGoalFreeNativeSolverJobs(pJobs, dwJobCount);
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
    uint32_t i = 0;
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pHiddenAvailable = NULL;

    if(!pTdnf || !ppHiddenAvailable || !pdwHiddenAvailableCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if(!pTdnf->dwHiddenRefCount)
    {
        goto cleanup;
    }

    dwError = TDNFAllocateMemory(
                  pTdnf->dwHiddenRefCount,
                  sizeof(TDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB),
                  (void **)&pHiddenAvailable);
    BAIL_ON_TDNF_ERROR(dwError);
    dwCount = pTdnf->dwHiddenRefCount;

    for(i = 0; i < pTdnf->dwHiddenRefCount; i++)
    {
        int nSkip = 0;

        dwError = TDNFGoalSplitHiddenRef(
                      pTdnf->ppszHiddenRefs[i],
                      &pHiddenAvailable[dwIndex],
                      &nSkip);
        BAIL_ON_TDNF_ERROR(dwError);
        if(nSkip)
        {
            continue;
        }
        dwIndex++;
    }

    if(!dwIndex)
    {
        goto cleanup;
    }

    *ppHiddenAvailable = pHiddenAvailable;
    *pdwHiddenAvailableCount = dwIndex;
    pHiddenAvailable = NULL;

cleanup:
    TDNFGoalFreeNativeSolverHiddenAvailable(pHiddenAvailable, dwCount);
    return dwError;
error:
    goto cleanup;
}

/*
 * Split one "repo\x1fN-E:V-R.A" hidden ref into the native solver's job
 * shape. The solver only accepts available packages, so installed and
 * command-line refs are reported as skipped rather than translated -- the
 * same two exclusions the pool walk used to apply.
 *
 * The pool walk needed a third exclusion, for the "patch:" pseudo-solvables
 * libsolv synthesises from updateinfo. Those exist only in the pool; the
 * native package model has no such entries, so no ref can name one and the
 * check has nothing left to reject.
 */
static
uint32_t
TDNFGoalSplitHiddenRef(
    const char *pszRef,
    PTDNF_REPOMD_NATIVE_SOLVER_LIVE_JOB pJob,
    int *pnSkip
    )
{
    uint32_t dwError = 0;
    char *pszRepo = NULL;
    char *pszName = NULL;
    char *pszVersion = NULL;
    char *pszRelease = NULL;
    char *pszArch = NULL;
    uint32_t dwEpoch = 0;

    if(IsNullOrEmptyString(pszRef) || !pJob || !pnSkip)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    *pnSkip = 0;

    dwError = TDNFNativeQuerySplitPackageRef(
                  pszRef,
                  &pszRepo,
                  &dwEpoch,
                  &pszName,
                  &pszVersion,
                  &pszRelease,
                  &pszArch);
    BAIL_ON_TDNF_ERROR(dwError);

    if(!strcmp(pszRepo, SYSTEM_REPO_NAME) ||
       !strcmp(pszRepo, CMDLINE_REPO_NAME))
    {
        *pnSkip = 1;
        goto cleanup;
    }

    pJob->pszRepository = pszRepo;
    pJob->dwEpoch = dwEpoch;
    pJob->pszName = pszName;
    pJob->pszVersion = pszVersion;
    pJob->pszRelease = pszRelease;
    pJob->pszArch = pszArch;
    pszRepo = NULL;
    pszName = NULL;
    pszVersion = NULL;
    pszRelease = NULL;
    pszArch = NULL;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszRepo);
    TDNF_SAFE_FREE_MEMORY(pszName);
    TDNF_SAFE_FREE_MEMORY(pszVersion);
    TDNF_SAFE_FREE_MEMORY(pszRelease);
    TDNF_SAFE_FREE_MEMORY(pszArch);
    return dwError;
error:
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
        dwError = GoalGetPkgNameFromHandle(
                       pTdnf,
                       pQueueGoal->pnElements[i],
                       &ppszPkgsUserInstall[i]);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppInfo->ppszPkgsUserInstall = ppszPkgsUserInstall;
cleanup:
    return dwError;
error:
    /* Frees the names too. Bailing partway through the loop above leaves
       the earlier ones allocated, and releasing only the array leaked
       them; the spare zeroed slot terminates the walk. */
    TDNFFreeStringArray(ppszPkgsUserInstall);
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
    TDNF_PKG_ID dwId,
    uint32_t dwCount,
    char** ppszExcludes
    )
{
    uint32_t dwError = 0;
    char** ppszPackagesTemp = NULL;
    char* pszName = NULL;
    uint32_t nTraceStart = 0;

    if(!pTdnf || !pQueueJobs || dwId == 0 || !pTdnf->pSack ||
       !pTdnf->pSack)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    nTraceStart = pQueueJobs->dwCount;

    if (dwCount != 0 && ppszExcludes)
    {
        dwError = GoalGetPkgNameFromHandle(pTdnf, dwId, &pszName);
        BAIL_ON_TDNF_ERROR(dwError);
        ppszPackagesTemp = ppszExcludes;

        while(ppszPackagesTemp && *ppszPackagesTemp)
        {
            if (TDNFIsGlob(*ppszPackagesTemp))
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
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE|TDNF_JOB_INSTALL, dwId);
            BAIL_ON_TDNF_ERROR(dwError);
            break;
        case ALTER_ERASE:
        case ALTER_AUTOERASE:
        case ALTER_AUTOERASEALL:
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE|TDNF_JOB_ERASE, dwId);
            BAIL_ON_TDNF_ERROR(dwError);
            break;
        case ALTER_REINSTALL:
        case ALTER_INSTALL:
        case ALTER_UPGRADE:
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE|TDNF_JOB_INSTALL, dwId);
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

static uint32_t
TDNFSolvAddPkgLocks(PTDNF pTdnf, PTDNF_ID_LIST pQueueJobs,
                    PTDNF_PKG_INFO pInstalled, uint32_t dwInstalledCount)
{
    uint32_t dwError = 0;
    int i;
    if(!pTdnf || !pQueueJobs) dwError = ERROR_TDNF_INVALID_PARAMETER;
    BAIL_ON_TDNF_ERROR(dwError);
    for (i = 0; pTdnf->pConf->ppszPkgLocks && pTdnf->pConf->ppszPkgLocks[i]; i++)
    {
        char *pszPkg = pTdnf->pConf->ppszPkgLocks[i];
        if (IsNullOrEmptyString(pszPkg)) continue;
        if (TDNFGoalNameIsInstalled(pszPkg, pInstalled, dwInstalledCount))
        {
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE_NAME|TDNF_JOB_LOCK, i);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordNameJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_LOCK, pszPkg, TDNF_JOB_SOLVABLE_NAME|TDNF_JOB_LOCK, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        }
    }
cleanup:
    return dwError;
error:
    goto cleanup;
}

static uint32_t
TDNFSolvAddInstallOnlyPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs,
    PTDNF_PKG_INFO pInstalled,
    uint32_t dwInstalledCount
    )
{
    uint32_t dwError = 0;
    char **ppszPackages = NULL;
    int i;

    if(!pTdnf || !pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppszPackages = pTdnf->pConf->ppszInstallOnlyPkgs;

    for (i = 0; ppszPackages && ppszPackages[i]; i++)
    {
        char *pszPkg = ppszPackages[i];
        if (IsNullOrEmptyString(pszPkg))
        {
            continue;
        }
        /* Name multiversion jobs matter only when an instance exists. */
        if (TDNFGoalNameIsInstalled(pszPkg, pInstalled, dwInstalledCount))
        {
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE_NAME|TDNF_JOB_MULTIVERSION, i);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordNameJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_MULTIVERSION, pszPkg, TDNF_JOB_SOLVABLE_NAME|TDNF_JOB_MULTIVERSION, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        }
    }

cleanup:
    return dwError;
error:
    goto cleanup;
}

/*
 * The installed set backing TDNFSolvAddPkgLocks and
 * TDNFSolvAddInstallOnlyPkgs. Both used to intern each configured name into
 * the libsolv pool and ask the pool whether an installed solvable carried it;
 * the pool was doing nothing but string interning and an installed-name
 * lookup, and the interned Id was handed straight back to
 * TDNFGoalBuildNativeSolverJobs which turned it back into the same string.
 *
 * The whole set is listed once, unfiltered, and compared by exact name:
 * passing the configured names as specs would subject them to the native
 * lister's glob matching, which the pool lookup never did.
 *
 * The filter is load-bearing, and not merely for bookkeeping -- but only for
 * locks. solver_rules.zig's `.lock` arm emits
 * Literal.init(id, package.installed != null), which for an
 * available-but-uninstalled package is a negative unit clause forbidding its
 * installation, and nothing downstream gates lock names on installed state.
 * So emitting a lock job for a configured name that names nothing installed
 * would refuse installs that must succeed. This filter is the only gate.
 *
 * For multiversion it is redundant, not load-bearing: solver_coordinator.zig's
 * hasInstalledName check drops the multiversion job for a name with nothing
 * installed before any rule is generated, and that is the sole production
 * producer of such jobs. Do not assume this filter covers what that one does.
 * What it still buys for multiversion is consistency of the recorded job set:
 * `tdnf plan` would otherwise advertise a multiversion job the solver discards.
 *
 * Mutation-checked against the 21-probe a62a set: never emitting a
 * lock/multiversion job moves 13, an off-by-one in the lock index moves 10,
 * skipping config index 0 in the install-only producer moves 4, and deleting
 * this filter moves 3 -- two `tdnf plan` probes plus one transaction whose
 * outcome flips from a successful install to a refusal.
 */
static
uint32_t
TDNFGoalLoadInstalledPkgs(
    PTDNF pTdnf,
    PTDNF_PKG_INFO *ppPkgInfo,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;

    if(!pTdnf || !ppPkgInfo || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* No repo inputs: SCOPE_INSTALLED admits only the installed dataset, which
       is built from pRpmConfig alone. Passing enabled repos here would parse
       every repomd.xml and primary.xml only for the scope filter to drop them. */
    dwError = TDNFRepoMdNativeListConfig(
                  NULL,
                  0,
                  pTdnf->pRpmConfig,
                  SCOPE_INSTALLED,
                  NULL,
                  DETAIL_LIST,
                  ppPkgInfo,
                  pdwCount);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    return dwError;
error:
    goto cleanup;
}

static
int
TDNFGoalNameIsInstalled(
    const char *pszName,
    PTDNF_PKG_INFO pPkgInfo,
    uint32_t dwInstalledCount
    )
{
    uint32_t i = 0;

    if(IsNullOrEmptyString(pszName) || !pPkgInfo)
    {
        return 0;
    }

    for(i = 0; i < dwInstalledCount; i++)
    {
        if(!IsNullOrEmptyString(pPkgInfo[i].pszName) &&
           strcmp(pPkgInfo[i].pszName, pszName) == 0)
        {
            return 1;
        }
    }

    return 0;
}


/*
 * Collect every package hidden from the solver -- by excludepkgs/--exclude
 * and by minversions -- as native "repo\x1fNEVRA" refs on the handle.
 *
 * Both sets used to be derived by scanning the libsolv pool: excludes matched
 * SOLVABLE_NAME through a Dataiterator, minversions resolved native ref lines
 * back to solvable Ids. Both are now produced natively and kept as refs, so
 * neither this function nor TDNFGoalBuildNativeSolverHiddenAvailable touches
 * the pool.
 *
 * Each ref is still resolved once below. That is a validation, not
 * bookkeeping: it is the only place that proves a hidden ref names exactly
 * one package, and TDNFNativeQueryResolveSinglePackageRef fails when it names
 * none or several.
 */
uint32_t
TDNFGoalAddHiddenPackages(
    PTDNF pTdnf,
    char **ppszExcludes
    )
{
    uint32_t dwError = 0;
    char **ppszExcludeLines = NULL;
    char **ppszMinVersionLines = NULL;
    char **ppszHiddenRefs = NULL;
    uint32_t dwExcludeLineCount = 0;
    uint32_t dwMinVersionLineCount = 0;
    uint32_t dwHiddenRefCount = 0;
    PTDNF_REPOMD_NATIVE_REPO_INPUT pRepos = NULL;
    uint32_t dwRepoCount = 0;
    uint32_t i = 0;

    if(!pTdnf || !pTdnf->pConf)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    TDNF_SAFE_FREE_STRINGARRAY(pTdnf->ppszHiddenRefs);
    pTdnf->dwHiddenRefCount = 0;

    if(!ppszExcludes && !pTdnf->pConf->ppszMinVersions)
    {
        goto cleanup;
    }

    dwError = TDNFNativeQueryBuildRepoInputs(pTdnf, &pRepos, &dwRepoCount);
    BAIL_ON_TDNF_ERROR(dwError);

    if(ppszExcludes)
    {
        dwError = TDNFRepoMdNativeExcludeLinesConfig(
                      pRepos,
                      dwRepoCount,
                      pTdnf->pRpmConfig,
                      ppszExcludes,
                      &ppszExcludeLines,
                      &dwExcludeLineCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pTdnf->pConf->ppszMinVersions)
    {
        dwError = TDNFRepoMdNativeMinVersionExcludeLinesConfig(
                      pRepos,
                      dwRepoCount,
                      pTdnf->pRpmConfig,
                      pTdnf->pConf->ppszMinVersions,
                      &ppszMinVersionLines,
                      &dwMinVersionLineCount);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(dwExcludeLineCount == 0 && dwMinVersionLineCount == 0)
    {
        goto cleanup;
    }

    /* One spare element so the array is NULL-terminated for
       TDNFFreeStringArray. A package caught by both filters must appear
       once: the native solver rejects a repeated hidden package outright. */
    dwError = TDNFAllocateMemory(
                  dwExcludeLineCount + dwMinVersionLineCount + 1,
                  sizeof(char *),
                  (void **)&ppszHiddenRefs);
    BAIL_ON_TDNF_ERROR(dwError);

    for(i = 0; i < dwExcludeLineCount + dwMinVersionLineCount; i++)
    {
        const char *pszLine = i < dwExcludeLineCount
            ? ppszExcludeLines[i]
            : ppszMinVersionLines[i - dwExcludeLineCount];
        uint32_t dwSeen = 0;

        for(dwSeen = 0; dwSeen < dwHiddenRefCount; dwSeen++)
        {
            if(!strcmp(ppszHiddenRefs[dwSeen], pszLine))
            {
                break;
            }
        }
        if(dwSeen < dwHiddenRefCount)
        {
            continue;
        }

        dwError = TDNFAllocateString(pszLine, &ppszHiddenRefs[dwHiddenRefCount]);
        BAIL_ON_TDNF_ERROR(dwError);
        dwHiddenRefCount++;
    }

    for(i = 0; i < dwHiddenRefCount; i++)
    {
        TDNF_PKG_ID dwPkgId = 0;

        dwError = TDNFNativeQueryResolveSinglePackageRef(
                      pTdnf->pSack,
                      ppszHiddenRefs[i],
                      0,
                      &dwPkgId);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pTdnf->ppszHiddenRefs = ppszHiddenRefs;
    pTdnf->dwHiddenRefCount = dwHiddenRefCount;
    ppszHiddenRefs = NULL;

cleanup:
    TDNF_SAFE_FREE_STRINGARRAY(ppszHiddenRefs);
    TDNFFreeStringArray(ppszExcludeLines);
    TDNFFreeStringArray(ppszMinVersionLines);
    TDNFNativeQueryFreeRepoInputs(pRepos, dwRepoCount);
    return dwError;
error:
    goto cleanup;
}

/*
 * Protected-package matching used to run in the pool's string-id space:
 * intern every configured name, ask each candidate handle for its name id,
 * and compare ids. libsolv interns each distinct string exactly once, so id
 * equality there was string equality -- which makes comparing the names
 * themselves the same test, expressed without the pool. It is also the test
 * TDNFFindProtectedPkg() below already applies to the same configured list,
 * so the two protected-package checks now agree by construction instead of
 * by coincidence.
 *
 * Two things improve as a side effect. TDNFStrIdFromString() -- since
 * deleted, this having been its last caller -- passed
 * create=1, so every configured name was interned into the pool's string
 * table whether or not any package had it; nothing is interned now. And the
 * old code took the matching name from ppszProtectedPkgs[] using a position
 * in a separate id list that skipped entries whose id was zero -- sound only
 * because create=1 meant the id was never zero. Returning the matched entry
 * itself removes that coupling.
 */
static
const char *
GoalFindProtectedName(
    char **ppszProtectedPkgs,
    const char *pszName
    )
{
    int i = 0;

    if(!ppszProtectedPkgs || IsNullOrEmptyString(pszName))
    {
        return NULL;
    }

    for(i = 0; ppszProtectedPkgs[i]; i++)
    {
        if(!strcmp(ppszProtectedPkgs[i], pszName))
        {
            return ppszProtectedPkgs[i];
        }
    }
    return NULL;
}

static
uint32_t
TDNFSolvAddProtectPkgs(
    PTDNF pTdnf,
    PTDNF_ID_LIST pQueueJobs
    )
{
    uint32_t dwError = 0;
    char **ppszProtectedPkgs = NULL;
    char *pszWhatName = NULL;
    char *pszAddName = NULL;
    char *pszInstalledName = NULL;
    int i, j, k;
    TDNF_ID_LIST qInstalled = {0};

    if(!pTdnf || !pQueueJobs || !pTdnf->pConf)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    ppszProtectedPkgs = pTdnf->pConf->ppszProtectedPkgs;
    TDNFIdListInit(&qInstalled);

    /* Direct erases of protected names must be rejected explicitly. */
    for (j = 0; j < (int)pQueueJobs->dwCount; j += 2) {
        int32_t how = pQueueJobs->pnElements[j];
        if (((how & TDNF_JOB_JOBMASK) == TDNF_JOB_ERASE) && (how & TDNF_JOB_SOLVABLE)) {
            /* The operand slot is polymorphic -- it holds a string handle
               when the job selects by name. The TDNF_JOB_SOLVABLE test above
               is what makes it a package handle here. */
            TDNF_PKG_ID what = pQueueJobs->pnElements[j+1];
            const char *pszPkgName = NULL;

            TDNF_SAFE_FREE_MEMORY(pszWhatName);
            dwError = GoalGetPkgNameFromHandle(pTdnf, what, &pszWhatName);
            BAIL_ON_TDNF_ERROR(dwError);
            pszPkgName = GoalFindProtectedName(ppszProtectedPkgs, pszWhatName);
            if (pszPkgName) {
                for (i = 0; i < (int)pQueueJobs->dwCount; i += 2) {
                    if (i == j)
                        continue;
                    how = pQueueJobs->pnElements[i];
                    if (((how & TDNF_JOB_JOBMASK) == TDNF_JOB_INSTALL) && (how & TDNF_JOB_SOLVABLE)) {
                        TDNF_PKG_ID what_add = pQueueJobs->pnElements[i+1];

                        TDNF_SAFE_FREE_MEMORY(pszAddName);
                        dwError = GoalGetPkgNameFromHandle(pTdnf, what_add, &pszAddName);
                        BAIL_ON_TDNF_ERROR(dwError);
                        if (!strcmp(pszAddName, pszWhatName)) {
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
    dwError = TDNFNativeQueryInstalledPkgIds(pTdnf->pSack, &qInstalled);
    BAIL_ON_TDNF_ERROR(dwError);
    for (k = 0; k < (int)qInstalled.dwCount; k++) {
        TDNF_PKG_ID p = qInstalled.pnElements[k];

        TDNF_SAFE_FREE_MEMORY(pszInstalledName);
        dwError = GoalGetPkgNameFromHandle(pTdnf, p, &pszInstalledName);
        BAIL_ON_TDNF_ERROR(dwError);
        if (!GoalFindProtectedName(ppszProtectedPkgs, pszInstalledName)) {
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE|TDNF_JOB_ALLOWUNINSTALL, p);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordPackageJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ALLOW_UNINSTALL, p, TDNF_JOB_SOLVABLE|TDNF_JOB_ALLOWUNINSTALL, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        } else {
            dwError = TDNFIdListPush2(pQueueJobs, TDNF_JOB_SOLVABLE|TDNF_JOB_USERINSTALLED, p);
            BAIL_ON_TDNF_ERROR(dwError);
            TDNFTransactionPlanRequestTraceRecordPackageJob(pTdnf->pRequestTrace, pQueueJobs->dwCount / 2 - 1,
                TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED, p, TDNF_JOB_SOLVABLE|TDNF_JOB_USERINSTALLED, 0, TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY,
                TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST);
        }
    }

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszWhatName);
    TDNF_SAFE_FREE_MEMORY(pszAddName);
    TDNF_SAFE_FREE_MEMORY(pszInstalledName);
    TDNFIdListFree(&qInstalled);
    return dwError;
error:
    goto cleanup;
}


/*
 * The local .rpm path recorded for a command-line package handle.
 *
 * A linear scan: the array holds one entry per .rpm named on the
 * command line, and the caller is already inside a loop over the job
 * list, so anything cleverer would cost more to maintain than it saves.
 *
 * ERROR_TDNF_NO_DATA on a miss is a deliberate refusal to fall back.
 * The path used to be re-derived from libsolv, which would have quietly
 * answered for a solvable this table had never seen; there is no such
 * solvable (see the call site for why), so if one ever appears the right
 * answer is to say so rather than to reconstruct it from the component
 * this code is being moved off.
 */
static
uint32_t
TDNFFindCmdLinePkgPath(
    PTDNF pTdnf,
    TDNF_PKG_ID dwPkgId,
    char **ppszPath
    )
{
    uint32_t dwError = 0;
    uint32_t dwIndex = 0;
    char *pszPath = NULL;

    if(!pTdnf || !ppszPath)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for(dwIndex = 0; dwIndex < pTdnf->dwCmdLinePkgCount; dwIndex++)
    {
        if(pTdnf->pdwCmdLinePkgIds[dwIndex] != dwPkgId)
        {
            continue;
        }
        dwError = TDNFAllocateString(
                      pTdnf->ppszCmdLinePkgPaths[dwIndex], &pszPath);
        BAIL_ON_TDNF_ERROR(dwError);
        break;
    }

    if(!pszPath)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppszPath = pszPath;

cleanup:
    return dwError;

error:
    TDNF_SAFE_FREE_MEMORY(pszPath);
    goto cleanup;
}
