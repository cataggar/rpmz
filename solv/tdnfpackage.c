/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

void
SolvFreePackageList(
    PSolvPackageList pPkgList
    )
{
    if(pPkgList)
    {
        queue_free(&pPkgList->queuePackages);
        TDNF_SAFE_FREE_MEMORY(pPkgList);
    }
}

uint32_t
SolvQueueToPackageList(
    Queue* pQueue,
    PSolvPackageList* ppPkgList
    )
{
    uint32_t dwError = 0;
    PSolvPackageList pPkgList = NULL;
    if(!ppPkgList || !pQueue)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pQueue->count == 0)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(SolvPackageList),
                  (void **)&pPkgList);
    BAIL_ON_TDNF_ERROR(dwError);

    queue_init(&pPkgList->queuePackages);
    queue_insertn(&pPkgList->queuePackages,
                  pPkgList->queuePackages.count,
                  pQueue->count,
                  pQueue->elements);
    *ppPkgList = pPkgList;
cleanup:
    return dwError;

error:
    if(ppPkgList)
    {
        *ppPkgList = NULL;
    }
    if(pPkgList)
    {
        SolvFreePackageList(pPkgList);
    }
    goto cleanup;
}

uint32_t
SolvGetQueryResult(
    PSolvQuery pQuery,
    PSolvPackageList* ppPkgList
    )
{
    uint32_t dwError = 0;
    PSolvPackageList pPkgList = NULL;
    if(!ppPkgList || !pQuery)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(pQuery->queueResult.count == 0)
    {
        dwError = ERROR_TDNF_NO_MATCH;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvQueueToPackageList(&pQuery->queueResult, &pPkgList);
    BAIL_ON_TDNF_ERROR(dwError);
    *ppPkgList = pPkgList;

cleanup:
    return dwError;

error:
    if(pPkgList)
    {
        SolvFreePackageList(pPkgList);
    }
    if(ppPkgList)
    {
        *ppPkgList = NULL;
    }
    goto cleanup;
}

uint32_t
SolvGetPkgNameFromId(
    PSolvSack pSack,
    uint32_t dwPkgId,
    char** ppszName)
{
    uint32_t dwError = 0;
    const char* pszTemp = NULL;
    char* pszName = NULL;
    Solvable *pSolv = NULL;

    if(!pSack || !ppszName)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pSack->pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszTemp = pool_id2str(pSack->pPool, pSolv->name);
    if(!pszTemp)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszTemp, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszName = pszName;
cleanup:
    return dwError;

error:
    if(ppszName)
    {
        *ppszName = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszName);
    goto cleanup;
}

uint32_t
SolvFindAvailablePkgByName(
    PSolvSack pSack,
    const char* pszName,
    PSolvPackageList* ppPkgList
    )
{
    uint32_t dwError = 0;
    PSolvQuery pQuery = NULL;
    PSolvPackageList pPkgList = NULL;

    if(!pSack || IsNullOrEmptyString(pszName) || !ppPkgList)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = SolvCreateQuery(pSack, &pQuery);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvAddAvailableRepoFilter(pQuery);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvApplySinglePackageFilter(pQuery, pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvApplyListQuery(pQuery);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvGetQueryResult(pQuery, &pPkgList);
    BAIL_ON_TDNF_ERROR(dwError);
    *ppPkgList = pPkgList;

cleanup:
    if(pQuery)
    {
        SolvFreeQuery(pQuery);
    }
    return dwError;

error:
    if(ppPkgList)
    {
        *ppPkgList = NULL;
    }
    goto cleanup;;
}

uint32_t
SolvSplitEvr(
    const PSolvSack pSack,
    const char *pszEVRstring,
    char **ppszEpoch,
    char **ppszVersion,
    char **ppszRelease)
{

    uint32_t dwError = 0;
    char *pszEvr = NULL;
    int eIndex = 0;
    int rIndex = 0;
    char *pszTempEpoch = NULL;
    char *pszTempVersion = NULL;
    char *pszTempRelease = NULL;
    char *pszEpoch = NULL;
    char *pszVersion = NULL;
    char *pszRelease = NULL;
    char *pszIt = NULL;

    if(!pSack || IsNullOrEmptyString(pszEVRstring)
       || !ppszEpoch || !ppszVersion || !ppszRelease)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszEVRstring, &pszEvr);
    BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);

    // EVR string format: epoch : version-release
    pszIt = pszEvr;
    for( ; *pszIt != '\0'; pszIt++)
    {
        if(*pszIt == ':')
        {
            eIndex = pszIt - pszEvr;
        }
        else if(*pszIt == '-')
        {
            rIndex = pszIt - pszEvr;
        }
    }

    pszTempVersion = pszEvr;
    pszTempEpoch = NULL;
    pszTempRelease = NULL;
    if(eIndex != 0)
    {
        pszTempEpoch = pszEvr;
        *(pszEvr + eIndex) = '\0';
        pszTempVersion = pszEvr + eIndex + 1;
    }

    if(rIndex != 0 && rIndex > eIndex)
    {
        pszTempRelease = pszEvr + rIndex + 1;
        *(pszEvr + rIndex) = '\0';
    }

    if(!IsNullOrEmptyString(pszTempEpoch))
    {
        dwError = TDNFAllocateString(pszTempEpoch, &pszEpoch);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if(!IsNullOrEmptyString(pszTempVersion))
    {
        dwError = TDNFAllocateString(pszTempVersion, &pszVersion);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if(!IsNullOrEmptyString(pszTempRelease))
    {
        dwError = TDNFAllocateString(pszTempRelease, &pszRelease);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    *ppszEpoch = pszEpoch;
    *ppszVersion = pszVersion;
    *ppszRelease = pszRelease;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszEvr);
    return dwError;

error:
    if(ppszEpoch)
    {
        *ppszEpoch = NULL;
    }
    if(ppszVersion)
    {
        *ppszVersion = NULL;
    }
    if(ppszRelease)
    {
        *ppszRelease = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszEpoch);
    TDNF_SAFE_FREE_MEMORY(pszVersion);
    TDNF_SAFE_FREE_MEMORY(pszRelease);
    goto cleanup;
}

/**
 * Description: This function should check problem type and
 *              skipProblemType if both matches then return true
 *              else return false
 * Arguments:
 *        SolverRuleinfo : Solver problem type
 *        TDNF_SKIPPROBLEM_TYPE: user specified problem type
 * Return:
 *      true : if solver problem type and user specified problem matches
 *      false : if not matches
 */
static bool
SkipBasedOnType(
    Solver* pSolv,
    SolverRuleinfo type,
    Id dwSource,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
    )
{
    bool result = false;

    if (dwSkipProblem & SKIPPROBLEM_CONFLICTS)
    {
        result = result || type == SOLVER_RULE_PKG_CONFLICTS ||
                 type == SOLVER_RULE_PKG_SELF_CONFLICT;
    }

    if (dwSkipProblem & SKIPPROBLEM_OBSOLETES)
    {
        result = result || type == SOLVER_RULE_PKG_OBSOLETES ||
                 type == SOLVER_RULE_PKG_IMPLICIT_OBSOLETES ||
                 type == SOLVER_RULE_PKG_INSTALLED_OBSOLETES;
    }

    if (dwSkipProblem & SKIPPROBLEM_BROKEN)
    {
        /* see https://github.com/openSUSE/libsolv/blob/master/src/rules.h */
        result = result || type & SOLVER_RULE_PKG;
    }

    if (dwSkipProblem & SKIPPROBLEM_DISABLED)
    {
        /**
         * If a package was marked not installable and it was disabled,
         * then we can skip this error as the package was excluded
         * conciously.
         */
        if (type == SOLVER_RULE_PKG_NOT_INSTALLABLE)
        {
            Solvable *s = pSolv->pool->solvables + dwSource;
            if (pool_disabled_solvable(pSolv->pool, s)) {
                result = true;
            }
        }
    }

    return result;
}

static uint32_t
check_for_providers(
    PSolvSack pSack,
    SolverRuleinfo type,
    const char *pszProblem,
    char *prv_pkgname
    )
{
    const char *beg;
    const char *end = NULL;
    uint32_t dwError = 0;
    char pkgname[256] = {0};
    PSolvPackageList pAvailablePkgList = NULL;

    if (!pSack || !prv_pkgname || !pszProblem)
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }

    if (type != SOLVER_RULE_PKG_REQUIRES)
    {
        return dwError;
    }

    beg = strstr(pszProblem, " requires ");
    if (beg)
    {
        beg += strlen(" requires ");
        end = strchr(beg, ',');
    }

    if (!beg || !end)
    {
        pr_err("Error while trying to resolve\n");
        return ERROR_TDNF_SOLV_FAILED;
    }

    for (int32_t i = 0; end > beg; beg++)
    {
        if (*beg != ' ')
        {
            pkgname[i++] = *beg;
        }
    }

    if (!strcmp(pkgname, prv_pkgname))
    {
        return dwError;
    }

    dwError = SolvFindAvailablePkgByName(pSack, pkgname, &pAvailablePkgList);
    if (pAvailablePkgList)
    {
        SolvFreePackageList(pAvailablePkgList);
    }
    strcpy(prv_pkgname, pkgname);

    return dwError;
}

uint32_t
SolvReportProblems(
    PSolvSack pSack,
    Solver* pSolv,
    TDNF_SKIPPROBLEM_TYPE dwSkipProblem
    )
{
    int nCount = 0;
    Id dwDep = 0;
    Id dwSource = 0;
    Id dwTarget = 0;
    SolverRuleinfo type;
    uint32_t dwError = 0;
    uint32_t total_prblms = 0;
    char prv_pkgname[256] = {0};

    if (!pSolv)
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }

    nCount = solver_problem_count(pSolv);
    for ( ; nCount > 0; nCount--)
    {
        const char *pszProblem = NULL;

        Id dwProblemId = solver_findproblemrule(pSolv, nCount);

        type = solver_ruleinfo(pSolv, dwProblemId,
                               &dwSource, &dwTarget, &dwDep);

       if (SkipBasedOnType(pSolv, type, dwSource, dwSkipProblem))
       {
           continue;
       }

        pszProblem = solver_problemruleinfo2str(pSolv, type, dwSource,
                                                dwTarget, dwDep);

        if (dwSkipProblem != SKIPPROBLEM_NONE &&
            type == SOLVER_RULE_PKG_REQUIRES)
        {
            if (!check_for_providers(pSack, type, pszProblem, prv_pkgname))
            {
                continue;
            }
        }

        dwError = ERROR_TDNF_SOLV_FAILED;
        pr_err("%u. %s\n", ++total_prblms, pszProblem);
    }

    if (dwError)
    {
        pr_err("Found %u problem(s) while resolving\n", total_prblms);
    }

    return dwError;
}

