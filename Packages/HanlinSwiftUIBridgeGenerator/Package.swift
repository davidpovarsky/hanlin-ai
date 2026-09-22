// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "HanlinSwiftUIBridgeGenerator",
    products: [
        .library(name: "HanlinSwiftUIBridgeCore", targets: ["HanlinSwiftUIBridgeCore"]),
        .executable(name: "hanlin-swiftui-bridge", targets: ["HanlinSwiftUIBridgeGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .target(
            name: "HanlinSwiftUIBridgeCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "HanlinSwiftUIBridgeGenerator",
            dependencies: ["HanlinSwiftUIBridgeCore"]
        ),
        .testTarget(
            name: "HanlinSwiftUIBridgeCoreTests",
            dependencies: ["HanlinSwiftUIBridgeCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
