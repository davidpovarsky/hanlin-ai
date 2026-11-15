// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinProductSplit",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [.library(name: "HanlinProductSplit", targets: ["HanlinProductSplit"])],
    dependencies: [.package(path: "../HanlinPlatform")],
    targets: [
        .target(
            name: "HanlinProductSplit",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ],
            exclude: ["SplitFixtureStore.swift"]
        ),
        .testTarget(
            name: "RegisteredIntegrationTests",
            dependencies: [
                "HanlinProductSplit",
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ],
            path: "Tests/RegisteredIntegrationTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
