// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinWidgetSDK",
    platforms: [.iOS("27.0")],
    products: [.library(name: "HanlinWidgetUI", targets: ["HanlinWidgetUI"])],
    dependencies: [
        .package(path: "../HanlinPlatform"),
        .package(path: "../HanlinPresentationSDK"),
        .package(path: "../HanlinExpoRuntime")
    ],
    targets: [
        .target(name: "HanlinWidgetUI", dependencies: ["HanlinScriptingWidgets"]),
        .target(name: "HanlinScriptingWidgets", dependencies: [
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform"),
            .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
            .product(name: "HanlinScriptExtensions", package: "HanlinPlatform"),
            .product(name: "HanlinScriptUI", package: "HanlinPlatform"),
            .product(name: "HanlinExpoWidgetNative", package: "HanlinExpoRuntime"),
            .product(name: "HanlinLocalization", package: "HanlinPresentationSDK")
        ])
    ],
    swiftLanguageModes: [.v6]
)
