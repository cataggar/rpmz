/*
 * Private borrowed-value ABI for authoritative transaction-plan capture.
 *
 * Capture-input pointers are borrowed for TDNFTransactionPlanCaptureCreate().
 * This include is internal to libtdnf and deliberately not installed.  A
 * span/array pointer is NULL exactly when its length/count is zero.  Presence
 * and boolean fields contain only 0 or 1.  Every reference is a zero-based
 * index into the corresponding top-level array.  An absent optional has a
 * zero/empty payload.
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
#define TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_PENDING UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_QUEUED UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_SATISFIED UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_REQUEST_OUTCOME_NO_CANDIDATE UINT32_C(3)

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

#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_NO_REQUEST UINT32_MAX

#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_CLEAN_DEPS (UINT32_C(1) << 0)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_FORCE_BEST (UINT32_C(1) << 1)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_TARGETED (UINT32_C(1) << 2)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_NOT_BY_USER (UINT32_C(1) << 3)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_FLAG_WEAK (UINT32_C(1) << 4)

#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_EXCLUDE UINT32_C(0)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_INSTALLONLY UINT32_C(1)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_LOCK UINT32_C(2)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_MIN_VERSION UINT32_C(3)
#define TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_PROTECTED UINT32_C(4)

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
    uint32_t outcome;
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

typedef struct TDNF_TRANSACTION_PLAN_LIBSOLV_CAPTURE_OWNER
    TDNF_TRANSACTION_PLAN_LIBSOLV_CAPTURE_OWNER;

typedef struct
{
    void *repository;
    const char *id;
    const char *cache_dir;
    int32_t priority;
    uint32_t cost;
} TDNF_TRANSACTION_PLAN_INTEGRATION_REPOSITORY;

typedef struct
{
    const char *architecture;
    const char *distro;
    const char *releasever;
    const char *force_architecture;
    const char *const *excludes;
    const char *const *installonly_names;
    const char *const *locked_names;
    const char *const *min_versions;
    const char *const *protected_names;
    const void *rpm_config;
    uint32_t installonly_limit;
    uint32_t allow_erasing;
    uint32_t allow_multilib;
    uint32_t all_deps;
    uint32_t best;
    uint32_t clean_requirements_on_remove;
    uint32_t include_installed;
    uint32_t install_weak_dependencies;
    uint32_t keep_orphans;
    uint32_t skip_broken;
} TDNF_TRANSACTION_PLAN_INTEGRATION_ENVIRONMENT;

typedef struct TDNF_TRANSACTION_PLAN_STATE TDNF_TRANSACTION_PLAN_STATE;

struct _TDNF_;
struct _TDNF_REPO_METADATA;
struct _SolvSack;
struct _SOLV_REPO_INFO_INTERNAL_;

typedef struct
{
    void (*free_memory)(void *);
    uint32_t (*make_dirs)(const char *);
    uint32_t (*get_cache_path)(
        struct _TDNF_ *,
        PTDNF_REPO_DATA,
        const char *,
        const char *,
        char **);
    uint32_t (*get_repo_md)(
        struct _TDNF_ *,
        PTDNF_REPO_DATA,
        const char *,
        struct _TDNF_REPO_METADATA **);
    void (*free_repo_metadata)(struct _TDNF_REPO_METADATA *);
    uint32_t (*calculate_cookie)(const char *, unsigned char *);
    uint32_t (*use_metadata_cache)(
        struct _SolvSack *,
        struct _SOLV_REPO_INFO_INTERNAL_ *,
        int *);
    uint32_t (*create_metadata_cache)(
        struct _SolvSack *,
        struct _SOLV_REPO_INFO_INTERNAL_ *);
    uint32_t (*init_from_metadata)(
        Repo *,
        const char *,
        struct _TDNF_REPO_METADATA *);
    uint32_t (*read_rpms_from_directory)(Repo *, const char *);
    uint32_t (*apply_snapshot)(
        struct _TDNF_ *,
        PTDNF_REPO_DATA,
        struct _SolvSack *,
        Repo *);
} TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS;

typedef struct
{
    void *next;
    void *live_repository;
    void **live_repository_slot;
    const char *id;
    const char *name;
    const char *base_url;
    const char *snapshot_file;
    long metadata_expire;
    int priority;
    int enabled;
    int skip_if_unavailable;
    int has_metadata;
} TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_VIEW;

typedef struct
{
    void *tdnf_handle;
    void *sack;
    void *live_sack;
    void *repository_head;
    void **command_line_repository_slot;
    void **state_slot;
    uint32_t *failure_stage;
    int *refresh_flag;
    const char *cache_dir;
    const char *root_dir;
    const char *architecture;
    const void *rpm_config;
    int cache_only;
    int all_deps;
    const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS
        *repository_init_callbacks;
    void (*describe_repository)(
        void *,
        TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_VIEW *);
    void (*set_repository_enabled)(void *, int);
} TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_INPUT;

typedef struct
{
    void *tdnf_handle;
    void *repo_data;
    void *sack;
    void *pool;
    const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS *callbacks;
    const TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_INPUT *refresh_input;
    void **state_slot;
    void *command_line_repository;
    void **live_repository_slot;
    uint32_t *failure_stage;
    const char *repository_id;
    const char *base_url;
    const char *snapshot_file;
    int32_t priority;
    uint32_t has_metadata;
    uint32_t apply_snapshot;
    uint32_t reuse_empty_repository;
} TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_INPUT;

#define TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS_DEFAULTS        \
    {                                                                   \
        .free_memory = TDNFFreeMemory,                                  \
        .make_dirs = TDNFUtilsMakeDirs,                                 \
        .get_cache_path = TDNFGetCachePath,                             \
        .get_repo_md = TDNFGetRepoMD,                                   \
        .free_repo_metadata = TDNFFreeRepoMetadata,                     \
        .calculate_cookie = SolvCalculateCookieForFile,                 \
        .use_metadata_cache = SolvUseMetaDataCache,                     \
        .create_metadata_cache = SolvCreateMetaDataCache,               \
        .init_from_metadata = TDNFInitRepoFromMetadata,                 \
        .read_rpms_from_directory = SolvReadRpmsFromDirectory,          \
        .apply_snapshot = TDNFApplySnapshot,                            \
    }

#define TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_INPUT_DEFAULTS            \
    {                                                                   \
        .callbacks = &(const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS) \
            TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_CALLBACKS_DEFAULTS,   \
    }

/*
 * Owned per-resolve provenance.  Package selections retain libsolv Id values
 * until extraction supplies the corresponding capture package references.
 * Views borrow all storage from the trace and become invalid on destruction.
 */
