// swift-tools-version: 5.5
// Copyright Sierra

import PackageDescription

let package = Package(
    name: "SierraSDK",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SierraSDK",
            targets: ["SierraSDK"]),
    ],
    dependencies: [],
    targets: [
        // Main SDK target (Swift)
        .target(
            name: "SierraSDK",
            dependencies: [],
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
            dependencies: ["SierraSDK"]),
    ]
)
