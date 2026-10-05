// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TorahLibraryKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
