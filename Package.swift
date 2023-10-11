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
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SierraSDK",
            resources: [
              .process("Resources")
            ]
        ),
        .testTarget(
            name: "SierraSDKTests",
            dependencies: ["SierraSDK"]),
    ]
)
