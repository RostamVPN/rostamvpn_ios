/** C ABI of redsocket-http-core (the crate's ffi module), written by hand and
 *  kept in step with it. Every char* returned here was allocated by Rust and
 *  MUST be released with rs_free_string; free(3) on it is undefined behaviour. */
#ifndef REDSOCKET_CORE_H
#define REDSOCKET_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Start the tunnel, serving SOCKS5 on socks_port. Returns "ok:<entry>" or
/// "err:<reason>". Call rs_load_config FIRST.
char *rs_start(uint16_t socks_port);

void rs_stop(void);
bool rs_is_running(void);

/** The SOCKS port actually bound, or 0 when not running.
 *
 *  NOT the port passed to rs_start. The preferred port may be held by another
 *  app, in which case the core binds one the OS picks rather than failing to
 *  start. The tun bridge must use THIS, or it relays into a closed port and the
 *  VPN comes up carrying nothing. */
uint16_t rs_socks_port(void);

/// Install the config JSON. Must precede rs_start: the endpoint list is read once
/// when selection begins.
void rs_load_config(const char *json);

/// Connection status as JSON: {"running":bool,"carrier":string}
char *rs_connection_status(void);

/// Open a sealed config. Returns the JSON, or "err:<reason>" if the signature
/// does not verify. Refusing is the point -- see cfgseal.
char *rs_unseal_config(const char *sealed_b64, const char *cert_sha256_hex);

/// Release any string returned above. Null is accepted and ignored.
void rs_free_string(char *s);

/// Pick a server region ("fra", "lax", ...), or clear it with "" / NULL.
/// Region choice is a PAID feature; the app clears this when the user is not
/// entitled, because the selection is persisted and hiding the picker alone
/// would leave an old choice in force.
void rs_set_region(const char *region);

/// Tell the core whether this install is premium. Endpoint tiers differ by
/// entitlement, so the core cannot infer it.
void rs_set_premium(int premium);

/// Free-tier speed limit in kbps; 0 = unlimited. The APP decides who is limited
/// (paid users and freedom regions never are); the core only enforces it.
void rs_set_rate_limit_kbps(int kbps);

/// Inject the app-owned client id. MUST be called before rs_start.
/// Without it the id the cashier knows and the id the server sees differ, so
/// entitlement cannot be matched to a session.
void rs_set_client_id(const char *cid);

/// Allow or deny the CDN fallback tier. Denied for free users by policy.
void rs_set_cdn_allowed(int allowed);

/// Restrict selection to one protocol; "auto"/"http" clear the filter.
void rs_set_protocol_filter(const char *proto);

/// Label of the endpoint currently carrying traffic, or "".
char *rs_get_active_carrier(void);

/// What selection is doing now ("trying:x", "racing:x|y"), or "".
char *rs_get_race_status(void);

/// Carriers this core can offer, as JSON. Drives the protocol picker.
char *rs_carriers(void);

/// What selection WOULD try, as JSON. Diagnostics only, connects to nothing.
char *rs_run_diagnostics(void);

/// Relay subsystem: off unless the app enables it after its own consent gates.
void rs_set_peer_tag(const char *tag);
void rs_set_peer_route(const char *host, uint16_t port);
void rs_set_peer_zone(const char *tz);
void rs_enable_peer(void);
void rs_disable_peer(void);
void rs_start_peer(uint16_t socks_port);

/// On-device blocklist.
void  rs_set_blocking_enabled(int32_t enabled);
char *rs_set_blocklist(const char *json);
/// Counts and the recent ring; entries carry host, port, category, secs_ago,
/// bits, reason, refused.
char *rs_get_block_stats(void);
char *rs_set_user_rule(const char *host, const char *verdict);
/// {"allow":[...],"deny":[...]} plus an optional "categories_off": <u16>,
/// sent upstream in the {rules} control frame.
char *rs_set_user_rules(const char *json);
char *rs_get_user_rules(void);
void  rs_clear_block_history(void);

/// Brand id for the MUX2 `app` field on capped tunnels and the probe tag
/// prefix. NULL clears it. Call once at startup, before rs_start.
void rs_set_app(const char *app);

/// Downstream control-stream messages ({seq, ts, type, payload}) queued since
/// the last call, as a JSON array, oldest first ("[]" when none). Drains the
/// queue. A {"type":"caps"} note means the exit acknowledged the capabilities;
/// show "Protected" only after it or a "protection" message, never from the
/// OTA flag. Entitlement: decide by payload.state == "paid".
char *rs_drain_notes(void);

#ifdef __cplusplus
}
#endif
#endif