typedef struct TDNF_TRANSACTION_PLAN_REQUEST_TRACE
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_CAPABILITY capability;
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES selection_value;
    int32_t selection_id;
    uint32_t action;
    uint32_t selection_kind;
    uint32_t raw_how;
    uint32_t effective_how;
    uint32_t raw_flags;
    uint32_t effective_flags;
    uint32_t reason;
    uint32_t request_ref;
    uint32_t has_request_ref;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_JOB;

typedef struct
{
    uint32_t queue_pair_index;
    uint32_t job_ref;
    uint32_t request_ref;
    uint32_t has_request_ref;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_QUEUE_ORIGIN;

typedef struct
{
    TDNF_TRANSACTION_PLAN_CAPTURE_BYTES value;
    uint32_t kind;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_FACT;

typedef struct
{
    uint32_t request_ref;
    int32_t selection_id;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_SATISFIED_SELECTION;

typedef struct
{
    const TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST *requests;
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_JOB *jobs;
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_QUEUE_ORIGIN *queue_origins;
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_POLICY_FACT *policy_facts;
    uint32_t request_count;
    uint32_t job_count;
    uint32_t queue_origin_count;
    uint32_t policy_fact_count;
    uint32_t allow_erasing;
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_SATISFIED_SELECTION
        *satisfied_selections;
    uint32_t satisfied_selection_count;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW;

typedef struct
{
    int32_t selection_id;
    uint32_t package_ref;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_PACKAGE_REF;

typedef struct
{
    uint32_t request_ref;
    uint32_t package_ref;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_SATISFIED_PACKAGE;

typedef struct
{
    const TDNF_TRANSACTION_PLAN_CAPTURE_REQUEST *requests;
    const TDNF_TRANSACTION_PLAN_CAPTURE_JOB *jobs;
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_SATISFIED_PACKAGE
        *satisfied_packages;
    uint32_t request_count;
    uint32_t job_count;
    uint32_t satisfied_package_count;
} TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_FACTS;

typedef struct TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER;

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

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanLibsolvCaptureCreate(
    void *pool,
    void *solver,
    void *transaction,
    const void *jobs,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW *trace,
    int solve_status,
    uint32_t problem_count,
    uint32_t problems_accepted,
    uint32_t unresolved_count,
    const int32_t *installonly_erases,
    uint32_t installonly_erase_count,
    const TDNF_TRANSACTION_PLAN_CAPTURE **facts,
    TDNF_TRANSACTION_PLAN_LIBSOLV_CAPTURE_OWNER **owner
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanLibsolvCaptureDestroy(
    TDNF_TRANSACTION_PLAN_LIBSOLV_CAPTURE_OWNER *owner
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateSetEnabled(
    TDNF_TRANSACTION_PLAN_STATE **state,
    uint32_t enabled
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateIsEnabled(
    const TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanInitRepository(
    const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_INPUT *input,
    void **loaded_repo
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanReloadRepository(
    const TDNF_TRANSACTION_PLAN_REPOSITORY_INIT_INPUT *input,
    void **loaded_repo
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanRefreshSack(
    const TDNF_TRANSACTION_PLAN_REPOSITORY_REFRESH_INPUT *input,
    int clean_metadata
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateRecordRepository(
    TDNF_TRANSACTION_PLAN_STATE **state,
    void *repository,
    const uint8_t cookie_sha256[32],
    uint32_t include_filelists,
    uint32_t include_updateinfo,
    uint32_t include_other
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateRepositoryRecordCount(
    const TDNF_TRANSACTION_PLAN_STATE *state,
    void *repository
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateFailNextRepositoryRecord(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateFailNextCapture(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateFailNextCaptureIntegrity(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanLoadSolvRepo(
    void *repository,
    const char *repomd,
    const char *primary,
    const char *filelists,
    const char *updateinfo,
    const char *other,
    uint8_t cookie_sha256[32]
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN int
TDNFTransactionPlanBindSolvCookie(
    const uint8_t raw_cookie[32],
    uint32_t include_filelists,
    uint32_t include_updateinfo,
    uint32_t include_other,
    uint8_t output[32]
    );

#define TDNF_TRANSACTION_PLAN_BIND_CACHE_COOKIE(_metadata, _cookie, _error) \
    do {                                                                 \
        if (TDNFTransactionPlanBindSolvCookie(                           \
                (_cookie), (_metadata)->pszFileLists != NULL,            \
                (_metadata)->pszUpdateInfo != NULL,                      \
                (_metadata)->pszOther != NULL, (_cookie)) != 0)          \
        {                                                                \
            (_error) = ERROR_TDNF_INVALID_PARAMETER;                    \
            BAIL_ON_TDNF_ERROR(_error);                                  \
        }                                                                \
    } while (0)

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN int
TDNFTransactionPlanTestWriteFileProvider(
    const void *rpm_config
    );

#define TDNF_TRANSACTION_PLAN_LOAD_REPOSITORY(                           \
    _repo, _metadata, _cookie, _error)                                  \
    do {                                                                 \
        (_error) = TDNFTransactionPlanLoadSolvRepo(                      \
            (_repo), (_metadata)->pszRepoMD,                             \
            (_metadata)->pszPrimary, (_metadata)->pszFileLists,          \
            (_metadata)->pszUpdateInfo, (_metadata)->pszOther,           \
            (_cookie));                                                  \
    } while (0)

#define TDNF_TRANSACTION_PLAN_RECORD_LOADED_REPOSITORY(                  \
    _tdnf, _repo_data, _repo, _metadata, _used_cache, _cache_cookie,    \
    _load_cookie, _error)                                                \
    do {                                                                 \
        if ((_repo_data)->nHasMetaData &&                                \
            TDNFTransactionPlanStateIsEnabled(                           \
                (_tdnf)->pTransactionPlanState))                         \
        {                                                                \
            const uint8_t *_cookie = (_used_cache)                       \
                ? (_cache_cookie) : (_load_cookie);                      \
            (_error) = TDNFTransactionPlanStateRecordRepository(         \
                &(_tdnf)->pTransactionPlanState, (_repo), _cookie,       \
                (_metadata)->pszFileLists != NULL,                       \
                (_metadata)->pszUpdateInfo != NULL,                      \
                (_metadata)->pszOther != NULL);                          \
        }                                                                \
    } while (0)

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateClear(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStatePublish(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateHasPendingProblem(
    const TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStatePublishProblem(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

#define TDNF_TRANSACTION_PLAN_HANDLE_RESOLVE_ERROR(_tdnf)               \
    do {                                                                 \
        if ((_tdnf) &&                                                   \
            !TDNFTransactionPlanStatePublishProblem(                     \
                (_tdnf)->pTransactionPlanState))                         \
            TDNFTransactionPlanStateClear(                               \
                (_tdnf)->pTransactionPlanState);                         \
    } while (0)

#define TDNF_TRANSACTION_PLAN_PUBLISH(_tdnf, _error)                    \
    do {                                                                 \
        (_error) = TDNFTransactionPlanStatePublish(                      \
            (_tdnf)->pTransactionPlanState);                             \
        BAIL_ON_TDNF_ERROR(_error);                                      \
    } while (0)

#define TDNF_TRANSACTION_PLAN_REJECT_UNSUPPORTED_RESOLVE(_tdnf, _error) \
    do {                                                                 \
        if (TDNFTransactionPlanStateIsEnabled(                           \
                (_tdnf)->pTransactionPlanState) &&                       \
            ((_tdnf)->pArgs->nBuildDeps || (_tdnf)->pArgs->nSource ||   \
             (_tdnf)->pArgs->nNoDeps))                                  \
        {                                                                \
            (_error) = ERROR_TDNF_CALL_NOT_SUPPORTED;                   \
            BAIL_ON_TDNF_ERROR(_error);                                  \
        }                                                                \
    } while (0)

/* Plan v1 has no authoritative identity model for repofromdir repositories. */
#define TDNF_TRANSACTION_PLAN_REJECT_REPOFROMDIR(_tdnf, _error)         \
    do {                                                                 \
        if (TDNFTransactionPlanStateIsEnabled(                           \
                (_tdnf)->pTransactionPlanState))                         \
        {                                                                \
            PTDNF_REPO_DATA _repo_data;                                  \
            char **_repo_ids = (_tdnf)->ppszRepoFromDirIds;              \
            for (; _repo_ids && *_repo_ids; _repo_ids++)                \
                for (_repo_data = (_tdnf)->pRepos; _repo_data;           \
                     _repo_data = _repo_data->pNext)                     \
                    if (_repo_data->nEnabled && _repo_data->pszId &&     \
                        !strcmp(_repo_data->pszId, *_repo_ids))           \
                    { (_error) = ERROR_TDNF_CALL_NOT_SUPPORTED; break; } \
            BAIL_ON_TDNF_ERROR(_error);                                  \
        }                                                                \
    } while (0)

#define TDNF_TRANSACTION_PLAN_CHECK_TRACE(_tdnf, _error)                \
    do {                                                                 \
        if (TDNFTransactionPlanStateIsEnabled(                           \
                (_tdnf)->pTransactionPlanState))                         \
        {                                                                \
            (_error) = TDNFTransactionPlanRequestTraceGetError(          \
                (_tdnf)->pRequestTrace);                                 \
            BAIL_ON_TDNF_ERROR(_error);                                  \
        }                                                                \
    } while (0)

#define TDNF_TRANSACTION_PLAN_CONSIDER_NEW_SOLVABLE(_pool, _solvid)      \
    do {                                                                 \
        if ((_pool)->considered)                                        \
        {                                                                \
            map_grow((_pool)->considered, (_pool)->nsolvables);          \
            map_set((_pool)->considered, (_solvid));                     \
        }                                                                \
    } while (0)

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateDestroy(
    TDNF_TRANSACTION_PLAN_STATE *state
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanStateGetCanonicalJson(
    const TDNF_TRANSACTION_PLAN_STATE *state,
    const uint8_t **data,
    size_t *length
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanStateFreeCanonicalJson(
    const uint8_t *data,
    size_t length
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanIntegrationCapturePending(
    TDNF_TRANSACTION_PLAN_STATE *state,
    void *pool,
    void *solver,
    void *transaction,
    const void *jobs,
    const void *native_solve,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW *trace,
    int solve_status,
    uint32_t problem_count,
    uint32_t problems_accepted,
    uint32_t unresolved_count,
    uint32_t terminal_problem_kind,
    const TDNF_TRANSACTION_PLAN_INTEGRATION_REPOSITORY *repositories,
    uint32_t repository_count,
    const TDNF_TRANSACTION_PLAN_INTEGRATION_ENVIRONMENT *environment
    );

/*
 * Private handle-level control.  These declarations are intentionally absent
 * from installed headers; a future public API can wrap the same state.
 */
TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanCaptureSetEnabled(
    void *tdnf_handle,
    uint32_t enabled
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanCaptureGetCanonicalJson(
    void *tdnf_handle,
    const uint8_t **data,
    size_t *length
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanCaptureFailNextRepositoryRecord(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanCaptureFailNextComposition(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanCaptureFailNextIntegrity(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanTestFailNextReload(
    void *tdnf_handle,
    uint32_t stage
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uintptr_t
TDNFTransactionPlanTestPoolIdentity(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestPoolSolvableCount(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestPoolRepoCount(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestConsideredCount(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uintptr_t
TDNFTransactionPlanTestConsideredIdentity(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoDataCount(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestGrowCmdlineConsidered(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRetireNullSack(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestPublicInitRepo(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestReloadRepo(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestInitRepoInSack(
    void *tdnf_handle,
    void *sack,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uintptr_t
TDNFTransactionPlanTestRepoIdentity(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoId(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoPackageCount(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoBindingCount(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoRecordCount(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestRepoRecordDigest(
    void *tdnf_handle,
    const char *repo_id,
    uint8_t digest[32]
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestInitRepoValidation(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestPoolIndexesHealthy(
    void *tdnf_handle
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanTestEnableRepo(
    void *tdnf_handle,
    const char *repo_id
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFHistoryGoalWithUnresolved(
    void *tdnf_handle,
    void *install_queue,
    void *erase_queue,
    uint32_t unresolved_count,
    void *solved_info
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFInitRepoWithResult(
    void *tdnf_handle,
    void *repo_data,
    void *sack,
    void **loaded_repo
    );


#define TDNF_TRANSACTION_PLAN_CAPTURE_SOLVED(                            \
    _tdnf, _jobs, _solver, _transaction, _native, _problems, _accepted,  \
    _unresolved, _terminal_problem, _excludes, _allow_erasing,          \
    _clean_deps, _error)                                                 \
    do {                                                                 \
        if (TDNFTransactionPlanStateIsEnabled(                           \
                (_tdnf)->pTransactionPlanState))                         \
        {                                                                \
            PTDNF_REPOMD_NATIVE_SOLVER_LIVE_REPOSITORY_V16 _repos = NULL;   \
            TDNF_TRANSACTION_PLAN_INTEGRATION_REPOSITORY *_capture_repos = NULL; \
            uint32_t _repo_count = 0;                                    \
            TDNF_TRANSACTION_PLAN_INTEGRATION_ENVIRONMENT _environment = { \
                .architecture = (_tdnf)->pConf->pszBaseArch,             \
                .distro = (_tdnf)->pConf->pszOSName,                     \
                .releasever = (_tdnf)->pConf->pszVarReleaseVer,          \
                .force_architecture = (_tdnf)->pArgs->pszArch,           \
                .excludes = (const char *const *)(_excludes),            \
                .installonly_names = (const char *const *)               \
                    (_tdnf)->pConf->ppszInstallOnlyPkgs,                  \
                .locked_names = (const char *const *)                    \
                    (_tdnf)->pConf->ppszPkgLocks,                         \
                .min_versions = (const char *const *)                    \
                    (_tdnf)->pConf->ppszMinVersions,                      \
                .protected_names = (const char *const *)                 \
                    (_tdnf)->pConf->ppszProtectedPkgs,                    \
                .rpm_config = (_tdnf)->pRpmConfig,                       \
                .installonly_limit = (uint32_t)                          \
                    (_tdnf)->pConf->nInstallOnlyLimit,                    \
                .allow_erasing = !!(_allow_erasing),                     \
                .allow_multilib = 1,                                     \
                .all_deps = !!(_tdnf)->pArgs->nAllDeps,                  \
                .best = !!(_tdnf)->pArgs->nBest,                         \
                .clean_requirements_on_remove = !!(_clean_deps),         \
                .include_installed = !(_tdnf)->pArgs->nAllDeps,          \
                .install_weak_dependencies = 1,                          \
                .keep_orphans = 1,                                      \
                .skip_broken = !!(_tdnf)->pArgs->nSkipBroken             \
            };                                                           \
            (_error) = TDNFTransactionPlanRequestTraceGetError(          \
                (_tdnf)->pRequestTrace);                                 \
            if ((_error)) break;                                        \
            (_error) = TDNFGoalBuildNativeSolverRepoInputs(              \
                (_tdnf), &_repos, &_repo_count);                          \
            if ((_error) == ERROR_TDNF_NO_DATA) (_error) = 0;            \
            if (!(_error) && _repo_count)                                 \
            {                                                            \
                uint32_t _index;                                         \
                (_error) = TDNFAllocateMemory(                            \
                    _repo_count, sizeof(*_capture_repos),                 \
                    (void **)&_capture_repos);                            \
                for (_index = 0; !(_error) && _index < _repo_count;      \
                     _index++)                                           \
                {                                                        \
                    PTDNF_REPO_DATA _repo_data = (_tdnf)->pRepos;        \
                    while (_repo_data &&                                 \
                           (!_repo_data->pRepo ||                         \
                            IsNullOrEmptyString(_repo_data->pszId) ||     \
                            strcmp(_repo_data->pszId,                     \
                                   _repos[_index].pszId)))                \
                        _repo_data = _repo_data->pNext;                   \
                    if (!_repo_data)                                     \
                    {                                                    \
                        (_error) = ERROR_TDNF_SOLV_FAILED;               \
                        break;                                           \
                    }                                                    \
                    _capture_repos[_index].repository =                  \
                        _repo_data->pRepo;                                \
                    _capture_repos[_index].id = _repos[_index].pszId;    \
                    _capture_repos[_index].cache_dir =                   \
                        _repos[_index].pszCacheDir;                       \
                    _capture_repos[_index].priority =                    \
                        _repos[_index].nPriority;                         \
                    _capture_repos[_index].cost =                        \
                        TDNF_REPOMD_NATIVE_SOLVER_DEFAULT_REPOSITORY_COST; \
                }                                                        \
            }                                                            \
            if (!(_error))                                               \
            {                                                            \
                (_error) = TDNFTransactionPlanIntegrationCapturePending( \
                    (_tdnf)->pTransactionPlanState,                       \
                    (_tdnf)->pSack->pPool, (_solver), (_transaction),    \
                    (_jobs), (_native),                                  \
                    TDNFTransactionPlanRequestTraceGetView(              \
                        (_tdnf)->pRequestTrace),                          \
                    (_problems), (uint32_t)(_problems), !!(_accepted),   \
                    (uint32_t)(_unresolved), (_terminal_problem),        \
                    _capture_repos, _repo_count, &_environment);         \
            }                                                            \
            TDNF_SAFE_FREE_MEMORY(_capture_repos);                       \
            TDNFGoalFreeNativeSolverRepoInputs(_repos, _repo_count);      \
        }                                                                \
    } while (0)

#define TDNF_TRANSACTION_PLAN_CAPTURE_FAILED_SOLVE(                      \
    _tdnf, _jobs, _solver, _problems, _unresolved, _excludes,          \
    _allow_erasing, _clean_deps, _error)                                \
    do {                                                                 \
        uint32_t _solve_error = (_error);                                \
        TDNFTransactionPlanRequestTraceFinalize(                         \
            (_tdnf)->pRequestTrace, (_jobs)->elements,                   \
            (_jobs)->count, SOLVER_CLEANDEPS, SOLVER_FORCEBEST);         \
        (_error) = 0;                                                    \
        TDNF_TRANSACTION_PLAN_CAPTURE_SOLVED(                            \
            (_tdnf), (_jobs), (_solver), NULL, NULL, (_problems), 0,     \
            (_unresolved), UINT32_MAX, (_excludes), (_allow_erasing),   \
            (_clean_deps), (_error));                                   \
        if ((_error)) { TDNFTransactionPlanStateClear((_tdnf)->pTransactionPlanState); (_error) = _solve_error; goto error; } \
        (_error) = _solve_error;                                         \
        goto error;                                                      \
    } while (0)

#define TDNF_TRANSACTION_PLAN_CAPTURE_TERMINAL_PROBLEM(                  \
    _tdnf, _jobs, _solver, _transaction, _native, _problems, _unresolved, \
    _problem_kind, _excludes, _allow_erasing, _clean_deps, _error)      \
    do {                                                                 \
        uint32_t _terminal_error = (_error);                             \
        TDNFTransactionPlanRequestTraceFinalize(                         \
            (_tdnf)->pRequestTrace, (_jobs)->elements,                   \
            (_jobs)->count, SOLVER_CLEANDEPS, SOLVER_FORCEBEST);         \
        (_error) = 0;                                                    \
        TDNF_TRANSACTION_PLAN_CAPTURE_SOLVED(                            \
            (_tdnf), (_jobs), (_solver), (_transaction), (_native),       \
            (_problems), 0, (_unresolved), (_problem_kind), (_excludes), \
            (_allow_erasing), (_clean_deps), (_error));                 \
        if ((_error)) { TDNFTransactionPlanStateClear((_tdnf)->pTransactionPlanState); (_error) = _terminal_error; goto error; } \
        (_error) = _terminal_error;                                      \
        goto error;                                                      \
    } while (0)

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN TDNF_TRANSACTION_PLAN_REQUEST_TRACE *
TDNFTransactionPlanRequestTraceCreate(
    uint32_t alter_type,
    const char *const *subjects,
    uint32_t subject_count
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN TDNF_TRANSACTION_PLAN_REQUEST_TRACE *
TDNFTransactionPlanRequestTraceCreateHistory(void);

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceDestroy(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceRecordGoalRange(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *ids,
    uint32_t start,
    uint32_t end,
    uint32_t alter_type,
    uint32_t reason,
    uint32_t request_ref
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
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

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceRecordRequestOutcome(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t request_ref,
    uint32_t outcome
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceCommitGoal(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    int32_t selection_id,
    uint32_t alter_type,
    const int32_t *queue,
    uint32_t start,
    uint32_t end
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
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

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceRecordPackageJobRange(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *queue,
    uint32_t start,
    uint32_t end,
    uint32_t action,
    uint32_t reason,
    uint32_t request_ref
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
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

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceRecordAllJob(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    uint32_t queue_pair_index,
    uint32_t action,
    int32_t raw_how,
    uint32_t raw_flags,
    uint32_t reason,
    uint32_t request_ref
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
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

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceRecordPolicies(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const char *const *excludes,
    const char *const *installonly_names,
    const char *const *locked_names,
    const char *const *min_versions,
    const char *const *protected_names,
    uint32_t allow_erasing
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceFinalize(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const int32_t *queue,
    uint32_t element_count,
    int32_t clean_deps_mask,
    int32_t force_best_mask
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN
const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_VIEW *
TDNFTransactionPlanRequestTraceGetView(
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanRequestTraceGetError(
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceTestFailNextCreate(void);

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceTestFailNextRecord(void);

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN uint32_t
TDNFTransactionPlanRequestTraceCaptureFactsCreate(
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE *trace,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_PACKAGE_REF *package_refs,
    uint32_t package_ref_count,
    const TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_FACTS **facts,
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER **owner
    );

TDNF_TRANSACTION_PLAN_CAPTURE_HIDDEN void
TDNFTransactionPlanRequestTraceCaptureFactsDestroy(
    TDNF_TRANSACTION_PLAN_REQUEST_TRACE_CAPTURE_OWNER *owner
    );

#ifdef __cplusplus
}
#endif

#endif /* _TDNF_CLIENT_TRANSACTION_PLAN_CAPTURE_ABI_INC_ */
