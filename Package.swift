// swift-tools-version: 5.9
// Copyright Sierra

import PackageDescription

let package = Package(
    name: "SierraSDK",
    platforms: [.iOS(.v15)],
    products: [
        // Chat-only SDK. Chat-only integrations depend on this product alone.
        .library(
            name: "SierraSDK",
            targets: ["SierraSDK"]),
        // Voice add-on. Depends on SierraSDK; adds the native voice conversation UI,
        // audio pipeline, and SVP transport. Contributes a privacy manifest.
        .library(
            name: "SierraSDKVoice",
            targets: ["SierraSDKVoice"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SierraSDK",
            dependencies: [],
            resources: [
              .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .target(
            name: "SierraSDKVoice",
            dependencies: ["SierraSDK"],
            resources: [
              .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "SierraSDKTests",
            dependencies: ["SierraSDK", "SierraSDKVoice"]),
    ]
)
