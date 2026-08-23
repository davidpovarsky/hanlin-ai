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
        ),
        .library(
            name: "HanlinScriptContracts",
            targets: ["HanlinScriptContracts"]
        ),
        .library(
            name: "HanlinScriptCompiler",
            targets: ["HanlinScriptCompiler"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            exact: "0.9.19"
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
        ),
        .target(
            name: "HanlinScriptContracts",
            dependencies: ["HanlinPlatformContracts"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HanlinScriptContractsTests",
            dependencies: ["HanlinScriptContracts"]
        ),
        .target(
            name: "HanlinScriptCompiler",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .testTarget(
            name: "HanlinScriptCompilerTests",
            dependencies: [
                "HanlinScriptCompiler",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
