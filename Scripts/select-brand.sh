#!/bin/bash
# Copyright 2026 Internet Mastering & Company, Inc.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

BRAND="${1:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Brands/$BRAND"

if [ -z "$BRAND" ] || [ ! -d "$SRC" ]; then
    echo "usage: Scripts/select-brand.sh <brand>" >&2
    echo "available:" >&2
    for d in "$ROOT"/Brands/*/; do [ -d "$d" ] && echo "  $(basename "$d")" >&2; done
    exit 2
fi

[ -f "$SRC/Brand.xcconfig" ] || { echo "error: $SRC/Brand.xcconfig missing" >&2; exit 1; }

mkdir -p "$ROOT/Config" "$ROOT/rostamvpn/Brand"
cp "$SRC/Brand.xcconfig" "$ROOT/Config/Brand.xcconfig"

cp "$SRC/BrandTheme.swift" "$ROOT/rostamvpn/Brand/BrandTheme.swift"

rm -rf "$ROOT/rostamvpn/Brand/Brand.xcassets"
cp -R "$SRC/Brand.xcassets" "$ROOT/rostamvpn/Brand/Brand.xcassets"

rm -f "$ROOT/rostamvpn/Brand/default-config.json"
if [ -f "$SRC/default-config.json" ]; then
    cp "$SRC/default-config.json" "$ROOT/rostamvpn/Brand/default-config.json"
fi

echo "selected brand: $BRAND"
grep -E '^BRAND_(ID|DISPLAY_NAME|APP_BUNDLE_ID|TUNNEL_BUNDLE_ID|TEAM_ID|MARKETING_VERSION|BUILD_NUMBER|BUNDLED_CONFIG) ' \
    "$ROOT/Config/Brand.xcconfig" | sed 's/^/  /'
if [ -f "$ROOT/rostamvpn/Brand/default-config.json" ]; then
    echo "  boot config      $(shasum -a 256 "$ROOT/rostamvpn/Brand/default-config.json" | cut -c1-16)…"
else
    echo "  boot config      none (ConfigPolicy.Snapshot.fallback until the first fetch)"
fi
echo
echo "next: xcodebuild -workspace rostamvpn.xcworkspace -scheme rostamvpn \\"
echo "        -configuration Release -sdk iphoneos -derivedDataPath build/$BRAND build"
