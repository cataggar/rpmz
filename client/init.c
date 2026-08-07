/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

static const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS
    gRepositoryInitCallbacks =
        TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS_DEFAULTS;

static void
TDNFDescribeRepository(
    void *pData,
    TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_VIEW *pView
    );

static void
TDNFSetRepositoryEnabled(
    void *pData,
    int nEnabled
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFBuildRefreshInput(
    PTDNF pTdnf,
    PTDNF_PACKAGE_CONTEXT pSack,
    TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_INPUT *pInput
    )
{
    if(!pTdnf || !pTdnf->pSack ||
       !pTdnf->pArgs || !pTdnf->pConf || !pInput)
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }

    memset(pInput, 0, sizeof(*pInput));
    pInput->tdnf_handle = pTdnf;
    pInput->sack = pSack;
    pInput->live_sack = pTdnf->pSack;
    pInput->repository_head = pTdnf->pRepos;
    pInput->command_line_repository_slot =
        (void **)&pTdnf->pCmdLineRepo;
    pInput->state_slot = (void **)&pTdnf->pTransactionPlanState;
    pInput->failure_stage = &pTdnf->nTestReloadFailureStage;
    pInput->refresh_flag = &pTdnf->pArgs->nRefresh;
    pInput->cache_dir = pTdnf->pConf->pszCacheDir;
    pInput->root_dir = TDNFPackageContextRootDir(pTdnf->pSack);
    pInput->architecture = pTdnf->pArgs->pszArch;
    pInput->rpm_config = pTdnf->pRpmConfig;
    pInput->cache_only = pTdnf->pArgs->nCacheOnly;
    pInput->all_deps = pTdnf->pArgs->nAllDeps;
    pInput->repository_init_callbacks = &gRepositoryInitCallbacks;
    pInput->describe_repository = TDNFDescribeRepository;
    pInput->set_repository_enabled = TDNFSetRepositoryEnabled;
    return 0;
}

static void
TDNFDescribeRepository(
    void *pData,
    TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_VIEW *pView
    )
{
    PTDNF_REPO_DATA pRepo = pData;

    if(!pRepo || !pView)
    {
        return;
    }

    memset(pView, 0, sizeof(*pView));
    pView->next = pRepo->pNext;
    pView->live_repository = pRepo->pRepo;
    pView->live_repository_slot = (void **)&pRepo->pRepo;
    pView->id = pRepo->pszId;
    pView->name = pRepo->pszName;
    pView->base_url = pRepo->ppszBaseUrls
        ? pRepo->ppszBaseUrls[0] : NULL;
    pView->metadata_expire = pRepo->lMetadataExpire;
    pView->priority = pRepo->nPriority;
    pView->enabled = pRepo->nEnabled;
    pView->skip_if_unavailable = pRepo->nSkipIfUnavailable;
    pView->has_metadata = pRepo->nHasMetaData;
}

static void
TDNFSetRepositoryEnabled(
    void *pData,
    int nEnabled
    )
{
    PTDNF_REPO_DATA pRepo = pData;

    if(!pRepo)
    {
        return;
    }
    if(pRepo->nEnabled && !nEnabled)
    {
        pr_info("Disabling Repo: '%s'\n", pRepo->pszName);
    }
    pRepo->nEnabled = nEnabled;
}
