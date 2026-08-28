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
        ),
        .library(
            name: "HanlinScriptStore",
            targets: ["HanlinScriptStore"]
        ),
        .library(
            name: "HanlinScriptRuntime",
            targets: ["HanlinScriptRuntime"]
        ),
        .library(
            name: "HanlinScriptingSDK",
            targets: ["HanlinScriptingSDK"]
        ),
        .library(
            name: "HanlinScriptUI",
            targets: ["HanlinScriptUI"]
        ),
        .library(
            name: "HanlinScriptServices",
            targets: ["HanlinScriptServices"]
        ),
        .library(
            name: "HanlinScriptDeviceServices",
            targets: ["HanlinScriptDeviceServices"]
        ),
        .library(
            name: "HanlinScriptExtensions",
            targets: ["HanlinScriptExtensions"]
        ),
        .library(
            name: "HanlinScriptingApplicationRuntime",
            targets: ["HanlinScriptingApplicationRuntime"]
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
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HanlinScriptCompilerTests",
            dependencies: [
                "HanlinScriptCompiler",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ]
        ),
        .target(
            name: "HanlinScriptStore",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts"
            ]
        ),
        .testTarget(
            name: "HanlinScriptStoreTests",
            dependencies: ["HanlinScriptStore"]
        ),
        .target(
            name: "HanlinScriptRuntime",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts"
            ]
        ),
        .testTarget(
            name: "HanlinScriptRuntimeTests",
            dependencies: ["HanlinScriptRuntime"]
        ),
        .target(
            name: "HanlinScriptingSDK",
            dependencies: ["HanlinScriptContracts"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HanlinScriptingSDKTests",
            dependencies: ["HanlinScriptingSDK"]
        ),
        .target(
            name: "HanlinScriptUI",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts"
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HanlinScriptUITests",
            dependencies: ["HanlinScriptUI"]
        ),
        .target(
            name: "HanlinScriptServices",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts"
            ]
        ),
        .testTarget(
            name: "HanlinScriptServicesTests",
            dependencies: ["HanlinScriptServices"]
        ),
        .target(
            name: "HanlinScriptDeviceServices",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptServices"
            ],
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "HanlinScriptDeviceServicesTests",
            dependencies: ["HanlinScriptDeviceServices"]
        ),
        .target(
            name: "HanlinScriptExtensions",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptContracts",
                "HanlinScriptUI"
            ]
        ),
        .testTarget(
            name: "HanlinScriptExtensionsTests",
            dependencies: ["HanlinScriptExtensions"]
        ),
        .target(
            name: "HanlinScriptingApplicationRuntime",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptUI"
            ],
            linkerSettings: [
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "HanlinScriptingApplicationRuntimeTests",
            dependencies: [
                "HanlinPlatformContracts",
                "HanlinScriptingApplicationRuntime"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
