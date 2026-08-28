// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinNativeScriptRuntime",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "HanlinNativeScriptRuntime",
            targets: ["HanlinNativeScriptRuntime"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/NativeScript/ios-spm.git",
            exact: "9.1.0"
        )
    ],
    targets: [
        .target(
            name: "HanlinNativeScriptCoreSupport",
            dependencies: [
                .product(name: "NativeScript", package: "ios-spm")
            ],
            path: "Sources/HanlinNativeScriptCoreSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("UIKit")
            ]
        ),
        .target(
            name: "HanlinNativeScriptRuntime",
            dependencies: ["HanlinNativeScriptCoreSupport"],
            path: "Sources/HanlinNativeScriptRuntime"
        )
    ],
    swiftLanguageModes: [.v6]
)
