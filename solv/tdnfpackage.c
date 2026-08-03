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


/*
 * The pool's repos carry a PTDNF_REPO_DATA in Repo.appdata, set when the
 * repo was created. Walking them is a libsolv iteration, so it lives
 * here; deciding which of them are interesting is policy and stays with
 * the caller. The returned array borrows the appdata pointers -- it owns
 * only the array itself.
 */
uint32_t
SolvGetRepoDataList(
    PSolvSack pSack,
    PTDNF_REPO_DATA **pppRepoData,
    uint32_t *pdwCount
    )
{
    uint32_t dwError = 0;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;
    int nRepoIndex = 0;
    Repo *pRepo = NULL;
    Pool *pool = NULL;
    PTDNF_REPO_DATA *ppRepoData = NULL;

    if(!pSack || !pSack->pPool || !pppRepoData || !pdwCount)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pool = pSack->pPool;
    FOR_REPOS(nRepoIndex, pRepo)
    {
        if(pRepo->appdata)
        {
            dwCount++;
        }
    }

    if(!dwCount)
    {
        goto cleanup;
    }

    dwError = TDNFAllocateMemory(
                  dwCount,
                  sizeof(PTDNF_REPO_DATA),
                  (void **)&ppRepoData);
    BAIL_ON_TDNF_ERROR(dwError);

    FOR_REPOS(nRepoIndex, pRepo)
    {
        if(pRepo->appdata)
        {
            ppRepoData[dwIndex++] = (PTDNF_REPO_DATA)pRepo->appdata;
        }
    }

cleanup:
    if(pppRepoData)
    {
        *pppRepoData = ppRepoData;
    }
    if(pdwCount)
    {
        *pdwCount = dwIndex;
    }
    return dwError;

error:
    TDNF_SAFE_FREE_MEMORY(ppRepoData);
    ppRepoData = NULL;
    dwIndex = 0;
    goto cleanup;
}

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
 * effect -- that is what the ABI audit exists to force. Note this holds
 * because they are TDNF*-prefixed: the audit's baseline tracks the
 * public API, so internal Solv*-prefixed helpers below (which libtdnf
 * also exports, for want of a version script) are outside it and are
 * not recorded.
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

