// swift-tools-version: 5.9
// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "hev-socks5-tunnel-apple",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v17)
    ],
    products: [
        .library(
            name: "HevSocks5Tunnel",
            targets: ["HevSocks5TunnelWrapper"]
        ),
    ],
    targets: [

        .target(
            name: "HevSocks5TunnelWrapper",
            dependencies: ["CHevSocks5Tunnel"],
            path: "Sources/HevSocks5Tunnel",
            linkerSettings: [
                .unsafeFlags(["-ObjC"]),
            ]
        ),

        .target(
            name: "CHevSocks5Tunnel",
            path: "Sources/CHevSocks5Tunnel",
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/Sources/CHevSocks5Tunnel/out",
                ]),
                .linkedLibrary("hev-socks5-tunnel"),
            ]
        ),
    ]
)
