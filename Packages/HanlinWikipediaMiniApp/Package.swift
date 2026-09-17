// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinWikipediaMiniApp",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HanlinWikipediaMiniApp", targets: ["HanlinWikipediaMiniApp"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform")
    ],
    targets: [
        .target(
            name: "HanlinWikipediaMiniApp",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinMiniAppCore", package: "HanlinPlatform")
            ]
        ),
        .testTarget(
            name: "HanlinWikipediaMiniAppTests",
            dependencies: ["HanlinWikipediaMiniApp"]
        )
    ],
    swiftLanguageModes: [.v6]
)
