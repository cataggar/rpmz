#ifndef __SOLV_INCLUDES_H__
#define __SOLV_INCLUDES_H__

#include <stdio.h>
#include <stdint.h>
#include <sys/utsname.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>

// libsolv
#include <solv/evr.h>
#include <solv/pool.h>
#include <solv/poolarch.h>
#include <solv/repo.h>
#include <solv/repo_solv.h>
#include <solv/repo_write.h>
#include <solv/solv_xfopen.h>
#include <solv/solver.h>
#include <solv/selection.h>
#include <solv/solverdebug.h>
#include <solv/chksum.h>
#include <solv/policy.h>

#include <tdnf.h>
#include <tdnfrepomd.h>
#include <tdnf-common-defines.h>

#include "../rpmzig/rpmdb.h"

#include "defines.h"
#include "tdnferror.h"
#include "../common/defines.h"
#include "../common/structs.h"
#include "../common/prototypes.h"
#include "../history/history.h"
#include "prototypes.h"

/* Definition of the type solv/prototypes.h leaves opaque. It lives here so
   that only translation units which have already committed to libsolv can
   see the Queue; everyone else gets the incomplete type. */
struct _SolvPackageList
{
    Queue       queuePackages;
};

/* solv/prototypes.h spells the ids it exchanges with client/ as int32_t so
   that its consumers need no libsolv header. That is only sound while the
   two types are interchangeable. Note the signedness check has to be
   `< 0`: `(Id)-1 == (int32_t)-1` holds even for an unsigned Id, because the
   -1 is converted to the unsigned type before the comparison. */
_Static_assert(sizeof(Id) == sizeof(int32_t),
               "libsolv Id must be layout-compatible with int32_t");
_Static_assert((Id)-1 < 0,
               "libsolv Id must be signed like int32_t");

#endif /* __SOLV_INCLUDES_H__ */
