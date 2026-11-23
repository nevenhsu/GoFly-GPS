// GoFly's audited Swift import boundary for idevice, MIT (Jackson Coxson).
// Declarations retain the ABI of pinned upstream; full generated bindings are
// provenance only and MUST NOT be added to a Swift include search path.
#ifndef GOFLY_IDEVICE_H
#define GOFLY_IDEVICE_H
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <sys/socket.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct AdapterHandle AdapterHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;
typedef struct RpPairingFileHandle RpPairingFileHandle;
typedef struct LockdowndClientHandle LockdowndClientHandle;
typedef struct ImageMounterHandle ImageMounterHandle;
typedef struct Cryptex1AssetsHandle Cryptex1AssetsHandle;
typedef struct RemoteServerHandle RemoteServerHandle;
typedef struct LocationSimulationHandle LocationSimulationHandle;
typedef struct IdeviceFfiError {
    int32_t code;
    int32_t sub_code;
    const char *message;
} IdeviceFfiError;
typedef struct InstalledCryptexC {
    char *identifier;
    char *version;
} InstalledCryptexC;
typedef void *plist_t;
typedef enum {
    PLIST_NONE = -1, PLIST_BOOLEAN, PLIST_INT, PLIST_REAL, PLIST_STRING,
    PLIST_ARRAY, PLIST_DICT, PLIST_DATE, PLIST_DATA, PLIST_KEY, PLIST_UID,
    PLIST_NULL
} plist_type;

// Verification-only: no PIN, consent or pair-setup callback exists in this API.
struct IdeviceFfiError *tunnel_create_rppairing_verify_only(
    const struct sockaddr *addr, socklen_t addr_len, const char *hostname,
    struct RpPairingFileHandle *pairing_file,
    struct AdapterHandle **out_adapter,
    struct RsdHandshakeHandle **out_handshake);

void idevice_set_global_timeout(uint64_t secs);
void idevice_data_free(uint8_t *data, uintptr_t len);
void idevice_error_free(struct IdeviceFfiError *err);
struct IdeviceFfiError *rp_pairing_file_read(const char *path, struct RpPairingFileHandle **out);
void rp_pairing_file_free(struct RpPairingFileHandle *handle);
void adapter_free(struct AdapterHandle *handle);
void rsd_handshake_free(struct RsdHandshakeHandle *handle);
struct IdeviceFfiError *lockdownd_connect_rsd(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, struct LockdowndClientHandle **client);
struct IdeviceFfiError *lockdownd_get_value(struct LockdowndClientHandle *client, const char *key, const char *domain, plist_t *out_plist);
void lockdownd_client_free(struct LockdowndClientHandle *handle);
struct IdeviceFfiError *image_mounter_connect_rsd(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, struct ImageMounterHandle **client);
void image_mounter_free(struct ImageMounterHandle *handle);
struct IdeviceFfiError *image_mounter_lookup_image(struct ImageMounterHandle *client, const char *image_type, uint8_t **signature, size_t *signature_len);
struct IdeviceFfiError *image_mounter_mount_personalized_rsd(struct ImageMounterHandle *client, struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, const uint8_t *image, size_t image_len, const uint8_t *trust_cache, size_t trust_cache_len, const uint8_t *build_manifest, size_t build_manifest_len, const void *info_plist, uint64_t unique_chip_id);
struct IdeviceFfiError *cryptex1_assets_load(const char *restore_dir, struct Cryptex1AssetsHandle **handle);
void cryptex1_assets_free(struct Cryptex1AssetsHandle *handle);
struct IdeviceFfiError *cryptexd_install_ddi(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, struct Cryptex1AssetsHandle *assets, struct InstalledCryptexC **installed);
struct IdeviceFfiError *cryptexd_installed_ddi(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, struct InstalledCryptexC **installed);
void cryptexd_free_installed_cryptex(struct InstalledCryptexC *cryptex);
struct IdeviceFfiError *remote_server_connect_rsd(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake, struct RemoteServerHandle **handle);
void remote_server_free(struct RemoteServerHandle *handle);
struct IdeviceFfiError *location_simulation_new(struct RemoteServerHandle *server, struct LocationSimulationHandle **handle);
void location_simulation_free(struct LocationSimulationHandle *handle);
struct IdeviceFfiError *location_simulation_clear(struct LocationSimulationHandle *handle);
struct IdeviceFfiError *location_simulation_set(struct LocationSimulationHandle *client, double latitude, double longitude);
struct IdeviceFfiError *gofly_coredevice_location_clear(struct AdapterHandle *provider, struct RsdHandshakeHandle *handshake);
void plist_free(plist_t plist);
plist_type plist_get_node_type(plist_t node);
const char* plist_get_string_ptr(plist_t node, uint64_t* length);
void plist_get_uint_val(plist_t node, uint64_t * val);

#ifdef __cplusplus
}
#endif
#endif
