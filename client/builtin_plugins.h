#ifndef __TDNF_BUILTIN_PLUGINS_H__
#define __TDNF_BUILTIN_PLUGINS_H__

#include <stddef.h>
#include <stdint.h>

struct cnfnode;

#define TDNF_HASH_MD5 0
#define TDNF_HASH_SHA1 1
#define TDNF_HASH_SHA256 2
#define TDNF_HASH_SHA512 3

uint32_t TDNFAllocateMemory(
    size_t nNumElements,
    size_t nSize,
    void **ppMemory
    );
uint32_t TDNFAllocateString(const char *pszSrc, char **ppszDst);
void TDNFFreeStringArray(char **ppszArray);
uint32_t TDNFCheckHexDigest(const char *pszDigest, int nDigestLen);
uint32_t TDNFChecksumFromHexDigest(
    const char *pszDigest,
    unsigned char *pByteArray
    );
uint32_t TDNFCheckHash(
    const char *pszFile,
    const unsigned char *pDigest,
    int nHashType
    );

int BuiltinRefreshRequested(void *pTdnf);
const char *BuiltinGetEnv(const char *pszName);
int BuiltinFileExists(const char *pszPath);
void BuiltinUnlink(const char *pszPath);
uint32_t BuiltinMakeDirs(const char *pszPath);
uint32_t BuiltinFindRepo(
    void *pTdnf,
    const char *pszRepoId,
    void **ppRepo
    );
uint32_t BuiltinDownloadMetalink(
    void *pTdnf,
    void *pRepo,
    const char *pszDestination
    );
uint32_t BuiltinDownloadRepoFile(
    void *pTdnf,
    void *pRepo,
    const char *pszLocation,
    const char *pszDestination,
    const char *pszProgress
    );
void BuiltinReplaceBaseUrls(void *pRepo, char **ppszBaseUrls);
int rpmzig_verify_detached_armored(
    const unsigned char *pSig,
    size_t nSig,
    const unsigned char *pData,
    size_t nData,
    const unsigned char *const *ppKeys,
    const size_t *pnKeyLengths,
    size_t nKeyCount
    );

#endif
