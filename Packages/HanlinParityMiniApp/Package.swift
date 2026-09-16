// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinParityMiniApp",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HanlinParityMiniApp", targets: ["HanlinParityMiniApp"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform")
    ],
    targets: [
        .target(
            name: "HanlinParityMiniApp",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ]
        ),
        .testTarget(
            name: "HanlinParityMiniAppTests",
            dependencies: ["HanlinParityMiniApp"]
        )
    ],
    swiftLanguageModes: [.v6]
)
