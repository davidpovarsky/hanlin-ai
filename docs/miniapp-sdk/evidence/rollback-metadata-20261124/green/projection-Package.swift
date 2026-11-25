// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinStoreLifecycleProjection",
    dependencies: [.package(path: "../dependencies/swift-crypto")],
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinScriptContracts", dependencies: ["HanlinPlatformContracts", .product(name: "Crypto", package: "swift-crypto")], resources: [.process("Resources")]),
        .target(name: "HanlinMiniAppCore", dependencies: ["HanlinPlatformContracts"]),
        .target(name: "HanlinScriptStore", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts", "HanlinMiniAppCore", .product(name: "Crypto", package: "swift-crypto")]),
        .testTarget(name: "HanlinScriptStoreTests", dependencies: ["HanlinScriptStore", "HanlinMiniAppCore", "HanlinScriptContracts", "HanlinPlatformContracts", .product(name: "Crypto", package: "swift-crypto")])
    ], swiftLanguageModes: [.v6])
