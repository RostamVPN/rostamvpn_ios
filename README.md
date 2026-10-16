# RostamVPN for iOS

The RostamVPN iOS client. `Brands/rostam/` holds the product definition
(identifiers, version, StoreKit ids, theme and assets); the transport cores are
the same Rust crates the Android app ships.

## Targets

| target | what it is |
|---|---|
| `RostamVPN` (scheme `rostamvpn`) | the SwiftUI app |
| `RedSocketTunnel` | the Network Extension (`NEPacketTunnelProvider`) |
| `RostamKit` | SwiftPM library in `LocalPackages/rostam-apple` wrapping `RedSocketCore.xcframework` and `WgtcpCore.xcframework` |

## Build

```
Scripts/select-brand.sh rostam
xcodebuild -workspace rostamvpn.xcworkspace -scheme rostamvpn \
    -configuration Release -sdk iphoneos -derivedDataPath build/rostam build
```

`Scripts/select-brand.sh` must run first. It generates `Config/Brand.xcconfig`
and `rostamvpn/Brand/` from `Brands/rostam/`; both are gitignored, and
`Config/AppCommon.xcconfig` includes the first with a hard `#include`, so a tree
with no brand selected fails to build instead of building with stale values.
There is no CocoaPods step: the app links no pods and has one `Release`
configuration.

`Scripts/verify-brand.sh` runs on both targets and fails the build when the
processed Info.plist disagrees with `Config/Brand.xcconfig`.

## Placeholders

`Brands/rostam/Brand.xcconfig` ships with placeholders that must be filled in
before a real build:

| key | value |
|---|---|
| `BRAND_TEAM_ID` | the Apple Developer team id; also `teamID` in `Config/Export/rostam.plist` for `-exportArchive` |
| `BRAND_CASHIER_BASE` | the cashier host, written as `https:/$()/host` so the xcconfig keeps both slashes |
| `BRAND_LEGAL_OPERATOR` | the legal operator named in the privacy policy |
| `BRAND_WGTCP_API_KEY` | the WGTCP provisioning API key |

The app and the extension must share one App Group; see `Config/Export/README.md`.

## Dependencies

Every Swift package is local, under `LocalPackages/` (`rostam-apple`,
`hev-socks5-tunnel-apple`); nothing is fetched at build time and
`Package.resolved` carries no pins.

The core xcframeworks in `LocalPackages/rostam-apple` are built from
`redsocket-http-core/` (`RedSocketCore`) and `wgtcp-android/` in the rostamvpn-android repository
(`WgtcpCore`) with `cargo build --release` for `aarch64-apple-ios` and
`aarch64-apple-ios-sim`; the static libraries are copied into the xcframework
slices next to the hand-written C headers. The shipped archives were built from
rostamvpn-android commit `82623d9` in a neutral directory with
`--remap-path-prefix` (and `-ffile-prefix-map` for the C objects) so that no
build-host path survives in them; `strings` on each archive finds none.

## Peer relay

The relay in the core is off by default. It runs only when the OTA config's
`probe.enabled` flag is on and the user has opted in on this device; either one
missing keeps it off, and turning the opt-in off disarms a running session.

## Related repositories

| Repository | Contents |
|---|---|
| `redsocket_http` | The exit server (Rust). |
| `rostamvpn-android` | The Android app, the shared Rust client core (`redsocket-http-core/`) and the WireGuard-over-TCP core. |
| `rostamvpn-ios` | The iOS app and its Network Extension; its core frameworks are built from the cores in `rostamvpn-android`. |
| `redsocket_pfe` | AF_XDP triangle-routing front-end. |
| `redsocket_wgtcp` | The userspace WireGuard-over-TCP client library and tools; vendored into `rostamvpn-android` for the Android core. |
| `redsocket_proteus` | The server wrapped in Proteus programmable protocols; intended to replace `redsocket_http` once proven. |

## Removed for publication

Deployment and infrastructure documents, exporter scripts, release artifacts,
signing material and API keys (replaced by `REPLACE_WITH_*` placeholders),
server telemetry other than the cid stats, other brands, narrative comments,
and dead code. All third-party dependencies are vendored in the tree and keep
their own license files.
