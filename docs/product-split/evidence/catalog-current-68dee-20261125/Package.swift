// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "HanlinCatalogFocusedControls",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../source/Packages/HanlinPlatform"),
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git", revision: "3f38f1302764635c9991d0d00fd7b12471a5373c")
    ],
    targets: [
        .testTarget(name: "HanlinChatCoreTests", dependencies: [
            .product(name: "HanlinChatCore", package: "HanlinPlatform"),
            .product(name: "AISDKProviderUtils", package: "swift-ai-sdk")
        ])
    ],
    swiftLanguageModes: [.v6]
)