uint32_t
SolvAddExcludes(
    Pool* pPool,
    char** ppszExcludes
    )
{
     uint32_t dwError = 0;
     Map *pExcludes = NULL;

     if (!pPool || !ppszExcludes)
     {
         dwError = ERROR_TDNF_INVALID_PARAMETER;
         BAIL_ON_TDNF_ERROR(dwError);
     }

     dwError = TDNFAllocateMemory(
                           1,
                           sizeof(Map),
                           (void**)&pExcludes);
     BAIL_ON_TDNF_ERROR(dwError);

     map_init(pExcludes, pPool->nsolvables);

     dwError = SolvDataIterator(pPool, ppszExcludes, pExcludes);
     BAIL_ON_TDNF_ERROR(dwError);

     if (!pPool->considered)
     {
         dwError = TDNFAllocateMemory(
                              1,
                              sizeof(Map),
                              (void**)&pPool->considered);
         map_init(pPool->considered, pPool->nsolvables);
         map_setall(pPool->considered);
     }
     map_subtract(pPool->considered, pExcludes);

cleanup:
    TDNFFreeMemory(pExcludes);
    return dwError;
error:
    goto cleanup;
}

uint32_t
SolvDataIterator(
     Pool* pPool,
     char** ppszExcludes,
     Map* pMap
     )
{
    Dataiterator di;
    Id keyname = SOLVABLE_NAME;
    char **ppszPkg = NULL;
    uint32_t dwError = 0;

    if (!pPool || !ppszExcludes || !pMap)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    for (ppszPkg = ppszExcludes; ppszPkg && *ppszPkg; ppszPkg++)
    {
          int flags = SEARCH_STRING;
          if (SolvIsGlob(*ppszPkg))
          {
              flags = SEARCH_GLOB;
          }
          dwError = dataiterator_init(&di, pPool, 0, 0, keyname, *ppszPkg, flags);
          BAIL_ON_TDNF_ERROR(dwError);
          while (dataiterator_step(&di))
          {
              MAPSET(pMap, di.solvid);
          }
          dataiterator_free(&di);
    }
cleanup:
    return dwError;
error:
    goto cleanup;
}

