#ifndef __SOLV_DEFINES_H__
#define __SOLV_DEFINES_H__

#include <stdint.h>

/* The interface types between client/ and solv/.

   These live here, rather than in client/, because both sides of the
   boundary are spelled in them and solv/ may not include a client header
   (doc/coding-guidelines.md). client/includes.h already pulls this file
   in, so moving them costs no new include and no new header -- the
   migration ratchet forbids adding one.

   Job-list encoding. tdnf builds its own job list and hands it to the
   native solver in repomd/; libsolv's solver is never invoked -- there is
   no solver_solve() call anywhere in the tree. These values were
   historically spelled with libsolv's SOLVER_* macros from
   <solv/solver.h>, which made client/ depend on a libsolv header for what
   is really tdnf's own wire format between goal.c, the request trace and
   the capture layer.

   The numeric values are reproduced byte-identically and must not change:
   they are recorded in the request trace and matched by exact whole-word
   equality when the job list is read back in
   TDNFGoalBuildNativeSolverJobs(). solv/tdnfpackage.c carries
   _Static_asserts proving the equality against libsolv's SOLVER_* for as
   long as libsolv is still vendored. */
#define TDNF_JOB_SOLVABLE           0x01
#define TDNF_JOB_SOLVABLE_NAME      0x02
#define TDNF_JOB_SOLVABLE_ALL       0x06

#define TDNF_JOB_INSTALL            0x0100
#define TDNF_JOB_ERASE              0x0200
#define TDNF_JOB_UPDATE             0x0300
#define TDNF_JOB_MULTIVERSION       0x0500
#define TDNF_JOB_LOCK               0x0600
#define TDNF_JOB_DISTUPGRADE        0x0700
#define TDNF_JOB_USERINSTALLED      0x0a00
#define TDNF_JOB_ALLOWUNINSTALL     0x0b00
#define TDNF_JOB_JOBMASK            0xff00

#define TDNF_JOB_CLEANDEPS          0x040000
#define TDNF_JOB_FORCEBEST          0x100000

/* Package and string handles.

   libsolv's `Id` is `typedef int` and is used for two unrelated things that
   share the job list: a solvable (package) handle, and an interned string
   id from pool_str2id(). The job list itself is tdnf's own TDNF_ID_LIST,
   which has always stored plain int32_t, so these spellings are local to
   client/ and cost nothing to own.

   The two are given distinct names because mixing them is a live hazard:
   TDNFGoalBuildNativeSolverJobs() discriminates the two spaces purely by
   the job's `how` word (TDNF_JOB_SOLVABLE_NAME selects the string space),
   and nothing in the type system stops a string id being read as a package
   id. A job's operand slot is deliberately polymorphic and stays int32_t.

   solv/tdnfpackage.c static-asserts these against libsolv's Id while it
   is vendored. */
typedef int32_t TDNF_PKG_ID;
typedef int32_t TDNF_STR_ID;

/* The identifying fields behind a package handle. All strings are
   borrowed from the sack; see the accessors in solv/tdnfpackage.c. */
typedef struct _TDNF_PKG_FIELDS
{
    const char *pszName;
    const char *pszArch;
    const char *pszEvr;
    const char *pszRepo;
} TDNF_PKG_FIELDS, *PTDNF_PKG_FIELDS;

#define SYSTEM_REPO_NAME "@System"
#define CMDLINE_REPO_NAME "@cmdline"
#define SOLV_COOKIE_IDENT "tdnf-solv-content-v3"
#define TDNF_SOLVCACHE_DIR_NAME "solvcache"
#define SOLV_COOKIE_LEN   32

#define SOLV_NEVRA_UNINSTALLED 0
#define SOLV_NEVRA_INSTALLED   1

#define BAIL_ON_TDNF_LIBSOLV_ERROR(dwError) \
    do {                                                           \
        if (dwError)                                               \
        {                                                          \
            goto error;                                            \
        }                                                          \
    } while(0)

#endif /* __SOLV_DEFINES_H__ */
