// swift-tools-version: 5.9
// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

let package = Package(
    name: "rostam-apple",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "RostamKit", targets: ["RostamKit"]),
        .library(name: "RostamKitExtension", targets: ["RostamKit"]),
    ],
    targets: [
        .binaryTarget(
            name: "RedSocketCore",
            path: "RedSocketCore.xcframework"
        ),

        .binaryTarget(
            name: "WgtcpCore",
            path: "WgtcpCore.xcframework"
        ),
        .target(
            name: "RostamKit",
            dependencies: ["RedSocketCore", "WgtcpCore"],
            path: "Sources/RostamKit",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .testTarget(
            name: "RostamKitTests",
            dependencies: ["RostamKit"],
            path: "Tests/RostamKitTests"
        ),
    ]
)
