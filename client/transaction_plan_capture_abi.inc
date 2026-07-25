/*
 * Private borrowed-value ABI for authoritative transaction-plan capture.
 *
 * Every pointer is borrowed and remains valid only for the duration of
 * TDNFTransactionPlanCaptureCreate().  This include is internal to libtdnf and
 * is deliberately not installed.  A span/array pointer is NULL exactly when
 * its length/count is zero.  Presence and boolean fields contain only 0 or 1.
 * Every reference is a zero-based index into the corresponding top-level
 * array.  An absent optional has a zero/empty payload.
 */
#ifndef _TDNF_CLIENT_TRANSACTION_PLAN_CAPTURE_ABI_INC_
#define _TDNF_CLIENT_TRANSACTION_PLAN_CAPTURE_ABI_INC_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TDNF_TRANSACTION_PLAN_CAPTURE_ABI_VERSION UINT32_C(1)

#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DISTRO_SYNC UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_DOWNGRADE UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_ERASE UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_INSTALL UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_LOCK UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_REINSTALL UINT32_C(5)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE UINT32_C(6)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST_UPDATE_ALL UINT32_C(7)

#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_INSTALL UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ERASE UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_UPDATE UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DOWNGRADE UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_DIST_SYNC UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_REINSTALL UINT32_C(5)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_LOCK UINT32_C(6)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_MULTIVERSION UINT32_C(7)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_USER_INSTALLED UINT32_C(8)
#define TDNF_TRANSACTION_PLAN_CAPTURE_JOB_ALLOW_UNINSTALL UINT32_C(9)

#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_USER UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_DEPENDENCY UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_WEAK_DEPENDENCY UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_CLEANUP UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_INSTALLONLY_LIMIT UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REASON_POLICY UINT32_C(5)

#define TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_AVAILABLE UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_INSTALLED UINT32_C(1)

#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_DOWNGRADE UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_ERASE UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_INSTALL UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_OBSOLETE UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REINSTALL UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_UPGRADE UINT32_C(5)

#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_CLEANUP UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_DEPENDENCY UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_INSTALLONLY_LIMIT UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_OBSOLETES UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_POLICY UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_USER UINT32_C(5)
#define TDNF_TRANSACTION_PLAN_CAPTURE_ACTION_REASON_WEAK_DEPENDENCY UINT32_C(6)

#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_CONFLICT UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_INSTALLONLY_LIMIT UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NO_CANDIDATE UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_NOT_INSTALLABLE UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_OBSOLETES UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_PROTECTED_PACKAGE UINT32_C(5)
#define TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM_UNSATISFIED_REQUIREMENT UINT32_C(6)

#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_EQ UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GE UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_GT UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LE UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_LT UINT32_C(4)
#define TDNF_TRANSACTION_PLAN_CAPTURE_COMPARE_NONE UINT32_C(5)

#define TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_PROBLEMS UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_STATUS_RESOLVED_WITH_SKIPS UINT32_C(2)

#define TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_BDB UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_NDB UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB_SQLITE UINT32_C(2)

#define TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_AVAILABLE UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_INSTALLED UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY_COMMAND_LINE UINT32_C(2)

#define TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_ALL UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_PACKAGE UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_NAME UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_CAPTURE_SELECTION_CAPABILITY UINT32_C(3)

typedef struct
{
    const uint8_t *data;
    size_t length;
} TDNF_TRANSACTION_PLAN_CAPTURE_BYTES;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES kind;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES value;
    uint32_t is_pkgid;
} TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES href;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES xml_base;
    uint32_t has_xml_base;
} TDNF_TRANSACTION_PLAN_CAPTURE_LOCATION;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES name;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES flags;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES version;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES release;
    uint64_t epoch;
    uint32_t comparison;
    uint32_t sense;
    uint32_t has_epoch;
    uint32_t has_flags;
    uint32_t has_version;
    uint32_t has_release;
    uint32_t pre;
} TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES arch;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES name;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES release;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES version;
    uint64_t epoch;
    uint32_t has_arch;
    uint32_t has_epoch;
    uint32_t has_release;
} TDNF_TRANSACTION_PLAN_CAPTURE_MIN_VERSION;

