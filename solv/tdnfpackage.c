/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

/*
 * Bounds-checked pool_id2solvable().
 *
 * libsolv's pool_id2solvable() is `pool->solvables + p` -- plain pointer
 * arithmetic that never returns NULL and never validates p. Every caller
 * below already guards on a NULL result, but against that inline those
 * guards were dead code: an out-of-range handle read past the end of the
 * solvables array instead of being refused. Returning NULL for a handle
 * the pool cannot address makes each of those existing guards live, so
 * each call site keeps reporting its own error code.
 *
 * The bound is [0, nsolvables), which is exactly the allocated extent of
 * the solvables array -- pool_create() allocates the block and sets
 * nsolvables together, and every grow and truncate keeps them in step.
 *
 * Handle 0 is deliberately admitted. It is libsolv's reserved "no
 * solvable" slot: allocated, zeroed, and therefore safe to read. This
 * helper is a memory-safety bound and nothing more, so what each caller
 * makes of handle 0 is unchanged. Do not read that as "every caller
 * rejects it" -- only the four that test pSolv->repo, or look up a
 * repo-backed field, do. The rest still succeed on it and report the
 * zero solvable's empty fields, exactly as they did before: pool_id2str()
 * renders its name as the literal "<NULL>" (knownid.h ID_NULL), which is
 * a non-empty string and passes an IsNullOrEmptyString() guard. Anyone
 * adding a tenth accessor needs its own guard; this one will not supply
 * it.
 */
static
Solvable *
PkgHandleToSolvable(
    const Pool *pPool,
    TDNF_PKG_ID dwPkgId
    )
{
    if(!pPool || dwPkgId < 0 || dwPkgId >= pPool->nsolvables)
    {
        return NULL;
    }
    return pool_id2solvable(pPool, dwPkgId);
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

    pSolv = PkgHandleToSolvable(pSack->pPool, dwPkgId);
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

    pSolv = PkgHandleToSolvable(pSack->pPool, dwPkgId);
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
_Static_assert(((Id)-1 < 0) == ((TDNF_PKG_ID)-1 < 0),
               "package handle signedness diverged from libsolv");
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
 * They live here rather than in their caller because they dereference
 * Solvable, and client/ is not allowed to include a libsolv header --
 * scripts/libsolv-include-audit.py enforces that. Being in solv/ and
 * TDNF*-prefixed, they are exported and so recorded in
 * scripts/abi-baseline.json as a deliberate act rather than a side
 * effect; that is what the ABI audit exists to force. Note this holds
 * because they are TDNF*-prefixed: the audit's baseline tracks the
 * public API, so internal Solv*-prefixed helpers below (which libtdnf
 * also exports, for want of a version script) are outside it and are
 * not recorded.
 *
 * client/querynative.c is now their only caller. It used to be both
 * querynative.c and goal.c; goal.c stopped needing a handle accessor
 * when the command-line .rpm path was recorded at creation instead of
 * being re-derived from the pool.
 *
 * Field strings returned by TDNFPkgHandleGetFields are borrowed from
 * the sack and stay valid for as long as it does; callers must not
 * free them. The NEVRA is different and is documented at
 * TDNFPkgHandleGetRepoNevra.
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

    pSolv = PkgHandleToSolvable(pPool, dwPkgId);
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

    pSolv = PkgHandleToSolvable(pPool, dwPkgId);
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

