// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinPlatform",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "HanlinPlatformContracts",
            targets: ["HanlinPlatformContracts"]
        )
    ],
    targets: [
        .target(
            name: "HanlinPlatformContracts",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HanlinPlatformContractsTests",
            dependencies: ["HanlinPlatformContracts"]
        )
    ],
    swiftLanguageModes: [.v6]
)
