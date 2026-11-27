// swift-tools-version: 6.2
import PackageDescription

// Original WidgetKit/JSC code imports only the shared native view product.
// React/Core module registration remains in the application product.
let widgetExtensionSettings: [SwiftSetting] = [.unsafeFlags(["-application-extension"])]

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
        .target(name: "HanlinWidgetUI", dependencies: ["HanlinScriptingWidgets"],
                swiftSettings: widgetExtensionSettings),
        .target(name: "HanlinScriptingWidgets", dependencies: [
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform"),
            .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
            .product(name: "HanlinScriptExtensions", package: "HanlinPlatform"),
            .product(name: "HanlinScriptUI", package: "HanlinPlatform"),
            .product(name: "HanlinExpoWidgetNative", package: "HanlinExpoRuntime"),
            .product(name: "HanlinExpoWidgetsExtension", package: "HanlinExpoRuntime"),
            .product(name: "HanlinLocalization", package: "HanlinPresentationSDK")
        ], swiftSettings: widgetExtensionSettings)
    ],
    swiftLanguageModes: [.v6]
)
