// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinPresentationSDK",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "HanlinPresentationKit", targets: ["HanlinPresentationKit"]),
        .library(name: "HanlinRichUI", targets: ["HanlinRichUI"]),
        .library(name: "HanlinChatUI", targets: ["HanlinChatUI"]),
        .library(name: "HanlinA2UI", targets: ["HanlinA2UI"])
    ],
    dependencies: [
        .package(url: "https://github.com/davidpovarsky/hanlin-streaming-markdown",
                 revision: "5cbb4b6c950051f98f02a0b0ae56756f5174a9b8"),
        .package(url: "https://github.com/a2ui-project/a2ui",
                 revision: "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"),
        .package(url: "https://github.com/scinfu/SwiftSoup",
                 revision: "bba848db50462894e7fc0891d018dfecad4ef11e")
    ],
    targets: [
        .target(name: "HanlinPresentationKit"),
        .target(name: "HanlinRichUI", dependencies: ["HanlinPresentationKit"],
                resources: [.copy("Resources/OpenUI")]),
        .target(name: "HanlinChatUI", dependencies: ["HanlinPresentationKit", "HanlinRichUI",
                .product(name: "SwiftStreamingMarkdown", package: "hanlin-streaming-markdown",
                         condition: .when(platforms: [.iOS]))],
                resources: [
                    .copy("CodeFences/Resources/HanlinCodeFenceAssets.json"),
                    .copy("CodeFences/Resources/HanlinCodeFenceRenderer.js"),
                    .copy("CodeFences/Resources/HanlinCodeFenceRenderer.css"),
                    .copy("CodeFences/Resources/HanlinCodeFenceRenderer.js.LEGAL.txt"),
                    .copy("CodeFences/Resources/HanlinCodeFenceThirdPartyLicenses.txt")
                ]),
        .target(name: "HanlinA2UI", dependencies: [
            "HanlinPresentationKit",
            .product(name: "A2UISwiftCore", package: "a2ui"),
            .product(name: "A2UISwiftUI", package: "a2ui"),
            .product(name: "BasicCatalog", package: "a2ui"),
            .product(name: "BasicCatalogSwiftUI", package: "a2ui"),
            .product(name: "SwiftSoup", package: "SwiftSoup")
        ]),
        .testTarget(name: "HanlinChatUITests", dependencies: ["HanlinChatUI"]),
        .testTarget(name: "HanlinPresentationKitTests", dependencies: ["HanlinPresentationKit"])
    ],
    swiftLanguageModes: [.v6]
)
