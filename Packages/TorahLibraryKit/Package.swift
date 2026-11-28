// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TorahLibraryKit",
    platforms: [
        .macOS(.v26),
        .iOS("27.0")
    ],
    products: [
        .library(
            name: "TorahLibraryKit",
            targets: ["TorahLibraryKit"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TorahLibraryKit",
            dependencies: [],
            path: "Sources/TorahLibraryKit"
        ),
        .testTarget(
            name: "TorahLibraryKitTests",
            dependencies: ["TorahLibraryKit"],
            path: "Tests/TorahLibraryKitTests"
        )
    ]
)
