/*
 * The C package-checker keeps error-code policy and user interaction.  This
 * narrow bridge owns no files or buffers: rpmzig receives the parsed file
 * handle, configuration, and complete fresh key set directly.
 */

#include "includes.h"

#include "../rpmzig/verify.h"
#include "gpgcheck_zig.h"

int
TDNFRpmzigVerifyFile(
    tdnf_rpm_file *pRpmFile,
    const tdnf_rpm_config *pRpmConfig,
    const void *const *ppFreshKeys,
    const size_t *pnFreshKeyLengths,
    size_t nFreshKeyCount,
    int *out_status)
{
    return tdnf_rpm_file_verify_signatures_config(
               pRpmFile,
               pRpmConfig,
               ppFreshKeys,
               pnFreshKeyLengths,
               nFreshKeyCount,
               out_status);
}
