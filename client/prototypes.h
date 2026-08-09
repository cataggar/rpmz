/*
 * Copyright (C) 2015-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#ifndef __CLIENT_PROTOTYPES_H__
#define __CLIENT_PROTOTYPES_H__

#include <unistd.h>

extern uid_t gEuid;
struct cnfnode;

uint32_t
tdnf_repomd_native_verified_transaction_solve_config(
    const TDNF_REPOMD_NATIVE_TRANSACTION_ITEM_V2 *pItems,
    const unsigned char *const *ppbHeaders,
    const size_t *pnHeaderLengths,
    const uint64_t *pqwPackageSizes,
    uint32_t dwItemCount,
    const tdnf_rpm_config *pConfig,
    TDNF_REPOMD_NATIVE_TRANSACTION_PLAN **ppPlan
    );

uint32_t
TDNFRefreshSack(
    PTDNF pTdnf,
    PTDNF_PACKAGE_CONTEXT pSack,
    int nCleanMetadata
    );

uint32_t
TDNFHistoryGoal(
    PTDNF pTdnf,
    PTDNF_ID_LIST pqInstall,
    PTDNF_ID_LIST pqErase,
    PTDNF_SOLVED_PKG_INFO* ppInfo
    );

uint32_t
TDNFPkgsToExclude(
    PTDNF pTdnf,
    uint32_t *pdwPkgsToExclude,
    char***  pppszExclude
    );



TDNF_TRANSACTION_PLAN_REQUEST_TRACE *
TDNFTransactionPlanRequestTraceCreate(
    uint32_t alter_type,
    const char *const *subjects,
    uint32_t subject_count
    );

TDNF_TRANSACTION_PLAN_REQUEST_TRACE *
TDNFTransactionPlanRequestTraceCreateHistory(void);

void
TDNFTransactionPlanRequestTraceDestroy(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace
    );

void
TDNFTransactionPlanRequestTraceRecordGoalRange(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *ids,
    uint32_t start,
    uint32_t end,
    uint32_t alter_type,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordHistoryGoal(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const char *subject,
    uint32_t request_kind,
    uint32_t action,
    const int32_t *ids,
    uint32_t start,
    uint32_t end,
    uint32_t outcome
    );

void
TDNFTransactionPlanRequestTraceRecordRequestOutcome(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t request_ref,
    uint32_t outcome
    );

void
TDNFTransactionPlanRequestTraceCommitGoal(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    int32_t selection_id,
    uint32_t alter_type,
    const int32_t *queue,
    uint32_t start,
    uint32_t end
    );

void
TDNFTransactionPlanRequestTraceRecordPackageJob(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t queue_pair_index,
    uint32_t action,
    int32_t selection_id,
    int32_t raw_how,
    uint32_t raw_flags,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordPackageJobRange(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *queue,
    uint32_t start,
    uint32_t end,
    uint32_t action,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordNameJob(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t queue_pair_index,
    uint32_t action,
    const char *selection_name,
    int32_t raw_how,
    uint32_t raw_flags,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordAllJob(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t queue_pair_index,
    uint32_t action,
    int32_t raw_how,
    uint32_t raw_flags,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordCapabilityJob(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t queue_pair_index,
    uint32_t action,
    const TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY *capability,
    int32_t raw_how,
    uint32_t raw_flags,
    uint32_t reason,
    uint32_t request_ref
    );

void
TDNFTransactionPlanRequestTraceRecordPolicies(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const char *const *excludes,
    const char *const *installonly_names,
    const char *const *locked_names,
    const char *const *min_versions,
    const char *const *protected_names,
    uint32_t allow_erasing
    );

void
TDNFTransactionPlanRequestTraceFinalize(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *queue,
    uint32_t element_count,
    int32_t clean_deps_mask,
    int32_t force_best_mask
    );

const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW *
TDNFTransactionPlanRequestTraceGetView(
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace
    );

uint32_t
TDNFTransactionPlanRequestTraceCaptureFactsCreate(
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_PACKAGE_REF *package_refs,
    uint32_t package_ref_count,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_FACTS **facts,
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER **owner
    );

void
TDNFTransactionPlanRequestTraceCaptureFactsDestroy(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER *owner
    );


uint32_t
TDNFReadConfig(
    PTDNF pTdnf,
    const char* pszConfFile,
    const char* pszConfGroup
    );

uint32_t
TDNFConfigExpandVars(
    PTDNF pTdnf
    );

uint32_t
TDNFConfigReadProxySettings(
    PCONF_SECTION pSection,
    PTDNF_CONF pConf);

void
TDNFFreeConfig(
    PTDNF_CONF pConf
    );

uint32_t
TDNFConfigReplaceVars(
    PTDNF pTdnf,
    char** pszString
    );


//updateinfo.zig
uint32_t
TDNFGetSecuritySeverityOption(
    PTDNF pTdnf,
    uint32_t *pdwSecurity,
    char **ppszSeverity
    );


uint32_t
TDNFGetUpdatePkgs(
    PTDNF pTdnf,
    char*** pppszPkgs,
    uint32_t *pdwCount
    );

uint32_t
TDNFGetRebootRequiredOption(
    PTDNF pTdnf,
    uint32_t *pdwRebootRequired
    );

//validate.c
uint32_t
TDNFGetSkipProblemOption(
    PTDNF pTdnf,
    TDNF_SKIPPROBLEM_TYPE *pdwSkipProblem
    );

/* plugins.zig */
uint32_t
TDNFLoadPlugins(
    PTDNF pTdnf
    );

void
TDNFFreePlugins(
    PTDNF_PLUGIN pPlugins
    );

uint32_t
BuiltinPluginsRepoConfig(
    PTDNF pTdnf,
    const struct cnfnode *pSection
    );

uint32_t
BuiltinPluginsRepoMDDownloadStart(
    PTDNF pTdnf,
    const char *pszRepoId,
    const char *pszRepoDataDir
    );

uint32_t
BuiltinPluginsRepoMDDownloadEnd(
    PTDNF pTdnf,
    const char *pszRepoId,
    const char *pszRepoMDFile
    );

struct cnfnode *parse_varsdirs(char *dirs[]);

char *replace_vars(struct cnfnode *cn_vars, const char *source);

#endif /* __CLIENT_PROTOTYPES_H__ */
