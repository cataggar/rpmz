/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"



static uint32_t
TDNFEnsureRepoMDParts(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    PTDNF_REPO_METADATA pRepoMDRel,
    PTDNF_REPO_METADATA *ppRepoMD
    );
static uint32_t
TDNFFindRepoMDPart(
    const TDNF_REPOMD_DOC *pRepoMd,
    const char *pszType,
    char **ppszPart
    );
static uint32_t
TDNFParseRepoMD(
    PTDNF_REPO_METADATA pRepoMD
    );
static uint32_t
TDNFReplaceFile(
    const char *pszSrcFile,
    const char *pszDstFile
    );
static uint32_t
TDNFDownloadRepoMDParts(
    PTDNF pTdnf,
    const TDNF_REPOMD_DOC *pRepoMd,
    PTDNF_REPO_DATA pRepo,
    const char *pszDir,
    int nPrintOnly
    );
uint32_t
TDNFGetGPGKeys(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    char*** pppszUrlGPGKeys
    )
{
    uint32_t dwError = 0;
    char** ppszUrlGPGKeys = NULL;

    if(!pTdnf || !pRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (pppszUrlGPGKeys != NULL)
    {
        if (pRepo->ppszUrlGPGKeys == NULL ||
            IsNullOrEmptyString(pRepo->ppszUrlGPGKeys[0]))
        {
            dwError = ERROR_TDNF_NO_GPGKEY_CONF_ENTRY;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        dwError = TDNFAllocateStringArray(
            pRepo->ppszUrlGPGKeys,
            &ppszUrlGPGKeys);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if (pppszUrlGPGKeys)
    {
        *pppszUrlGPGKeys = ppszUrlGPGKeys;
    }

cleanup:
    return dwError;

error:
    if(pppszUrlGPGKeys)
    {
        *pppszUrlGPGKeys = NULL;
    }
    TDNF_SAFE_FREE_STRINGARRAY(ppszUrlGPGKeys);
    goto cleanup;
}


static uint32_t
TDNFEventRepoMDDownloadStart(
    PTDNF pTdnf,
    const char *pcszRepoId,
    const char *pcszRepoDataDir
    )
{
    if (!pTdnf ||
        IsNullOrEmptyString(pcszRepoId))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }

    return BuiltinPluginsRepoMDDownloadStart(
               pTdnf,
               pcszRepoId,
               pcszRepoDataDir);
}

static uint32_t
TDNFEventRepoMDDownloadEnd(
    PTDNF pTdnf,
    const char *pcszRepoId,
    const char *pcszRepoMDFile
    )
{
    if (!pTdnf ||
        IsNullOrEmptyString(pcszRepoId) ||
        IsNullOrEmptyString(pcszRepoMDFile))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }

    return BuiltinPluginsRepoMDDownloadEnd(
               pTdnf,
               pcszRepoId,
               pcszRepoMDFile);
}

uint32_t
TDNFGetRepoMD(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepoData,
    const char *pszRepoDataDir,
    PTDNF_REPO_METADATA *ppRepoMD
    )
{
    uint32_t dwError = 0;
    char *pszRepoMDFile = NULL;
    char *pszRepoMDUrl = NULL;
    char *pszTmpRepoDataDir = NULL;
    char *pszTmpRepoMDFile = NULL;
    char *pszMirrorFile = NULL;
    char *pszSnapshotFile = NULL;
    char *pszTempBaseUrlFile = NULL;
    char* pszLastRefreshMarker = NULL;
    PTDNF_REPO_METADATA pRepoMDRel = NULL;
    PTDNF_REPO_METADATA pRepoMD = NULL;
    unsigned char pszMDCookie[SOLV_COOKIE_LEN] = {0};
    unsigned char pszTmpCookie[SOLV_COOKIE_LEN] = {0};
    int nNeedDownload = 0;
    int nNewRepoMDFile = 0;
    int nReplaceRepoMD = 0;
    int nKeepCache = 0;
    char *pszError = NULL;

    if (!pTdnf ||
        !pRepoData ||
        IsNullOrEmptyString(pszRepoDataDir) ||
        !ppRepoMD)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    /* plugin event indicating a repomd download is about to start */
    dwError = TDNFEventRepoMDDownloadStart(
                  pTdnf,
                  pRepoData->pszId,
                  pszRepoDataDir);
    BAIL_ON_TDNF_ERROR(dwError);

    if (pRepoData->pszMirrorList) {
        time_t now = time(NULL);
        int needDownload = 0;
        struct stat st = {0};
        int i, j;

        dwError = TDNFGetCachePath(pTdnf, pRepoData,
                                   TDNF_REPO_METADATA_MIRRORLIST, NULL,
                                   &pszMirrorFile);
        BAIL_ON_TDNF_ERROR(dwError);

        if (stat(pszMirrorFile, &st) < 0) {
            if (errno == ENOENT)
                needDownload = 1;
            else {
                dwError = errno;
                BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
            }
        } else if ((now - st.st_ctime) > pRepoData->lMetadataExpire)
            needDownload = 1;

        if (needDownload) {
            dwError = TDNFDownloadFile(pTdnf, pRepoData, pRepoData->pszMirrorList, pszMirrorFile, pRepoData->pszId);
            BAIL_ON_TDNF_ERROR(dwError);
        }

        dwError = TDNFReadFileToStringArray(pszMirrorFile, &pRepoData->ppszBaseUrls);
        BAIL_ON_TDNF_ERROR(dwError);

        /* remove comments from mirror file */
        for(i = 0, j = 0; pRepoData->ppszBaseUrls[i]; i++) {
            if (pRepoData->ppszBaseUrls[i][0] == '#')
                continue;
            if (i != j) {
                pRepoData->ppszBaseUrls[j++] = pRepoData->ppszBaseUrls[i];
            } else
                j++;
        }
        for (; pRepoData->ppszBaseUrls[j] != NULL; j++)
            pRepoData->ppszBaseUrls[j] = NULL;
    }

    if (!pRepoData->ppszBaseUrls || IsNullOrEmptyString(pRepoData->ppszBaseUrls[0]))
    {
        pr_err("Error: Cannot find a valid base URL for repo: %s\n", pRepoData->pszName);
        dwError = ERROR_TDNF_BASEURL_DOES_NOT_EXISTS;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    nKeepCache = pTdnf->pConf->nKeepCache;

    dwError = TDNFJoinPath(&pszRepoMDFile,
                           pszRepoDataDir,
                           TDNF_REPO_METADATA_FILE_NAME,
                           NULL);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(TDNF_REPO_METADATA),
                  (void **)&pRepoMDRel);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFGetCachePath(pTdnf, pRepoData,
                               NULL, NULL,
                               &pRepoMDRel->pszRepoCacheDir);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateString(pszRepoMDFile, &pRepoMDRel->pszRepoMD);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFAllocateString(pRepoData->pszId, &pRepoMDRel->pszRepo);
    BAIL_ON_TDNF_ERROR(dwError);

    /* if repomd.xml file is not present, set flag to download */
    if (access(pszRepoMDFile, F_OK))
    {
        if (errno != ENOENT)
        {
            dwError = errno;
            BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
        }
        nNeedDownload = 1;
    }

    /* if refresh flag is set, get shasum of existing repomd file */
    if (pTdnf->pArgs->nRefresh)
    {
        if (!access(pszRepoMDFile, F_OK))
        {
            dwError = TDNFRepoMdCalculateCookieForFile(
                          pszRepoMDFile,
                          pszMDCookie);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        nNeedDownload = 1;
    }

    /* download repomd.xml to tmp */
    if (nNeedDownload && !pTdnf->pArgs->nCacheOnly)
    {
        pr_notice("Refreshing metadata for: '%s'\n", pRepoData->pszName);
        /* always download to tmp */
        dwError = TDNFGetCachePath(pTdnf, pRepoData,
                                   "tmp", NULL,
                                   &pszTmpRepoDataDir);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFUtilsMakeDirs(pszTmpRepoDataDir);
        if (dwError == ERROR_TDNF_ALREADY_EXISTS)
        {
            dwError = 0;
        }
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFJoinPath(
                      &pszTmpRepoMDFile,
                      pszTmpRepoDataDir,
                      TDNF_REPO_METADATA_FILE_NAME,
                      NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadFileFromRepo(
                          pTdnf,
                          pRepoData,
                          TDNF_REPO_METADATA_FILE_PATH,
                          pszTmpRepoMDFile,
                          pRepoData->pszId);
        BAIL_ON_TDNF_ERROR(dwError);

        nReplaceRepoMD = 1;
        if (pszMDCookie[0])
        {
            dwError = TDNFRepoMdCalculateCookieForFile(
                          pszTmpRepoMDFile,
                          pszTmpCookie);
            BAIL_ON_TDNF_ERROR(dwError);
            if (!memcmp (pszMDCookie, pszTmpCookie, sizeof(pszTmpCookie)))
            {
                nReplaceRepoMD = 0;
            }
        }
        nNewRepoMDFile = 1;

        /* plugin event indicating a repomd download happened */
        dwError = TDNFEventRepoMDDownloadEnd(
                      pTdnf,
                      pRepoData->pszId,
                      pszTmpRepoMDFile);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (nReplaceRepoMD)
    {
        /* Remove the old repodata, solvcache and lastRefreshMarker before
           replacing the new repomd file and metalink files. */
        TDNFRepoRemoveCache(pTdnf, pRepoData);
        TDNFRemoveSolvCache(pTdnf, pRepoData);
        TDNFRemoveLastRefreshMarker(pTdnf, pRepoData);
        if (!nKeepCache)
        {
            TDNFRemoveRpmCache(pTdnf, pRepoData);
        }
        dwError = TDNFUtilsMakeDirs(pszRepoDataDir);
        BAIL_ON_TDNF_ERROR(dwError);
        dwError = TDNFReplaceFile(pszTmpRepoMDFile, pszRepoMDFile);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if (nNewRepoMDFile)
    {
        dwError = TDNFGetCachePath(pTdnf, pRepoData,
                                   TDNF_REPO_METADATA_MARKER, NULL,
                                   &pszLastRefreshMarker);
        BAIL_ON_TDNF_ERROR(dwError);
        dwError = TDNFTouchFile(pszLastRefreshMarker);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFParseRepoMD(pRepoMDRel);
    if (dwError == ERROR_TDNF_FILE_NOT_FOUND && pTdnf->pArgs->nCacheOnly)
    {
        dwError = ERROR_TDNF_CACHE_DISABLED;
    }
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFEnsureRepoMDParts(
                  pTdnf,
                  pRepoData,
                  pRepoMDRel,
                  &pRepoMD);
    BAIL_ON_TDNF_ERROR(dwError);

    if (pRepoData->pszSnapshotUrl) {
        time_t now = time(NULL);
        int needDownload = 0, nIsRemote = 0;
        struct stat st = {0};

        if (pRepoData->pszSnapshotUrl[0] == '/') {
            SET_STRING(pRepoData->pszSnapshotFile, pRepoData->pszSnapshotUrl);
        } else {
            dwError = TDNFUriIsRemote(pRepoData->pszSnapshotUrl, &nIsRemote);
            if (dwError) {
                /* should be a relative path, relative to repo dir */
                dwError = TDNFJoinPath(
                              &pRepoData->pszSnapshotFile,
                              pTdnf->pConf->pszRepoDir,
                              pRepoData->pszSnapshotUrl,
                              NULL);
                BAIL_ON_TDNF_ERROR(dwError);
            } else {
                if (nIsRemote) {
                    /* we need a unique name based on URL locally, so we automatically refresh on config changes
                       "snapshot" % URL => "snapshot-12345678" */
                    dwError = TDNFRepoMdCreateRepoCacheName(
                                  TDNF_REPO_METADATA_SNAPSHOT,
                                  pRepoData->pszSnapshotUrl,
                                  &pszSnapshotFile);
                    BAIL_ON_TDNF_ERROR(dwError);

                    dwError = TDNFGetCachePath(pTdnf, pRepoData,
                                               pszSnapshotFile, NULL,
                                               &pRepoData->pszSnapshotFile);
                    BAIL_ON_TDNF_ERROR(dwError);

                    if (stat(pRepoData->pszSnapshotFile, &st) < 0) {
                        if (errno == ENOENT)
                            needDownload = 1;
                        else {
                            dwError = errno;
                            BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
                        }
                    } else if ((now - st.st_ctime) > pRepoData->lMetadataExpire)
                        needDownload = 1;

                    if (needDownload) {
                        dwError = TDNFDownloadFile(pTdnf, pRepoData, pRepoData->pszSnapshotUrl, pRepoData->pszSnapshotFile, pRepoData->pszId);
                        BAIL_ON_TDNF_ERROR(dwError);
                    }
                } else if (strncmp(pRepoData->pszSnapshotUrl, "file://", 7) == 0) {
                    SET_STRING(pRepoData->pszSnapshotFile, &pRepoData->pszSnapshotUrl[7]);
                } else {
                    /* we should never get here if TDNFUriIsRemote() behaves correctly */
                    dwError = ERROR_TDNF_URL_INVALID;
                    BAIL_ON_TDNF_ERROR(dwError);
                }
            }
        }
    }
    *ppRepoMD = pRepoMD;

cleanup:
    if (!IsNullOrEmptyString(pszTmpRepoDataDir))
    {
        if((TDNFRemoveTmpRepodata(pszTmpRepoDataDir)) &&
           (dwError == ERROR_TDNF_CHECKSUM_VALIDATION_FAILED))
	{
	    pr_crit("Downloaded repomd shasum mismatch, failed to remove %s file. Please remove it manually\n.",
                pszTmpRepoDataDir);
	}
    }
    TDNFFreeRepoMetadata(pRepoMDRel);
    TDNF_SAFE_FREE_MEMORY(pszTmpRepoMDFile);
    TDNF_SAFE_FREE_MEMORY(pszTmpRepoDataDir);
    TDNF_SAFE_FREE_MEMORY(pszRepoMDFile);
    TDNF_SAFE_FREE_MEMORY(pszRepoMDUrl);
    TDNF_SAFE_FREE_MEMORY(pszMirrorFile);
    TDNF_SAFE_FREE_MEMORY(pszTempBaseUrlFile);
    TDNF_SAFE_FREE_MEMORY(pszError);
    TDNF_SAFE_FREE_MEMORY(pszLastRefreshMarker);
    TDNF_SAFE_FREE_MEMORY(pszSnapshotFile);
    return dwError;

error:
    TDNFGetErrorString(dwError, &pszError);
    if (!IsNullOrEmptyString(pszError))
    {
        pr_err("Error(%u) : %s\n", dwError, pszError);
    }
    TDNFFreeRepoMetadata(pRepoMD);
    goto cleanup;
}

static uint32_t
TDNFDownloadRepoMDPart(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszLocation,
    const char *pszDestPath,
    const char *pszPartName
    )
{
    uint32_t dwError = 0;
    char *pszInfo;

    if(!pTdnf || !pRepo ||
       IsNullOrEmptyString(pszLocation) ||
       IsNullOrEmptyString(pszDestPath))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(access(pszDestPath, F_OK))
    {
        if(errno != ENOENT)
        {
            dwError = errno;
            BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
        }

        dwError = TDNFAllocateStringPrintf(&pszInfo, "%s (%s)", pRepo->pszId, pszPartName);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadFileFromRepo(
                      pTdnf,
                      pRepo,
                      pszLocation,
                      pszDestPath,
                      pszInfo);
        BAIL_ON_TDNF_ERROR(dwError);
    }

cleanup:
    return dwError;
error:
    goto cleanup;
}

static uint32_t
TDNFEnsureRepoMDParts(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    PTDNF_REPO_METADATA pRepoMDRel,
    PTDNF_REPO_METADATA *ppRepoMD
    )
{
    uint32_t dwError = 0;
    PTDNF_REPO_METADATA pRepoMD = NULL;

    if(!pTdnf || !pRepoMDRel || !ppRepoMD)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(
                  1,
                  sizeof(TDNF_REPO_METADATA),
                  (void **)&pRepoMD);
    BAIL_ON_TDNF_ERROR(dwError);

    pRepoMD->pszRepoMD = pRepoMDRel->pszRepoMD;
    pRepoMDRel->pszRepoMD = NULL;

    dwError = TDNFAppendPath(
                  pRepoMDRel->pszRepoCacheDir,
                  pRepoMDRel->pszPrimary,
                  &pRepoMD->pszPrimary);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFDownloadRepoMDPart(
                  pTdnf,
                  pRepo,
                  pRepoMDRel->pszPrimary,
                  pRepoMD->pszPrimary,
                  "primary");
    BAIL_ON_TDNF_ERROR(dwError);

    if(!pRepo->nSkipMDFileLists && !IsNullOrEmptyString(pRepoMDRel->pszFileLists))
    {
        dwError = TDNFAppendPath(
                      pRepoMDRel->pszRepoCacheDir,
                      pRepoMDRel->pszFileLists,
                      &pRepoMD->pszFileLists);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadRepoMDPart(
                      pTdnf,
                      pRepo,
                      pRepoMDRel->pszFileLists,
                      pRepoMD->pszFileLists,
                      "file lists");
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(!pRepo->nSkipMDUpdateInfo && !IsNullOrEmptyString(pRepoMDRel->pszUpdateInfo))
    {
        dwError = TDNFAppendPath(
                      pRepoMDRel->pszRepoCacheDir,
                      pRepoMDRel->pszUpdateInfo,
                      &pRepoMD->pszUpdateInfo);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadRepoMDPart(
                      pTdnf,
                      pRepo,
                      pRepoMDRel->pszUpdateInfo,
                      pRepoMD->pszUpdateInfo,
                      "update info");
        BAIL_ON_TDNF_ERROR(dwError);
    }

    if(!pRepo->nSkipMDOther && !IsNullOrEmptyString(pRepoMDRel->pszOther))
    {
        dwError = TDNFAppendPath(
                      pRepoMDRel->pszRepoCacheDir,
                      pRepoMDRel->pszOther,
                      &pRepoMD->pszOther);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadRepoMDPart(
                      pTdnf,
                      pRepo,
                      pRepoMDRel->pszOther,
                      pRepoMD->pszOther,
                      "other");
        BAIL_ON_TDNF_ERROR(dwError);
    }
    *ppRepoMD = pRepoMD;

cleanup:
    return dwError;

error:
    TDNFFreeRepoMetadata(pRepoMD);
    goto cleanup;
}

static uint32_t
TDNFFindRepoMDPart(
    const TDNF_REPOMD_DOC *pRepoMd,
    const char *pszType,
    char **ppszPart
    )
{
    uint32_t dwError = 0;
    char *pszPart = NULL;
    const char *pszPartTemp = NULL;
    const TDNF_REPOMD_RECORD *pRecord = NULL;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;

    if(!pRepoMd ||
       IsNullOrEmptyString(pszType) ||
       !ppszPart)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwCount = TDNFRepoMdGetRecordCount(pRepoMd);
    for(dwIndex = 0; dwIndex < dwCount; ++dwIndex)
    {
        pRecord = TDNFRepoMdGetRecord(pRepoMd, dwIndex);
        if(!pRecord || IsNullOrEmptyString(pRecord->pszLocationHref))
        {
            continue;
        }

        if(!strcmp(pszType, TDNF_REPOMD_TYPE_UPDATEINFO))
        {
            if(pRecord->dwKind == TDNF_REPOMD_RECORD_KIND_UPDATEINFO)
            {
                pszPartTemp = pRecord->pszLocationHref;
                break;
            }
        }
        else if(!IsNullOrEmptyString(pRecord->pszType) &&
                !strcmp(pRecord->pszType, pszType))
        {
            pszPartTemp = pRecord->pszLocationHref;
            break;
        }
    }

    if(!pszPartTemp)
    {
        dwError = ERROR_TDNF_NO_DATA;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateString(pszPartTemp, &pszPart);
    BAIL_ON_TDNF_ERROR(dwError);

    *ppszPart = pszPart;

cleanup:
    return dwError;

error:
    if(ppszPart)
    {
        *ppszPart = NULL;
    }
    TDNF_SAFE_FREE_MEMORY(pszPart);
    goto cleanup;
}

static uint32_t
TDNFParseRepoMDDoc(
    const char *pszRepoMDPath,
    TDNF_REPOMD_DOC **ppRepoMd
    )
{
    static const char szEmptyRepoMD[] =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        "<repomd xmlns=\"http://linux.duke.edu/metadata/repo\"></repomd>";
    uint32_t dwError = 0;
    TDNF_REPOMD_DOC *pRepoMd = NULL;

    if(IsNullOrEmptyString(pszRepoMDPath) || !ppRepoMd)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFRepoMdParseFile(pszRepoMDPath, &pRepoMd);
    if(dwError == ERROR_TDNF_INVALID_REPO_FILE)
    {
        pr_crit("Error(%u) parsing repomd: %s\n",
                dwError,
                TDNFRepoMdLastError());

        dwError = TDNFRepoMdParseBuffer(
                      szEmptyRepoMD,
                      sizeof(szEmptyRepoMD) - 1,
                      &pRepoMd);
    }
    BAIL_ON_TDNF_ERROR(dwError);

    *ppRepoMd = pRepoMd;

cleanup:
    return dwError;

error:
    if(ppRepoMd)
    {
        *ppRepoMd = NULL;
    }
    TDNFRepoMdFree(pRepoMd);
    goto cleanup;
}

static uint32_t
TDNFParseRepoMD(
    PTDNF_REPO_METADATA pRepoMD
    )
{
    uint32_t dwError = 0;
    TDNF_REPOMD_DOC *pRepoMdDoc = NULL;

    if(!pRepoMD)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFParseRepoMDDoc(pRepoMD->pszRepoMD, &pRepoMdDoc);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFFindRepoMDPart(
                  pRepoMdDoc,
                  TDNF_REPOMD_TYPE_PRIMARY,
                  &pRepoMD->pszPrimary);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFFindRepoMDPart(
                  pRepoMdDoc,
                  TDNF_REPOMD_TYPE_FILELISTS,
                  &pRepoMD->pszFileLists);
    /* file lists can be missing (issue #273) */
    if(dwError == ERROR_TDNF_NO_DATA)
    {
        dwError = 0;
    }
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFFindRepoMDPart(
                  pRepoMdDoc,
                  TDNF_REPOMD_TYPE_UPDATEINFO,
                  &pRepoMD->pszUpdateInfo);
    /* updateinfo is not mandatory */
    if(dwError == ERROR_TDNF_NO_DATA)
    {
        dwError = 0;
    }
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFFindRepoMDPart(
                  pRepoMdDoc,
                  TDNF_REPOMD_TYPE_OTHER,
                  &pRepoMD->pszOther);
    if(dwError == ERROR_TDNF_NO_DATA)
    {
        dwError = 0;
    }
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFRepoMdFree(pRepoMdDoc);
    return dwError;

error:
    goto cleanup;
}

void
TDNFFreeRepoMetadata(
    PTDNF_REPO_METADATA pRepoMD
    )
{
    if(!pRepoMD)
    {
        return;
    }
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszRepoCacheDir);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszRepo);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszRepoMD);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszPrimary);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszFileLists);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszUpdateInfo);
    TDNF_SAFE_FREE_MEMORY(pRepoMD->pszOther);
    TDNF_SAFE_FREE_MEMORY(pRepoMD);
}

static uint32_t
TDNFReplaceFile(
    const char *pszSrcFile,
    const char *pszDstFile
    )
{
    uint32_t dwError = 0;

    if (IsNullOrEmptyString(pszSrcFile) || IsNullOrEmptyString(pszDstFile) || access(pszSrcFile, F_OK))
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    /* coverity[toctou] */
    if (rename(pszSrcFile, pszDstFile) == -1)
    {
        dwError = errno;
        BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
    }
cleanup:
    return dwError;
error:
    goto cleanup;
}

uint32_t
TDNFDownloadMetadata(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszRepoDir,
    int nPrintOnly
    )
{
    uint32_t dwError = 0;
    char *pszRepoMDPath = NULL;
    char *pszRepoMDUrl = NULL;
    char *pszRepoDataDir = NULL;
    TDNF_REPOMD_DOC *pRepoMd = NULL;

    if (!nPrintOnly)
    {
        dwError = TDNFUtilsMakeDir(pszRepoDir);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFJoinPath(&pszRepoDataDir,
                    pszRepoDir,
                    "repodata",
                    NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFUtilsMakeDir(pszRepoDataDir);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFJoinPath(&pszRepoMDPath,
                    pszRepoDataDir, TDNF_REPO_METADATA_FILE_NAME,
                    NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        dwError = TDNFDownloadFileFromRepo(pTdnf, pRepo, TDNF_REPO_METADATA_FILE_PATH, pszRepoMDPath, pRepo->pszId);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    else
    {
        /* use first base url - we cannot tell which one is good */
        dwError = TDNFJoinPath(&pszRepoMDUrl,
                               pRepo->ppszBaseUrls[0],
                               TDNF_REPO_METADATA_FILE_PATH,
                               NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        /* if printing only we use the already downloaded repomd.xml */
        dwError = TDNFGetCachePath(pTdnf, pRepo,
                                   TDNF_REPO_METADATA_FILE_PATH, NULL,
                                   &pszRepoMDPath);
        BAIL_ON_TDNF_ERROR(dwError);

        pr_info("%s\n", pszRepoMDUrl);
    }

    dwError = TDNFParseRepoMDDoc(pszRepoMDPath, &pRepoMd);
    BAIL_ON_TDNF_ERROR(dwError);

    dwError = TDNFDownloadRepoMDParts(pTdnf, pRepoMd, pRepo, pszRepoDir, nPrintOnly);
    BAIL_ON_TDNF_ERROR(dwError);

cleanup:
    TDNFRepoMdFree(pRepoMd);
    TDNF_SAFE_FREE_MEMORY(pszRepoMDPath);
    TDNF_SAFE_FREE_MEMORY(pszRepoMDUrl);
    TDNF_SAFE_FREE_MEMORY(pszRepoDataDir);
    return dwError;
error:
    goto cleanup;
}

static uint32_t
TDNFDownloadRepoMDParts(
    PTDNF pTdnf,
    const TDNF_REPOMD_DOC *pRepoMd,
    PTDNF_REPO_DATA pRepo,
    const char *pszDir,
    int nPrintOnly
    )
{
    uint32_t dwError = 0;
    const char *pszPartFile = NULL;
    char *pszPartUrl = NULL;
    char *pszPartPath = NULL;
    const TDNF_REPOMD_RECORD *pRecord = NULL;
    uint32_t dwCount = 0;
    uint32_t dwIndex = 0;

    if(!pRepoMd ||
       !pRepo)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwCount = TDNFRepoMdGetRecordCount(pRepoMd);
    for(dwIndex = 0; dwIndex < dwCount; ++dwIndex)
    {
        pRecord = TDNFRepoMdGetRecord(pRepoMd, dwIndex);
        if(!pRecord || IsNullOrEmptyString(pRecord->pszLocationHref))
        {
            continue;
        }

        pszPartFile = pRecord->pszLocationHref;

        dwError = TDNFJoinPath(&pszPartPath,
                               pszDir,
                               pszPartFile,
                               NULL);
        BAIL_ON_TDNF_ERROR(dwError);

        if (!nPrintOnly)
        {
            dwError = TDNFDownloadFileFromRepo(pTdnf, pRepo, pszPartFile, pszPartPath, pRepo->pszId);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        else
        {
            dwError = TDNFJoinPath(&pszPartUrl,
                                   pRepo->ppszBaseUrls[0],
                                   pszPartFile,
                                   NULL);
            BAIL_ON_TDNF_ERROR(dwError);

            pr_info("%s\n", pszPartUrl);
            TDNF_SAFE_FREE_MEMORY(pszPartUrl);
        }
        TDNF_SAFE_FREE_MEMORY(pszPartPath);
    }

cleanup:
    return dwError;
error:
    TDNF_SAFE_FREE_MEMORY(pszPartUrl);
    TDNF_SAFE_FREE_MEMORY(pszPartPath);

    goto cleanup;
}
