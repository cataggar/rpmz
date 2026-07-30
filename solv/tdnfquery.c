/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

#define MODE_INSTALL     1
#define MODE_ERASE       2
#define MODE_UPDATE      3
#define MODE_DISTUPGRADE 4
#define MODE_VERIFY      5
#define MODE_PATCH       6

uint32_t
SolvAddUpgradeAllJob(
    Queue* pQueueJobs
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    queue_push2(pQueueJobs, SOLVER_UPDATE|SOLVER_SOLVABLE_ALL, 0);
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddDistUpgradeJob(
    Queue* pQueueJobs
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    queue_push2(pQueueJobs, SOLVER_DISTUPGRADE|SOLVER_SOLVABLE_ALL, 0);
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddFlagsToJobs(
    Queue* pQueueJobs,
    int nFlags
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    for (int i = 0; i < pQueueJobs->count; i += 2)
    {
        pQueueJobs->elements[i] |= nFlags;
    }
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddUserInstalledToJobs(
    Queue* pQueueJobs,
    Pool *pPool,
    struct history_ctx *pHistoryCtx
    )
{
    uint32_t dwError = 0;
    int rc;
    Id p;
    Solvable *s;

    if(!pQueueJobs || !pPool)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    FOR_REPO_SOLVABLES(pPool->installed, p, s)
    {
        int nFlag = 0;
        const char *pszName = pool_id2str(pPool, s->name);
        rc = history_get_auto_flag(pHistoryCtx, pszName, &nFlag);
        if (rc != 0)
        {
            dwError = ERROR_TDNF_HISTORY_ERROR;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        if (nFlag == 0)
        {
            queue_push2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_USERINSTALLED, p);
        }
    }

cleanup:
    return dwError;
error:
    goto cleanup;
}

uint32_t
SolvAddPkgInstallJob(
    Queue*  pQueueJobs,
    Id      dwId
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    queue_push2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_INSTALL, dwId);
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddPkgDowngradeJob(
    Queue*  pQueueJobs,
    Id      dwId
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    queue_push2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_INSTALL, dwId);
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddPkgEraseJob(
    Queue*  pQueueJobs,
    Id      dwId
    )
{
    uint32_t dwError = 0;
    if(!pQueueJobs)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }
    queue_push2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_ERASE, dwId);
cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvCreateQuery(
    PSolvSack   pSack,
    PSolvQuery* ppQuery
    )
{
    uint32_t dwError = 0;
    PSolvQuery pQuery = NULL;

    if(!pSack || !ppQuery)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(1, sizeof(SolvQuery), (void **)&pQuery);
    BAIL_ON_TDNF_ERROR(dwError);

    pQuery->pSack = pSack;
    queue_init(&pQuery->queueJob);
    queue_init(&pQuery->queueRepoFilter);
    queue_init(&pQuery->queueResult);

    *ppQuery = pQuery;

cleanup:
    return dwError;

error:
    if(ppQuery)
    {
        *ppQuery = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pQuery);
    goto cleanup;
}

void
SolvFreeQuery(
    PSolvQuery pQuery
    )
{
    if(pQuery)
    {
        if(pQuery->pTrans)
        {
            transaction_free(pQuery->pTrans);
        }

        if(pQuery->pSolv)
        {
            solver_free(pQuery->pSolv);
        }

        queue_free(&pQuery->queueJob);
        queue_free(&pQuery->queueRepoFilter);
        queue_free(&pQuery->queueResult);
        if(pQuery->ppszPackageNames)
        {
            TDNFFreeStringArray(pQuery->ppszPackageNames);
        }
        TDNF_SAFE_FREE_MEMORY(pQuery);
    }
}

uint32_t
SolvApplySinglePackageFilter(
    PSolvQuery pQuery,
    const char* pszPackageName
    )
{
    uint32_t dwError = 0;
    char** ppCopyOfpkgNames = NULL;
    if(!pQuery || IsNullOrEmptyString(pszPackageName))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  2,
                  sizeof(char*),
                  (void**)&ppCopyOfpkgNames);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateString(
                  pszPackageName,
                  &ppCopyOfpkgNames[0]);
    BAIL_ON_TDNF_ERROR(dwError);

    if(pQuery->ppszPackageNames)
    {
        TDNFFreeStringArray(pQuery->ppszPackageNames);
    }

    pQuery->ppszPackageNames = ppCopyOfpkgNames;

cleanup:
    return dwError;

error:
    if(ppCopyOfpkgNames)
    {
        TDNFFreeStringArray(ppCopyOfpkgNames);
    }
    goto cleanup;
}

uint32_t
SolvAddSystemRepoFilter(
    PSolvQuery  pQuery
    )
{
    uint32_t dwError = 0;
    Pool *pool = NULL;

    if(!pQuery || !pQuery->pSack)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    pool = pQuery->pSack->pPool;
    queue_push2(&pQuery->queueRepoFilter,
                SOLVER_SOLVABLE_REPO | SOLVER_SETREPO,
                pool->installed->repoid);

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvAddAvailableRepoFilter(
    PSolvQuery pQuery
    )
{
    uint32_t dwError = 0;
    Repo *pRepo = NULL;
    const Pool *pool = NULL;
    int i = 0;

    if(!pQuery || !pQuery->pSack)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    pool = pQuery->pSack->pPool;
    FOR_REPOS(i, pRepo)
    {
        if (strcasecmp(SYSTEM_REPO_NAME, pRepo->name))
        {
            queue_push2(
                &pQuery->queueRepoFilter,
                SOLVER_SOLVABLE_REPO | SOLVER_SETREPO | SOLVER_SETVENDOR,
                pRepo->repoid);
        }
    }

cleanup:
    return dwError;

error:
    goto cleanup;
}

uint32_t
SolvGenerateCommonJob(
    PSolvQuery pQuery,
    uint32_t dwSelectFlags
    )
{
    uint32_t dwError = 0;
    char** ppszPkgNames = NULL;
    Pool *pPool = NULL;
    Queue queueJob = {0};
    uint32_t nFlags = 0;
    uint32_t nRetFlags = 0;

    if(!pQuery || !pQuery->pSack)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    ppszPkgNames = pQuery->ppszPackageNames;
    queue_init(&queueJob);
    pPool = pQuery->pSack->pPool;
    if(ppszPkgNames)
    {
        while(*ppszPkgNames)
        {
            nFlags  = dwSelectFlags;
            nRetFlags = 0;

            queue_empty(&queueJob);
            if (!pPool || !pPool->solvables || !pPool->whatprovides)
            {
                dwError = ERROR_TDNF_INVALID_PARAMETER;
                BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
            }

            nRetFlags = selection_make(
                         pPool,
                         &queueJob,
                         *ppszPkgNames,
                         nFlags);

            if (pQuery->queueRepoFilter.count)
            {
                selection_filter(pPool, &queueJob, &pQuery->queueRepoFilter);
            }
            if (!queueJob.count)
            {
                nFlags |= SELECTION_NOCASE;
                nRetFlags = selection_make(
                                pPool,
                                &queueJob,
                                *ppszPkgNames,
                                nFlags);
                if (pQuery->queueRepoFilter.count)
                {
                    selection_filter(
                        pPool,
                        &queueJob,
                        &pQuery->queueRepoFilter);
                }
                if (queueJob.count)
                {
                    pr_info("[ignoring case for '%s']\n", *ppszPkgNames);
                }
            }
            if (queueJob.count)
            {
                if (nRetFlags & SELECTION_FILELIST)
                {
                    pr_info("[using file list match for '%s']\n",
                           *ppszPkgNames);
                }
                if (nRetFlags & SELECTION_PROVIDES)
                {
                    pr_info("[using capability match for '%s']\n",
                           *ppszPkgNames);
                }
                queue_insertn(&pQuery->queueJob,
                              pQuery->queueJob.count,
                              queueJob.count,
                              queueJob.elements);
            }
            ppszPkgNames++;
        }
    }
    else if(pQuery->queueRepoFilter.count)
    {
        queue_empty(&queueJob);
        queue_push2(&queueJob, SOLVER_SOLVABLE_ALL, 0);
        selection_filter(pPool, &queueJob, &pQuery->queueRepoFilter);
        queue_insertn(&pQuery->queueJob,
                      pQuery->queueJob.count,
                      queueJob.count,
                      queueJob.elements);
    }

cleanup:
    queue_free(&queueJob);
    return dwError;

error:
    goto cleanup;
}

static inline int
is_pseudo_package(Pool *pool, Solvable *s)
{
    const char *n = pool_id2str(pool, s->name);
    if (*n == 'p' && !strncmp(n, "patch:", 6))
    {
        return 1;
    }
    return 0;
}

uint32_t
SolvApplyListQuery(
    PSolvQuery pQuery
    )
{
    uint32_t dwError = 0;
    int nIndex = 0;
    Queue queueTmp = {0};
    uint32_t nFlags = 0;

    if(!pQuery)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    queue_init(&queueTmp);
    nFlags = SELECTION_NAME |     /* foo */
             SELECTION_PROVIDES |
             SELECTION_GLOB |     /* foo* */
             SELECTION_CANON |    /* foo-1.2-3.ph4.noarch */
             SELECTION_DOTARCH |  /* foo.noarch */
             SELECTION_REL;       /* foo>=1.2-3 */

    if (pQuery->nScope == SCOPE_SOURCE) {
        nFlags |= SELECTION_SOURCE_ONLY;
    }

    dwError = SolvGenerateCommonJob(pQuery, nFlags);
    BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);

    if(pQuery->queueJob.count > 0)
    {
        for (nIndex = 0; nIndex < pQuery->queueJob.count ; nIndex += 2)
        {
            Pool *pool;
            Id p = 0, pp = 0, how = 0, what = 0;

            queue_empty(&queueTmp);
            what = pQuery->queueJob.elements[nIndex + 1];
            how = SOLVER_SELECTMASK & pQuery->queueJob.elements[nIndex];
            pool = pQuery->pSack->pPool;
            if (how == SOLVER_SOLVABLE_ALL)
            {
                FOR_POOL_SOLVABLES(p)
                {
                    if (pool->considered && !MAPTST(pool->considered, p))
                        continue;
                    if(is_pseudo_package(pool, &pool->solvables[p]))
                        continue;
                    queue_push(&queueTmp, p);
                }
            }
            else if (how == SOLVER_SOLVABLE_REPO)
            {
                Repo *repo = pool_id2repo(pool, what);
                if (repo)
                {
                    Solvable *s = NULL;

                    FOR_REPO_SOLVABLES(repo, p, s)
                    {
                        if (pool->considered && !MAPTST(pool->considered, p))
                            continue;
                        if (is_pseudo_package(pool, &pool->solvables[p]))
                            continue;
                        queue_push(&queueTmp, p);
                    }
                }
            }
            else
            {
                FOR_JOB_SELECT(p, pp, how, what)
                {
                    if (pool->considered && !MAPTST(pool->considered, p))
                        continue;
                    if (is_pseudo_package(pool, &pool->solvables[p]))
                        continue;
                    queue_push(&queueTmp, p);
                }
            }
            queue_insertn(&pQuery->queueResult,
                          pQuery->queueResult.count,
                          queueTmp.count,
                          queueTmp.elements);
        }
    }
    else if(!pQuery->ppszPackageNames ||
            IsNullOrEmptyString(pQuery->ppszPackageNames[0]))
    {
        Id p = 0;
        Pool *pool = pQuery->pSack->pPool;
        FOR_POOL_SOLVABLES(p)
        {
            if (pool->considered && !MAPTST(pool->considered, p))
                continue;
            if(is_pseudo_package(pool, &pool->solvables[p]))
                continue;
            queue_push(&pQuery->queueResult, p);
        }
    }

cleanup:
    queue_free(&queueTmp);
    return dwError;

error:
    goto cleanup;
}
