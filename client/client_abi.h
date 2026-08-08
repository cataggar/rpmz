/*
 * Copyright (C) 2026 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#pragma once

#include <tdnftypes.h>
#include <tdnfdownload.h>
#include <tdnfrepomd.h>
#include <tdnfrpmconfig.h>

#include "../rpmzig/rpmdb.h"

typedef struct _TDNF_ID_LIST TDNF_ID_LIST, *PTDNF_ID_LIST;

#include "package_context.h"
#include "transaction_plan_capture_abi.inc"
#include "structs.h"
#include "../llconf/nodes.h"

uint32_t
ReadGPGKeyFile(
    const char *pszFile,
    char **ppszKeyData,
    int *pnSize
    );

uint32_t
TDNFGPGCheckPackageEx(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszFilePath,
    tdnf_rpm_file **ppRpmFile,
    int *pnPolicyRejected
    );

uint32_t
TDNFGPGCheckPackageWithFile(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszFilePath,
    tdnf_rpm_file *pRpmFile,
    int *pnPolicyRejected
    );

uint32_t
TDNFFetchRemoteGPGKey(
    PTDNF pTdnf,
    PTDNF_REPO_DATA pRepo,
    const char *pszUrlGPGKey,
    char **ppszKeyLocation
    );
