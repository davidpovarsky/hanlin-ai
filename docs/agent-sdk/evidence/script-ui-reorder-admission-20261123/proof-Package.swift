// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinScriptUIReorderProof",
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinScriptUI", dependencies: ["HanlinPlatformContracts"]),
        .executableTarget(name: "Reproduce", dependencies: ["HanlinScriptUI"]),
        .testTarget(name: "HanlinScriptUITests", dependencies: ["HanlinScriptUI", "HanlinPlatformContracts"])
    ], swiftLanguageModes: [.v6])
