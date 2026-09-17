// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinTextStudioMiniApp",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HanlinTextStudioMiniApp", targets: ["HanlinTextStudioMiniApp"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform")
    ],
    targets: [
        .target(
            name: "HanlinTextStudioMiniApp",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ]
        ),
        .testTarget(
            name: "HanlinTextStudioMiniAppTests",
            dependencies: ["HanlinTextStudioMiniApp"]
        )
    ],
    swiftLanguageModes: [.v6]
)
