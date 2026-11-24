// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HanlinPermissionBoundaryProbe",
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinScriptContracts", dependencies: ["HanlinPlatformContracts"], resources: [.process("Resources")]),
        .target(name: "HanlinScriptServices", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts"]),
        .executableTarget(name: "OriginalBoundaryProbe", dependencies: ["HanlinScriptServices", "HanlinPlatformContracts"])
    ],
    swiftLanguageModes: [.v6]
)
