#pragma once

#include <stdint.h>

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

typedef int32_t TDNF_PKG_ID;

typedef struct _TDNF_PACKAGE_CONTEXT
    TDNF_PACKAGE_CONTEXT, *PTDNF_PACKAGE_CONTEXT;
typedef Repo *PTDNF_REPOSITORY_CONTEXT;

typedef struct _TDNF_PKG_FIELDS
{
    const char *pszName;
    const char *pszArch;
    const char *pszEvr;
    const char *pszRepo;
} TDNF_PKG_FIELDS, *PTDNF_PKG_FIELDS;

#define SYSTEM_REPO_NAME "@System"
#define CMDLINE_REPO_NAME "@cmdline"
#define TDNF_METADATA_COOKIE_LEN 32
#define TDNF_NEVRA_UNINSTALLED 0
#define TDNF_NEVRA_INSTALLED 1

uint32_t
TDNFPackageContextCreate(
    const char *pszCacheDir,
    const char *pszRootDir,
    const char *pszArch,
    const tdnf_rpm_config *pRpmConfig,
    int nIncludeInstalled,
    PTDNF_PACKAGE_CONTEXT *ppContext
    );

void
TDNFPackageContextFree(
    PTDNF_PACKAGE_CONTEXT pContext
    );

const char *
TDNFPackageContextCacheDir(
    const TDNF_PACKAGE_CONTEXT *pContext
    );

const char *
TDNFPackageContextRootDir(
    const TDNF_PACKAGE_CONTEXT *pContext
    );

uint32_t
TDNFPackageContextInitCommandLine(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_REPOSITORY_CONTEXT *ppRepository
    );

uint32_t
TDNFPackageContextResetCommandLine(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_REPOSITORY_CONTEXT *ppRepository
    );

uint32_t
TDNFPackageContextAddRpm(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_REPOSITORY_CONTEXT pRepository,
    const char *pszPath,
    uint32_t *pdwPkgId
    );

uint32_t
TDNFPackageContextGetFields(
    PTDNF_PACKAGE_CONTEXT pContext,
    TDNF_PKG_ID dwPkgId,
    PTDNF_PKG_FIELDS pFields
    );

uint32_t
TDNFPackageContextGetRepoNevra(
    PTDNF_PACKAGE_CONTEXT pContext,
    TDNF_PKG_ID dwPkgId,
    const char **ppszRepo,
    char **ppszNevra
    );

uint32_t
TDNFPackageContextGetInstalledPkgIds(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_ID_LIST pIdList
    );

uint32_t
TDNFPackageContextGetAllPkgIds(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_ID_LIST pIdList
    );

uint32_t
TDNFPackageContextGetRepoDataList(
    PTDNF_PACKAGE_CONTEXT pContext,
    PTDNF_REPO_DATA **pppRepoData,
    uint32_t *pdwCount
    );