int
SolvIsGlob(
    const char* pszString
    )
{
    int nResult = 0;
    while(*pszString)
    {
        char ch = *pszString;

        if(ch == '*' || ch == '?' || ch == '[')
        {
            nResult = 1;
            break;
        }

        pszString++;
    }
    return nResult;
}

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
    )
{
    uint32_t dwError = 0;
    const char* pszTmp = NULL;
    Solvable *pSolv = NULL;
    uint32_t dwEpoch = 0;
    char *pszName = NULL;
    char *pszEpoch = NULL;
    char *pszVersion = NULL;
    char *pszRelease = NULL;
    char *pszArch = NULL;
    char *pszEVR = NULL;

    if(!pSack ||
       !ppszName ||
       !ppszVersion ||
       !ppszRelease ||
       !ppszArch ||
       !pdwEpoch)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_LIBSOLV_ERROR(dwError);
    }

    pSolv = pool_id2solvable(pSack->pPool, dwPkgId);
    if(!pSolv)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pszTmp = solvable_lookup_str(pSolv, SOLVABLE_NAME);
    if(!pszTmp)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszTmp, &pszName);
    BAIL_ON_TDNF_ERROR(dwError);

    pszTmp = solvable_lookup_str(pSolv, SOLVABLE_ARCH);
    if(!pszTmp)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszTmp, &pszArch);
    BAIL_ON_TDNF_ERROR(dwError);

    pszTmp = solvable_lookup_str(pSolv, SOLVABLE_EVR);
    if(!pszTmp)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszTmp, &pszEVR);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = SolvSplitEvr(pSack,
                           pszTmp,
                           &pszEpoch,
                           &pszVersion,
                           &pszRelease);
    BAIL_ON_TDNF_ERROR(dwError);

    if(!IsNullOrEmptyString(pszEpoch))
    {
        dwEpoch = strtol(pszEpoch, NULL, 10);
    }

    *pdwEpoch = dwEpoch;
    *ppszName = pszName;
    *ppszVersion = pszVersion;
    *ppszRelease = pszRelease;
    *ppszArch = pszArch;
    if (ppszEVR)
    {
        *ppszEVR = pszEVR;
    }
    else
    {
        TDNF_SAFE_FREE_MEMORY(pszEVR);
    }
cleanup:
    TDNF_SAFE_FREE_MEMORY(pszEpoch);
    return dwError;

error:
    if(pdwEpoch)
    {
        *pdwEpoch = 0;
    }
    if(ppszName)
    {
        *ppszName = NULL;
    }
    if(ppszVersion)
    {
        *ppszVersion = NULL;
    }
    if(ppszRelease)
    {
        *ppszRelease = NULL;
    }
    if(ppszArch)
    {
        *ppszArch = NULL;
    }
    if(ppszEVR)
    {
        *ppszEVR = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszName);
    TDNF_SAFE_FREE_MEMORY(pszVersion);
    TDNF_SAFE_FREE_MEMORY(pszRelease);
    TDNF_SAFE_FREE_MEMORY(pszArch);
    TDNF_SAFE_FREE_MEMORY(pszEVR);
    goto cleanup;
}
