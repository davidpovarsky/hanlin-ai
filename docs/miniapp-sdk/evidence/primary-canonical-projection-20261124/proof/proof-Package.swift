// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinCanonicalProjectionProof", platforms: [.macOS(.v26)], targets: [
    .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
    .target(name: "HanlinMiniAppCore", dependencies: ["HanlinPlatformContracts"]),
    .target(name: "HanlinScriptContracts", dependencies: ["HanlinPlatformContracts"], resources: [.process("Resources")]),
    .target(name: "HanlinScriptStore", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts", "HanlinMiniAppCore"]),
    .testTarget(name: "HanlinScriptStoreTests", dependencies: ["HanlinScriptStore", "HanlinMiniAppCore"])
])
