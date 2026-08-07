/*
 * Copyright (C) 2020-2023 VMware, Inc. All Rights Reserved.
 *
 * Licensed under the GNU Lesser General Public License v2.1 (the "License");
 * you may not use this file except in compliance with the License. The terms
 * of the License are located in the COPYING file of this distribution.
 */

#include "includes.h"

#include "../llconf/nodes.h"
#include "../llconf/modules.h"
#include "../llconf/entry.h"
#include "../llconf/ini.h"

typedef struct _TDNF_BUILTIN_PLUGIN_DESC
{
    const char *pszName;
    int nKind;
} TDNF_BUILTIN_PLUGIN_DESC;

static const TDNF_BUILTIN_PLUGIN_DESC gBuiltins[] =
{
    {"tdnfmetalink", TDNF_BUILTIN_PLUGIN_METALINK},
    {"tdnfrepogpgcheck", TDNF_BUILTIN_PLUGIN_REPOGPGCHECK},
};

static void
TDNFShowPluginError(
    PTDNF_PLUGIN pPlugin,
    uint32_t dwError
    );

static uint32_t
TDNFLoadPluginConfig(
    const char *pszConfigFile,
    const TDNF_BUILTIN_PLUGIN_DESC *pDesc,
    PTDNF_PLUGIN *ppPlugin
    )
{
    uint32_t dwError = 0;
    PTDNF_PLUGIN pPlugin = NULL;
    struct cnfnode *cn_conf = NULL;
    struct cnfnode *cn_section = NULL;
    struct cnfnode *cn = NULL;
    struct cnfmodule *mod_ini = NULL;

    if (IsNullOrEmptyString(pszConfigFile) || !pDesc || !ppPlugin)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if (access(pszConfigFile, F_OK))
    {
        if (errno == ENOENT)
        {
            goto cleanup;
        }
        dwError = errno;
        BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
    }

    mod_ini = find_cnfmodule("ini");
    if (!mod_ini)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    cn_conf = cnfmodule_parse_file(mod_ini, pszConfigFile);
    if (!cn_conf)
    {
        if (errno)
        {
            dwError = errno;
            BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
        }
        dwError = ERROR_TDNF_CONF_FILE_LOAD;
        BAIL_ON_TDNF_ERROR(dwError);
    }

    dwError = TDNFAllocateMemory(1, sizeof(*pPlugin), (void **)&pPlugin);
    BAIL_ON_TDNF_ERROR(dwError);
    dwError = TDNFAllocateString(pDesc->pszName, &pPlugin->pszName);
    BAIL_ON_TDNF_ERROR(dwError);
    pPlugin->nKind = pDesc->nKind;

    for (cn_section = cn_conf->first_child;
         cn_section;
         cn_section = cn_section->next)
    {
        if (cn_section->name[0] == '.' ||
            strcmp(cn_section->name, TDNF_PLUGIN_CONF_MAIN_SECTION))
        {
            continue;
        }
        for (cn = cn_section->first_child; cn; cn = cn->next)
        {
            if (cn->name[0] == '.' || !cn->value)
            {
                continue;
            }
            if (!strcmp(cn->name, TDNF_PLUGIN_CONF_KEY_ENABLED))
            {
                pPlugin->nEnabled = isTrue(cn->value);
            }
        }
    }

    *ppPlugin = pPlugin;
    pPlugin = NULL;

cleanup:
    if (cn_conf)
    {
        destroy_cnfnode(cn_conf);
    }
    if (pPlugin)
    {
        TDNF_SAFE_FREE_MEMORY(pPlugin->pszName);
        TDNFFreeMemory(pPlugin);
    }
    return dwError;

error:
    goto cleanup;
}

