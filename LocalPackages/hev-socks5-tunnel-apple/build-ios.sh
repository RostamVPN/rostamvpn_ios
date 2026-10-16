#!/bin/bash
# Copyright 2026 Internet Mastering & Company, Inc.
# SPDX-License-Identifier: Apache-2.0

#
# Build hev-socks5-tunnel for iOS
# https://github.com/heiher/hev-socks5-tunnel
#
# Produces: Sources/CHevSocks5Tunnel/out/libhev-socks5-tunnel.a (the library Package.swift links)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
LIB_DIR="$SCRIPT_DIR/Sources/CHevSocks5Tunnel/out"
SOURCE_DIR="$BUILD_DIR/hev-socks5-tunnel"

# iOS SDK paths
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)

echo "╔═══════════════════════════════════════════════════╗"
echo "║  Building hev-socks5-tunnel for iOS               ║"
echo "╚═══════════════════════════════════════════════════╝"

# Clone if not exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "📥 Cloning hev-socks5-tunnel..."
    mkdir -p "$BUILD_DIR"
    git clone --depth 1 https://github.com/heiher/hev-socks5-tunnel.git "$SOURCE_DIR"
fi

cd "$SOURCE_DIR"

# Clean previous builds
make clean 2>/dev/null || true
rm -rf "$BUILD_DIR/arm64-device" "$BUILD_DIR/arm64-sim"

echo ""
echo "🔨 Building for iOS device (arm64)..."
mkdir -p "$BUILD_DIR/arm64-device"
make \
    CC="$(xcrun --sdk iphoneos -f clang)" \
    CFLAGS="-arch arm64 -isysroot $IOS_SDK -miphoneos-version-min=15.0 -fembed-bitcode -O3" \
    LDFLAGS="-arch arm64 -isysroot $IOS_SDK" \
    static

cp libhev-socks5-tunnel.a "$BUILD_DIR/arm64-device/"
make clean

echo ""
echo "🔨 Building for iOS Simulator (arm64)..."
mkdir -p "$BUILD_DIR/arm64-sim"
make \
    CC="$(xcrun --sdk iphonesimulator -f clang)" \
    CFLAGS="-arch arm64 -isysroot $SIM_SDK -miphonesimulator-version-min=15.0 -O3" \
    LDFLAGS="-arch arm64 -isysroot $SIM_SDK" \
    static

cp libhev-socks5-tunnel.a "$BUILD_DIR/arm64-sim/"
make clean

echo ""
echo "📦 Installing static libraries..."
mkdir -p "$LIB_DIR"

# Create fat library (for simple linking, or use xcframework for SPM)
lipo -create \
    "$BUILD_DIR/arm64-device/libhev-socks5-tunnel.a" \
    -output "$LIB_DIR/libhev-socks5-tunnel-device.a"

cp "$BUILD_DIR/arm64-sim/libhev-socks5-tunnel.a" "$LIB_DIR/libhev-socks5-tunnel-sim.a"

# For SPM, just use the device library
cp "$LIB_DIR/libhev-socks5-tunnel-device.a" "$LIB_DIR/libhev-socks5-tunnel.a"

echo ""
echo "✅ Build complete!"
echo ""
echo "📁 Output:"
echo "   $LIB_DIR/libhev-socks5-tunnel.a (device)"
echo "   $LIB_DIR/libhev-socks5-tunnel-sim.a (simulator)"
echo ""
echo "📝 To use:"
echo "   1. Add package to Xcode project"
echo "   2. Link against libhev-socks5-tunnel.a"
