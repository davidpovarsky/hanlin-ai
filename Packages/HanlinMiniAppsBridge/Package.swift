// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinMiniAppsBridge",
    defaultLocalization: "en",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "HanlinMiniAppsBridge", targets: ["HanlinMiniAppsBridge"]),
        .library(name: "HanlinMiniAppsPicker", targets: ["HanlinMiniAppsPicker"])
    ],
    targets: [
        .target(name: "HanlinMiniAppsBridge"),
        .target(name: "HanlinMiniAppsPicker", dependencies: ["HanlinMiniAppsBridge"],
                resources: [.process("Resources")]),
        .testTarget(name: "HanlinMiniAppsBridgeTests", dependencies: ["HanlinMiniAppsBridge"])
    ],
    swiftLanguageModes: [.v6]
)
