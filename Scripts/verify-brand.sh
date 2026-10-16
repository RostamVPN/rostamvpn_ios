#!/bin/bash
# Copyright 2026 Internet Mastering & Company, Inc.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
PB=/usr/libexec/PlistBuddy

fail() { echo "error: verify-brand: $*" >&2; exit 1; }
get()  { $PB -c "Print :$1" "$PLIST" 2>/dev/null || true; }

[ -f "$PLIST" ] || fail "no processed Info.plist at $PLIST"

for k in BrandID BrandDisplayName BrandAppGroup BrandTunnelBundleID BrandKeychainGroup; do
    v="$(get "$k")"
    [ -n "$v" ] || fail "$k is empty in $PLIST -- Config/Brand.xcconfig not applied"
    case "$v" in *'$('*) fail "$k did not substitute: $v";; esac
done

[ "$(get BrandID)" = "${BRAND_ID}" ] \
    || fail "BrandID in the bundle is '$(get BrandID)' but BRAND_ID is '${BRAND_ID}'"
[ "$(get BrandAppGroup)" = "${BRAND_APP_GROUP}" ] \
    || fail "BrandAppGroup '$(get BrandAppGroup)' != BRAND_APP_GROUP '${BRAND_APP_GROUP}'"

[ "$(get CFBundleShortVersionString)" = "${BRAND_MARKETING_VERSION}" ] \
    || fail "CFBundleShortVersionString '$(get CFBundleShortVersionString)' != BRAND_MARKETING_VERSION '${BRAND_MARKETING_VERSION}'"
[ "$(get CFBundleVersion)" = "${BRAND_BUILD_NUMBER}" ] \
    || fail "CFBundleVersion '$(get CFBundleVersion)' != BRAND_BUILD_NUMBER '${BRAND_BUILD_NUMBER}'"

if [ "${WRAPPER_EXTENSION:-app}" = "app" ]; then
    [ "$(get CFBundleDisplayName)" = "${BRAND_DISPLAY_NAME}" ] \
        || fail "CFBundleDisplayName '$(get CFBundleDisplayName)' != BRAND_DISPLAY_NAME '${BRAND_DISPLAY_NAME}' -- a target-level INFOPLIST_KEY_CFBundleDisplayName in project.pbxproj outranks the xcconfig"
fi

case "${BRAND_TUNNEL_BUNDLE_ID}" in
    "${BRAND_APP_BUNDLE_ID}".*) ;;
    *) fail "BRAND_TUNNEL_BUNDLE_ID '${BRAND_TUNNEL_BUNDLE_ID}' is not prefixed by BRAND_APP_BUNDLE_ID '${BRAND_APP_BUNDLE_ID}'";;
esac

if [ "${PRODUCT_BUNDLE_IDENTIFIER}" = "${BRAND_TUNNEL_BUNDLE_ID}" ]; then
    ROLE=extension
elif [ "${PRODUCT_BUNDLE_IDENTIFIER}" = "${BRAND_APP_BUNDLE_ID}" ]; then
    ROLE=app
else
    fail "PRODUCT_BUNDLE_IDENTIFIER '${PRODUCT_BUNDLE_IDENTIFIER}' is neither BRAND_APP_BUNDLE_ID nor BRAND_TUNNEL_BUNDLE_ID"
fi
[ "$(get CFBundleIdentifier)" = "${PRODUCT_BUNDLE_IDENTIFIER}" ] \
    || fail "CFBundleIdentifier '$(get CFBundleIdentifier)' != PRODUCT_BUNDLE_IDENTIFIER '${PRODUCT_BUNDLE_IDENTIFIER}'"

if [ "$ROLE" = app ]; then
    [ -n "$(get BrandCashierBase)" ] || fail "BrandCashierBase is empty on the app target"

    case "$(get BrandStyle)" in
        classic|rings|value|tabs) ;;
        "") fail "BrandStyle is empty -- BRAND_STYLE did not substitute; the brand would silently render classic";;
        *)  fail "BrandStyle is '$(get BrandStyle)', which has no renderer. Known: classic rings value tabs";;
    esac
    case "$(get BrandMarkScale)" in
        ''|*[!0-9.]*) fail "BrandMarkScale is '$(get BrandMarkScale)' -- must be a positive number";;
    esac
    for k in BrandCashierBase BrandSiteURL; do
        v="$(get "$k")"
        [ -z "$v" ] && continue
        case "$v" in
            http://*|https://*) ;;
            *) fail "$k is '$v' -- a URL lost its slashes. In an xcconfig write it as https:/\$()/host";;
        esac
    done
    [ -n "$(get BrandStoreKitIDs)" ] \
        || echo "warning: verify-brand: ${BRAND_ID} has no StoreKit product ids; the paywall will say plans are unavailable"

    CFG="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/default-config.json"
    if [ "${BRAND_BUNDLED_CONFIG:-NO}" = "YES" ]; then
        [ -f "$CFG" ] || fail "BRAND_BUNDLED_CONFIG is YES but the bundle has no default-config.json. Re-run gen-ios.py and Scripts/select-brand.sh ${BRAND_ID}."
        GOT="$(shasum -a 256 "$CFG" | cut -d' ' -f1)"
        [ -n "${BRAND_BUNDLED_CONFIG_SHA256:-}" ] \
            || fail "BRAND_BUNDLED_CONFIG is YES but BRAND_BUNDLED_CONFIG_SHA256 is empty; Config/Brand.xcconfig is stale."
        [ "$GOT" = "${BRAND_BUNDLED_CONFIG_SHA256}" ] \
            || fail "the bundled default-config.json is $GOT but ${BRAND_ID} expects ${BRAND_BUNDLED_CONFIG_SHA256}. This is ANOTHER BRAND'S POLICY, or a hand edit. Re-run Scripts/select-brand.sh ${BRAND_ID}."
    else
        if [ -f "$CFG" ]; then
            fail "${BRAND_ID} declares no bundled config (BRAND_BUNDLED_CONFIG=NO) but one is in the bundle. It is almost certainly another brand's, left by a previous Scripts/select-brand.sh. Re-run it for ${BRAND_ID}."
        fi
    fi

    CAR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Assets.car"
    if [ -f "$CAR" ]; then
        NAMES="$(xcrun --sdk iphoneos assetutil --info "$CAR" 2>/dev/null | grep -o '"Name" : "[^"]*"' | sed 's/.*: "//;s/"//' | sort -u)"
        for img in AppIcon LaunchGradient LaunchLogo BrandMascot; do
            echo "$NAMES" | grep -qx "$img" || fail "the asset catalog has no '$img'. A missing image renders as NOTHING at runtime, with no error."
        done
        if [ "$(get BrandHasMascot)" = "YES" ]; then
            echo "$NAMES" | grep -qx BrandDialMark \
                || fail "BrandHasMascot is YES but the catalog has no 'BrandDialMark'. The connect dial would draw a blank ring."
        fi
    else
        echo "warning: verify-brand: no Assets.car at $CAR; skipped the image check"
    fi
fi

echo "verify-brand: ${BRAND_ID} ${ROLE} ${PRODUCT_BUNDLE_IDENTIFIER} ${BRAND_MARKETING_VERSION} (${BRAND_BUILD_NUMBER})"
mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
date > "${SCRIPT_OUTPUT_FILE_0}"