typedef struct
{
    const TDNF_TRANSACTION_PLAN_CAPTURE_BYTES *excludes;
    const TDNF_TRANSACTION_PLAN_CAPTURE_BYTES *installonly_names;
    const TDNF_TRANSACTION_PLAN_CAPTURE_BYTES *locked_names;
    const TDNF_TRANSACTION_PLAN_CAPTURE_MIN_VERSION *min_versions;
    const TDNF_TRANSACTION_PLAN_CAPTURE_BYTES *protected_names;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES force_architecture;
    uint32_t exclude_count;
    uint32_t installonly_name_count;
    uint32_t locked_name_count;
    uint32_t min_version_count;
    uint32_t protected_name_count;
    uint32_t allow_erasing;
    uint32_t allow_multilib;
    uint32_t all_deps;
    uint32_t best;
    uint32_t clean_requirements_on_remove;
    uint32_t has_force_architecture;
    uint32_t include_installed;
    uint32_t installonly_limit;
    uint32_t install_weak_dependencies;
    uint32_t keep_orphans;
    uint32_t skip_broken;
} TDNF_TRANSACTION_PLAN_CAPTURE_POLICY;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES cookie_sha256;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES package_set_sha256;
    uint32_t backend;
} TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES architecture;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES distro;
    TDNF_TRANSACTION_PLAN_CAPTURE_POLICY policy;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES releasever;
    TDNF_TRANSACTION_PLAN_CAPTURE_RPMDB rpmdb;
    uint32_t resolution_status;
} TDNF_TRANSACTION_PLAN_CAPTURE_ENVIRONMENT;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM checksum;
    TDNF_TRANSACTION_PLAN_CAPTURE_LOCATION location;
    TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM open_checksum;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES record_type;
    uint64_t database_version;
    uint64_t open_size;
    uint64_t size;
    uint64_t timestamp;
    uint32_t has_checksum;
    uint32_t has_database_version;
    uint32_t has_open_checksum;
    uint32_t has_open_size;
    uint32_t has_size;
    uint32_t has_timestamp;
} TDNF_TRANSACTION_PLAN_CAPTURE_METADATA_RECORD;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES checksum_sha256;
    const TDNF_TRANSACTION_PLAN_CAPTURE_METADATA_RECORD *records;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES revision;
    uint64_t timestamp;
    uint32_t record_count;
    uint32_t has_revision;
} TDNF_TRANSACTION_PLAN_CAPTURE_REPOMD;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES id;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES metadata_sha256;
} TDNF_TRANSACTION_PLAN_CAPTURE_SNAPSHOT;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES id;
    TDNF_TRANSACTION_PLAN_CAPTURE_REPOMD repomd;
    TDNF_TRANSACTION_PLAN_CAPTURE_SNAPSHOT snapshot;
    int32_t priority;
    uint32_t cost;
    uint32_t kind;
    uint32_t has_repomd;
    uint32_t has_snapshot;
} TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES id;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES subject;
    uint32_t kind;
    uint32_t has_subject;
} TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY capability;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES selection_value;
    uint32_t action;
    uint32_t selection_kind;
    uint32_t selection_package_ref;
    uint32_t reason;
    uint32_t request_ref;
    uint32_t has_request_ref;
    uint32_t clean_deps;
    uint32_t force_best;
    uint32_t targeted;
    uint32_t not_by_user;
    uint32_t weak;
} TDNF_TRANSACTION_PLAN_CAPTURE_JOB;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES arch;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES name;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES release;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES version;
    uint32_t epoch;
    uint32_t has_epoch;
} TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_IDENTITY;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_CHECKSUM checksum;
    TDNF_TRANSACTION_PLAN_CAPTURE_LOCATION location;
    uint64_t size;
    uint32_t has_location;
    uint32_t has_size;
} TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_SOURCE;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_IDENTITY identity;
    TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE_SOURCE source;
    uint32_t repository_ref;
    uint32_t rpmdb_hnum;
    uint32_t state;
    uint32_t has_rpmdb_hnum;
    uint32_t has_source;
} TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE;

typedef struct
{
    uint32_t target_package_ref;
    uint32_t kind;
    uint32_t reason;
    uint32_t requested_job_ref;
    uint32_t has_requested_job_ref;
    /* Ranges partition prior_package_refs in action order. */
    uint32_t prior_offset;
    uint32_t prior_count;
} TDNF_TRANSACTION_PLAN_CAPTURE_ACTION;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY capability;
    uint32_t count;
    uint32_t kind;
    uint32_t job_ref;
    uint32_t package_ref;
    uint32_t related_package_ref;
    uint32_t has_capability;
    uint32_t has_job_ref;
    uint32_t has_package_ref;
    uint32_t has_related_package_ref;
} TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM;

typedef struct
{
    uint32_t abi_version;
    uint32_t struct_size;
    TDNF_TRANSACTION_PLAN_CAPTURE_ENVIRONMENT environment;
    const TDNF_TRANSACTION_PLAN_CAPTURE_REPOSITORY *repositories;
    const TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST *requests;
    const TDNF_TRANSACTION_PLAN_CAPTURE_JOB *jobs;
    const TDNF_TRANSACTION_PLAN_CAPTURE_PACKAGE *packages;
    const TDNF_TRANSACTION_PLAN_CAPTURE_ACTION *actions;
    const uint32_t *prior_package_refs;
    const uint32_t *selected_package_refs;
    const uint32_t *skipped_job_refs;
    const uint32_t *hidden_package_refs;
    const TDNF_TRANSACTION_PLAN_CAPTURE_PROBLEM *problems;
    uint32_t repository_count;
    uint32_t request_count;
    uint32_t job_count;
    uint32_t package_count;
    uint32_t action_count;
    uint32_t prior_package_ref_count;
    uint32_t selected_package_ref_count;
    uint32_t skipped_job_ref_count;
    uint32_t hidden_package_ref_count;
    uint32_t problem_count;
} TDNF_TRANSACTION_PLAN_CAPTURE;

typedef struct TDNF_TRANSACTION_PLAN_CAPTURE_OWNER
    TDNF_TRANSACTION_PLAN_CAPTURE_OWNER;

#if defined(__GNUC__) || defined(__clang__)
#define TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN \
    __attribute__((visibility("hidden")))
#else
#define TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN
#endif

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanCaptureCreate(
    const TDNF_TRANSACTION_PLAN_CAPTURE *input,
    TDNF_TRANSACTION_PLAN_CAPTURE_OWNER **owner
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanCaptureDestroy(
    TDNF_TRANSACTION_PLAN_CAPTURE_OWNER *owner
    );

#ifdef __cplusplus
}
#endif

#endif /* _TDNF_CLIENT_TRANSACTION_PLAN_CAPTURE_ABI_INC_ */
