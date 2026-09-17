// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinSefariaMiniApp",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HanlinSefariaMiniApp", targets: ["HanlinSefariaMiniApp"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform")
    ],
    targets: [
        .target(
            name: "HanlinSefariaMiniApp",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ]
        ),
        .testTarget(
            name: "HanlinSefariaMiniAppTests",
            dependencies: ["HanlinSefariaMiniApp"]
        )
    ],
    swiftLanguageModes: [.v6]
)
