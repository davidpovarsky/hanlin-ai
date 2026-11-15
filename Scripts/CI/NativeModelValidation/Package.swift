// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinNativeModelCatalog",
    platforms: [.macOS(.v26), .iOS("27.0")],
    products: [.library(name: "HanlinNativeModelCatalog", targets: ["HanlinNativeModelCatalog"])],
    dependencies: [.package(path: "../Packages/HanlinAgentSDK"), .package(path: "../Packages/HanlinPlatform")],
    targets: [
        .target(name: "HanlinNativeModelCatalog", dependencies: [
            .product(name: "HanlinAgentCore", package: "HanlinAgentSDK"),
            .product(name: "HanlinChatCore", package: "HanlinPlatform")
        ]),
        .testTarget(name: "HanlinNativeModelCatalogTests", dependencies: [
            "HanlinNativeModelCatalog", .product(name: "HanlinAgentCore", package: "HanlinAgentSDK"),
            .product(name: "HanlinChatCore", package: "HanlinPlatform")
        ])
    ], swiftLanguageModes: [.v6]
)
