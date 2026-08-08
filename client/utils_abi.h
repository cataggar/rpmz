/*
 * Copyright (C) 2015-2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#pragma once

#include <stdint.h>
#include <tdnftypes.h>

#include "../rpmzig/rpmdb.h"

uint32_t
TDNFIsFileOrSymlink(
    const char* pszPath,
    int* pnPathIsFile
    );

uint32_t
TDNFGetFileSize(
    const char* pszPath,
    int* pnSize
    );

int
TDNFIsGlob(
    const char* pszString
    );

uint32_t
TDNFUtilsMakeDir(
    const char* pszPath
    );

uint32_t
TDNFUtilsMakeDirs(
    const char* pszPath
    );

uint32_t
TDNFGetReleaseVersion(
    const char* pszRootDir,
    const char* pszDistroVerPkg,
    char** ppszVersion
    );

uint32_t
TdnfGetReleaseVersionConfig(
    const tdnf_rpm_config* pRpmConfig,
    const char* pszDistroVerPkg,
    char** ppszVersion
    );

uint32_t
TDNFGetKernelArch(
    char** ppszArch
    );

uint32_t
TDNFParseMetadataExpire(
    const char* pszMetadataExpire,
    long* plMetadataExpire
    );

uint32_t
TDNFAppendPath(
    const char* pszBase,
    const char* pszPart,
    char** ppszPath
    );

void
TDNFFreeHistoryInfoItems(
    PTDNF_HISTORY_INFO_ITEM pHistoryItems,
    int nCount
    );
