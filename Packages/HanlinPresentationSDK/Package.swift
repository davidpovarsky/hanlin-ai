// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinPresentationSDK",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "HanlinPresentationKit", targets: ["HanlinPresentationKit"]),
        .library(name: "HanlinRichUI", targets: ["HanlinRichUI"]),
        .library(name: "HanlinChatUI", targets: ["HanlinChatUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/davidpovarsky/hanlin-streaming-markdown",
                 revision: "6bde022876ef4af738c154b3d5c871984ef76195")
    ],
    targets: [
        .target(name: "HanlinPresentationKit"),
        .target(name: "HanlinRichUI", dependencies: ["HanlinPresentationKit"],
                resources: [.copy("Resources/OpenUI")]),
        .target(name: "HanlinChatUI", dependencies: ["HanlinPresentationKit", "HanlinRichUI",
                .product(name: "SwiftStreamingMarkdown", package: "hanlin-streaming-markdown",
                         condition: .when(platforms: [.iOS]))]),
        .testTarget(name: "HanlinPresentationKitTests", dependencies: ["HanlinPresentationKit"])
    ],
    swiftLanguageModes: [.v6]
)
