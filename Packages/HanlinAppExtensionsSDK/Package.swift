// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinAppExtensionsSDK",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "HanlinShareExtensionUI", targets: ["HanlinShareExtensionUI"]),
        .library(name: "HanlinNotificationExtension", targets: ["HanlinNotificationExtension"]),
        .library(name: "HanlinTranslationUI", targets: ["HanlinTranslationUI"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform"),
        .package(path: "../HanlinPresentationSDK"),
        .package(path: "../HanlinExpoRuntime")
    ],
    targets: [
        .target(name: "HanlinShareExtensionUI", dependencies: [
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform"),
            .product(name: "HanlinScriptStore", package: "HanlinPlatform"),
            .product(name: "HanlinLocalization", package: "HanlinPresentationSDK")
        ]),
        .target(name: "HanlinNotificationExtension", dependencies: [
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform")
        ]),
        .target(name: "HanlinTranslationUI", dependencies: [
            .product(name: "HanlinExpoWidgetNative", package: "HanlinExpoRuntime"),
            .product(name: "HanlinScriptContracts", package: "HanlinPlatform"),
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform"),
            .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
            .product(name: "HanlinScriptExtensions", package: "HanlinPlatform"),
            .product(name: "HanlinScriptUI", package: "HanlinPlatform"),
            .product(name: "HanlinChatCore", package: "HanlinPlatform"),
            .product(name: "HanlinLocalization", package: "HanlinPresentationSDK")
        ])
    ],
    swiftLanguageModes: [.v6]
)
