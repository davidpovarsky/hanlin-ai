// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinNativeScriptRuntime",
    platforms: [.iOS("27.0")],
    products: [
        .library(
            name: "HanlinNativeScriptRuntime",
            targets: ["HanlinNativeScriptRuntime"]
        )
    ],
    dependencies: [
        .package(name: "HanlinPlatform", path: "../HanlinPlatform"),
        .package(
            url: "https://github.com/NativeScript/ios-spm.git",
            exact: "9.1.0"
        )
    ],
    targets: [
        .target(
            name: "HanlinNativeScriptCoreSupport",
            dependencies: [
                .product(name: "NativeScript", package: "ios-spm"),
                "TNSWidgets",
                "NSCWinterTC",
            ],
            path: "Sources/HanlinNativeScriptCoreSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit")
            ]
        ),
        .target(
            name: "HanlinNativeScriptRuntime",
            dependencies: ["HanlinNativeScriptCoreSupport", .product(name: "HanlinPlatformContracts", package: "HanlinPlatform")],
            path: "Sources/HanlinNativeScriptRuntime",
            resources: [
                .copy("Resources/NativeScriptSharedRuntime")
            ]
        ),
        // @nativescript/core ships these native frameworks separately from
        // ios-spm. The preparation script derives and stages the pinned assets.
        .binaryTarget(name: "TNSWidgets", path: "Artifacts/TNSWidgets.xcframework"),
        .binaryTarget(name: "NSCWinterTC", path: "Artifacts/NSCWinterTC.xcframework"),
    ],
    swiftLanguageModes: [.v6]
)