static uint32_t
TDNFLoadPluginConfigs(
    PTDNF pTdnf,
    PTDNF_PLUGIN *ppPlugins
    )
{
    uint32_t dwError = 0;
    size_t i = 0;
    PTDNF_PLUGIN pPlugins = NULL;
    PTDNF_PLUGIN pLast = NULL;
    PTDNF_PLUGIN pPlugin = NULL;
    char *pszConfig = NULL;

    if (!pTdnf || !ppPlugins)
    {
        dwError = ERROR_TDNF_INVALID_PARAMETER;
        BAIL_ON_TDNF_ERROR(dwError);
    }
    if (access(pTdnf->pConf->pszPluginConfPath, F_OK))
    {
        if (errno == ENOENT)
        {
            dwError = ERROR_TDNF_NO_PLUGIN_CONF_DIR;
            BAIL_ON_TDNF_ERROR(dwError);
        }
        dwError = errno;
        BAIL_ON_TDNF_SYSTEM_ERROR(dwError);
    }

    for (i = 0; i < ARRAY_SIZE(gBuiltins); ++i)
    {
        dwError = TDNFAllocateStringPrintf(
                      &pszConfig,
                      "%s/%s%s",
                      pTdnf->pConf->pszPluginConfPath,
                      gBuiltins[i].pszName,
                      TDNF_PLUGIN_CONF_EXT);
        BAIL_ON_TDNF_ERROR(dwError);
        dwError = TDNFLoadPluginConfig(pszConfig, &gBuiltins[i], &pPlugin);
        BAIL_ON_TDNF_ERROR(dwError);
        TDNF_SAFE_FREE_MEMORY(pszConfig);

        if (!pPlugin)
        {
            continue;
        }
        if (!pPlugins)
        {
            pPlugins = pLast = pPlugin;
        }
        else
        {
            pLast->pNext = pPlugin;
            pLast = pPlugin;
        }
        pPlugin = NULL;
    }

    *ppPlugins = pPlugins;
    pPlugins = NULL;

cleanup:
    TDNF_SAFE_FREE_MEMORY(pszConfig);
    TDNFFreePlugins(pPlugins);
    return dwError;

error:
    goto cleanup;
}

static uint32_t
TDNFAlterPluginState(
    PTDNF_PLUGIN pPlugins,
    int nEnable,
    const char *pszName
    )
{
    int nIsGlob = 0;
    PTDNF_PLUGIN pPlugin = NULL;

    if (!pPlugins || IsNullOrEmptyString(pszName))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    nIsGlob = TDNFIsGlob(pszName);
    for (pPlugin = pPlugins; pPlugin; pPlugin = pPlugin->pNext)
    {
        int nMatch = nIsGlob
            ? !fnmatch(pszName, pPlugin->pszName, 0)
            : !strcmp(pPlugin->pszName, pszName);
        if (nMatch)
        {
            pPlugin->nEnabled = nEnable;
            if (!nIsGlob)
            {
                break;
            }
        }
    }
    return 0;
}

static uint32_t
TDNFApplyPluginOverrides(
    PTDNF pTdnf,
    PTDNF_PLUGIN pPlugins
    )
{
    uint32_t dwError = 0;
    struct cnfnode *cn = NULL;

    for (cn = pTdnf->pArgs->cn_setopts->first_child; cn; cn = cn->next)
    {
        if (!strcmp(cn->name, "enableplugin"))
        {
            dwError = TDNFAlterPluginState(pPlugins, 1, cn->value);
            BAIL_ON_TDNF_ERROR(dwError);
        }
        else if (!strcmp(cn->name, "disableplugin"))
        {
            dwError = TDNFAlterPluginState(pPlugins, 0, cn->value);
            BAIL_ON_TDNF_ERROR(dwError);
        }
    }

error:
    return dwError;
}

static uint32_t
TDNFInitPlugin(
    PTDNF pTdnf,
    PTDNF_PLUGIN pPlugin
    )
{
    uint32_t dwError = 0;

    if (pPlugin->nKind == TDNF_BUILTIN_PLUGIN_METALINK)
    {
        dwError = BuiltinMetalinkCreate(pTdnf, &pPlugin->pHandle);
    }
    else
    {
        dwError = BuiltinRepoGPGCheckCreate(pTdnf, &pPlugin->pHandle);
    }
    if (dwError)
    {
        TDNFShowPluginError(pPlugin, dwError);
        return dwError;
    }
    pr_info("Loaded plugin: %s\n", pPlugin->pszName);
    return 0;
}

