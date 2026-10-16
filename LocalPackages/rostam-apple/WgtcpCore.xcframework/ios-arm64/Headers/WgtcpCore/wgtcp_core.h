/** C ABI of wgtcp-android (the crate's ffi module), written by hand and kept
 *  in step with it. Symbols are prefixed wgtcp_, never rs_: both cores are
 *  linked into the same Network Extension binary. Every char* returned here was
 *  allocated by Rust and MUST be released with wgtcp_free_string. */
#ifndef WGTCP_CORE_H
#define WGTCP_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Start the tunnel, serving SOCKS5 on socks_port. The config JSON carries the
/// keypair and peer. Returns "ok" or "err:<reason>".
char *wgtcp_start(const char *config_json, uint16_t socks_port);

void wgtcp_stop(void);
int wgtcp_is_running(void);

/// Human-readable connection status ("connected", "stopped", "failed: ...").
char *wgtcp_status(void);

/// Generate a WireGuard keypair: "<private_b64>:<public_b64>".
/// The private half is returned deliberately -- WireGuard needs the raw key to
/// run its handshake, so a Keychain-backed key could never be used here.
char *wgtcp_generate_keypair(void);

/// Free any string returned above. NULL is a no-op.
void wgtcp_free_string(char *s);

#ifdef __cplusplus
}
#endif

#endif
