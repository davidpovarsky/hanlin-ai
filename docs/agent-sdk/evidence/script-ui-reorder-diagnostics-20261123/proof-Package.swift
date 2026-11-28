// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinScriptUIReorderDiagnosticProof",
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinScriptUI", dependencies: ["HanlinPlatformContracts"]),
        .testTarget(name: "HanlinScriptUITests", dependencies: ["HanlinScriptUI", "HanlinPlatformContracts"])
    ], swiftLanguageModes: [.v6])