uint32_t
TDNFLoadPlugins(
    PTDNF pTdnf
    )
{
    uint32_t dwError = 0;
    PTDNF_PLUGIN pPlugins = NULL;
    PTDNF_PLUGIN pPlugin = NULL;

    if (!pTdnf || !pTdnf->pArgs)
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    if (!pTdnf->pConf->nPluginsEnabled ||
        find_child(pTdnf->pArgs->cn_setopts, TDNF_CONF_KEY_NO_PLUGINS))
    {
        return 0;
    }

    dwError = TDNFLoadPluginConfigs(pTdnf, &pPlugins);
    if (dwError == ERROR_TDNF_NO_PLUGIN_CONF_DIR)
    {
        return 0;
    }
    BAIL_ON_TDNF_ERROR(dwError);
    if (pPlugins)
    {
        dwError = TDNFApplyPluginOverrides(pTdnf, pPlugins);
        BAIL_ON_TDNF_ERROR(dwError);
    }
    for (pPlugin = pPlugins; pPlugin; pPlugin = pPlugin->pNext)
    {
        if (!pPlugin->nEnabled)
        {
            continue;
        }
        dwError = TDNFInitPlugin(pTdnf, pPlugin);
        BAIL_ON_TDNF_ERROR(dwError);
    }

    pTdnf->pPlugins = pPlugins;
    pPlugins = NULL;

cleanup:
    TDNFFreePlugins(pPlugins);
    return dwError;

error:
    goto cleanup;
}

void
TDNFFreePlugins(
    PTDNF_PLUGIN pPlugins
    )
{
    PTDNF_PLUGIN pNext = NULL;

    while (pPlugins)
    {
        pNext = pPlugins->pNext;
        if (pPlugins->pHandle)
        {
            if (pPlugins->nKind == TDNF_BUILTIN_PLUGIN_METALINK)
            {
                BuiltinMetalinkDestroy(pPlugins->pHandle);
            }
            else
            {
                BuiltinRepoGPGCheckDestroy(pPlugins->pHandle);
            }
        }
        TDNF_SAFE_FREE_MEMORY(pPlugins->pszName);
        TDNFFreeMemory(pPlugins);
        pPlugins = pNext;
    }
}

uint32_t
BuiltinPluginsRepoConfig(
    PTDNF pTdnf,
    const struct cnfnode *pSection
    )
{
    uint32_t dwError = 0;
    PTDNF_PLUGIN pPlugin = NULL;

    if (!pTdnf || !pSection)
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    for (pPlugin = pTdnf->pPlugins; pPlugin; pPlugin = pPlugin->pNext)
    {
        if (!pPlugin->nEnabled)
        {
            continue;
        }
        dwError = pPlugin->nKind == TDNF_BUILTIN_PLUGIN_METALINK
            ? BuiltinMetalinkRepoConfig(pPlugin->pHandle, pSection)
            : BuiltinRepoGPGCheckRepoConfig(pPlugin->pHandle, pSection);
        if (dwError)
        {
            TDNFShowPluginError(pPlugin, dwError);
            return dwError;
        }
    }
    return 0;
}

uint32_t
BuiltinPluginsRepoMDDownloadStart(
    PTDNF pTdnf,
    const char *pszRepoId,
    const char *pszRepoDataDir
    )
{
    uint32_t dwError = 0;
    PTDNF_PLUGIN pPlugin = NULL;

    if (!pTdnf || IsNullOrEmptyString(pszRepoId) ||
        IsNullOrEmptyString(pszRepoDataDir))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    for (pPlugin = pTdnf->pPlugins; pPlugin; pPlugin = pPlugin->pNext)
    {
        if (!pPlugin->nEnabled ||
            pPlugin->nKind != TDNF_BUILTIN_PLUGIN_METALINK)
        {
            continue;
        }
        dwError = BuiltinMetalinkRepoMDDownloadStart(
                      pPlugin->pHandle,
                      pszRepoId,
                      pszRepoDataDir);
        if (dwError)
        {
            TDNFShowPluginError(pPlugin, dwError);
            return dwError;
        }
    }
    return 0;
}

uint32_t
BuiltinPluginsRepoMDDownloadEnd(
    PTDNF pTdnf,
    const char *pszRepoId,
    const char *pszRepoMDFile
    )
{
    uint32_t dwError = 0;
    PTDNF_PLUGIN pPlugin = NULL;

    if (!pTdnf || IsNullOrEmptyString(pszRepoId) ||
        IsNullOrEmptyString(pszRepoMDFile))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    for (pPlugin = pTdnf->pPlugins; pPlugin; pPlugin = pPlugin->pNext)
    {
        if (!pPlugin->nEnabled)
        {
            continue;
        }
        dwError = pPlugin->nKind == TDNF_BUILTIN_PLUGIN_METALINK
            ? BuiltinMetalinkRepoMDDownloadEnd(
                  pPlugin->pHandle,
                  pszRepoId,
                  pszRepoMDFile)
            : BuiltinRepoGPGCheckRepoMDDownloadEnd(
                  pPlugin->pHandle,
                  pszRepoId,
                  pszRepoMDFile);
        if (dwError)
        {
            TDNFShowPluginError(pPlugin, dwError);
            return dwError;
        }
    }
    return 0;
}

