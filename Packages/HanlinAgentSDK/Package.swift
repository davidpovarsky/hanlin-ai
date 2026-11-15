// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinAgentSDK",
    platforms: [.iOS("27.0"), .macOS(.v26)],
    products: [
        .library(name: "HanlinHostContracts", targets: ["HanlinHostContracts"]),
        .library(name: "HanlinAgentCore", targets: ["HanlinAgentCore"]),
        .library(name: "HanlinPersistenceAdapters", targets: ["HanlinPersistenceAdapters"]),
        .executable(name: "HanlinFixtureHost", targets: ["HanlinFixtureHost"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform"),
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git", revision: "43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6")
    ],
    targets: [
        .target(name: "HanlinHostContracts", dependencies: [.product(name: "HanlinPlatformContracts", package: "HanlinPlatform")]),
        .target(name: "HanlinAgentCore", dependencies: [
            "HanlinHostContracts",
            .product(name: "HanlinChatCore", package: "HanlinPlatform"),
            .product(name: "AISDKProvider", package: "swift-ai-sdk"),
            .product(name: "SwiftAISDK", package: "swift-ai-sdk")
        ]),
        .target(name: "HanlinPersistenceAdapters", dependencies: ["HanlinHostContracts"]),
        .target(name: "HanlinSDKTestFixtures", dependencies: ["HanlinHostContracts"], path: "Tests/Fixtures"),
        .executableTarget(name: "HanlinFixtureHost", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures"], path: "Examples/FixtureHost"),
        .executableTarget(name: "HanlinSDKPortableProof", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures"], path: "Tests/PortableProof"),
        .testTarget(name: "HanlinHostContractsTests", dependencies: ["HanlinHostContracts"]),
        .testTarget(name: "HanlinAgentCoreTests", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures", .product(name: "AISDKProvider", package: "swift-ai-sdk")]),
        .testTarget(name: "HanlinPersistenceAdaptersTests", dependencies: ["HanlinPersistenceAdapters"])
    ],
    swiftLanguageModes: [.v6]
)
