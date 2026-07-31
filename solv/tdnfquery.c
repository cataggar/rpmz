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
SolvAddUserInstalledToJobs(
    PTDNF_ID_LIST pQueueJobs,
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
            dwError = TDNFIdListPush2(pQueueJobs, SOLVER_SOLVABLE|SOLVER_USERINSTALLED, p);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

cleanup:
    return dwError;
error:
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
