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
#include <solv/solvversion.h>

/* Pin the headers to the vendored libsolv that build.zig actually links.
   This is not belt-and-braces: zig cc searches /usr/include before any
   user -isystem directory, so for as long as libsolv's include paths were
   added with -isystem, a host libsolv-devel silently shadowed the
   vendored tree and solv/ was compiled against one set of headers and
   linked against another library. Measured, that mismatch happened to be
   harmless: the public views of 0.7.28 and 0.7.39 agree on every field
   offset tdnf can reach. The declarations this include set pulls in
   differ by ten additions -- eight prototypes, the static inline
   allochashtable, and solv_cookieopen from the ext header -- and one
   removal, stringpool_resize_hash, which nothing here calls (a call
   would fail at link). struct s_Dirpool gained two members in 0.7.39,
   but .dirpool is the last member outside
   LIBSOLV_INTERNAL, so only sizeof(Repodata) (192 vs 208) and
   sizeof(Dirpool) (24 vs 40) differ -- and tdnf only ever holds
   Repodata pointers libsolv allocated. That is luck, it is specific to
   this pair of versions, and nothing would report it if the next .libsolv
   bump stopped it holding.
   build.zig now uses -I, and this assert is what makes an include-path
   regression loud. Know its limit: it fires when the vendored tree is off
   the path, not whenever a host header is in scope. libsolv's guards mean
   a host header winning a lookup *after* a vendored one has its body
   skipped, leaving LIBSOLV_VERSION_PATCH at the vendored value. See the
   known-boundary comment on addLibsolvIncludes in build.zig. */
_Static_assert(LIBSOLV_VERSION_PATCH == TDNF_VENDORED_LIBSOLV_VERSION_PATCH,
               "libsolv headers are not the vendored ones build.zig links; "
               "a host libsolv-devel is shadowing the vendored copy (.libsolv in build.zig.zon)");

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
