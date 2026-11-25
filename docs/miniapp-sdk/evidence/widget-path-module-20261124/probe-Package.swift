// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "WidgetPathBoundaryProbe", targets: [
        .target(
            name: "HanlinPlatformContracts",
            path: "Packages/HanlinPlatform/Sources/HanlinPlatformContracts",
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-application-extension"], .when(platforms: [.iOS]))],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension"], .when(platforms: [.iOS]))]
        ),
])