static const char *
TDNFPluginErrorDescription(
    PTDNF_PLUGIN pPlugin,
    uint32_t dwError
    )
{
    if (pPlugin->nKind == TDNF_BUILTIN_PLUGIN_REPOGPGCHECK)
    {
        switch (dwError)
        {
            case 2001: return "unknown error";
            case 2002: return "version failed";
            case 2003: return "failed to verify result";
            case 2004: return "failed to verify signature";
            default: return "unknown error";
        }
    }
    switch (dwError)
    {
        case 2701: return "Failed to parse and create document tree";
        case 2702: return "Root element not found";
        case 2703: return "Missing filename in metalink file";
        case 2704: return "Invalid filename present";
        case 2705: return "Missing file size in metalink file";
        case 2706: return "Missing attribute in hash tag";
        case 2707: return "Missing content in hash tag value";
        case 2708: return "Missing attribute in url tag";
        case 2709: return "Missing content in url tag value";
        default: return "unknown error";
    }
}

static void
TDNFShowPluginError(
    PTDNF_PLUGIN pPlugin,
    uint32_t dwError
    )
{
    const char *pszPrefix = NULL;

    if (!pPlugin || !dwError)
    {
        return;
    }
    pszPrefix = pPlugin->nKind == TDNF_BUILTIN_PLUGIN_METALINK
        ? "metalink plugin error"
        : "repogpgcheck plugin error";
    pr_err(
        "Plugin error: %s: %s\n",
        pszPrefix,
        TDNFPluginErrorDescription(pPlugin, dwError));
}

int
BuiltinRefreshRequested(
    void *pHandle
    )
{
    PTDNF pTdnf = pHandle;
    return pTdnf && pTdnf->pArgs && pTdnf->pArgs->nRefresh;
}

const char *
BuiltinGetEnv(
    const char *pszName
    )
{
    return pszName ? getenv(pszName) : NULL;
}

int
BuiltinFileExists(
    const char *pszPath
    )
{
    return pszPath && access(pszPath, F_OK) == 0;
}

void
BuiltinUnlink(
    const char *pszPath
    )
{
    if (pszPath)
    {
        unlink(pszPath);
    }
}

uint32_t
BuiltinMakeDirs(
    const char *pszPath
    )
{
    return TDNFUtilsMakeDirs(pszPath);
}

uint32_t
BuiltinFindRepo(
    void *pHandle,
    const char *pszRepoId,
    void **ppRepo
    )
{
    return TDNFFindRepoById(pHandle, pszRepoId, (PTDNF_REPO_DATA *)ppRepo);
}

uint32_t
BuiltinDownloadMetalink(
    void *pHandle,
    void *pRepoHandle,
    const char *pszDestination
    )
{
    PTDNF_REPO_DATA pRepo = pRepoHandle;

    if (!pHandle || !pRepo || IsNullOrEmptyString(pRepo->pszMetaLink) ||
        IsNullOrEmptyString(pszDestination))
    {
        return ERROR_TDNF_INVALID_PARAMETER;
    }
    return TDNFDownloadFile(
               pHandle,
               pRepo,
               pRepo->pszMetaLink,
               pszDestination,
               pRepo->pszId);
}

uint32_t
BuiltinDownloadRepoFile(
    void *pHandle,
    void *pRepo,
    const char *pszLocation,
    const char *pszDestination,
    const char *pszProgress
    )
{
    return TDNFDownloadFileFromRepo(
               pHandle,
               pRepo,
               pszLocation,
               pszDestination,
               pszProgress);
}

void
BuiltinReplaceBaseUrls(
    void *pRepoHandle,
    char **ppszBaseUrls
    )
{
    PTDNF_REPO_DATA pRepo = pRepoHandle;

    if (!pRepo)
    {
        TDNF_SAFE_FREE_STRINGARRAY(ppszBaseUrls);
        return;
    }
    TDNF_SAFE_FREE_STRINGARRAY(pRepo->ppszBaseUrls);
    pRepo->ppszBaseUrls = ppszBaseUrls;
}
