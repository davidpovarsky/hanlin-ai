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
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git", revision: "e7bf34111e603ca977becd007dd4e5bb109af857")
    ],
    targets: [
        // Original pinned Swift-JSON sources, with a unique schema module in the A2UI app graph.
        // See Vendor/Swift-JSON/PROVENANCE.json for byte identity and the resource-name adaptation.
        .target(name: "JSON", path: "Vendor/Swift-JSON/Sources/JSON"),
        .target(name: "JSONRegexRuntime", dependencies: ["JSON"], path: "Vendor/Swift-JSON/Sources/JSONRegexRuntime"),
        .target(name: "HanlinExactJSONSchema", dependencies: ["JSON", "JSONRegexRuntime"],
                path: "Vendor/Swift-JSON/Sources/JSONSchema", resources: [.copy("Resources/Draft2020-12")]),
        .target(name: "HanlinHostContracts", dependencies: [.product(name: "HanlinPlatformContracts", package: "HanlinPlatform")]),
        .target(name: "HanlinAgentCore", dependencies: [
            "HanlinHostContracts",
            .product(name: "HanlinChatCore", package: "HanlinPlatform"),
            .product(name: "AISDKProvider", package: "swift-ai-sdk"),
            .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
            "JSON",
            "HanlinExactJSONSchema"
        ]),
        .target(name: "HanlinPersistenceAdapters", dependencies: ["HanlinHostContracts"]),
        .target(name: "HanlinSDKTestFixtures", dependencies: ["HanlinHostContracts"], path: "Tests/Fixtures"),
        .executableTarget(name: "HanlinFixtureHost", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures"], path: "Examples/FixtureHost"),
        .executableTarget(name: "HanlinSDKPortableProof", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures"], path: "Tests/PortableProof"),
        .testTarget(name: "HanlinHostContractsTests", dependencies: ["HanlinHostContracts"]),
        .testTarget(name: "HanlinHostConcurrencyTests", dependencies: ["HanlinHostContracts", .product(name: "HanlinPlatformContracts", package: "HanlinPlatform")],
                    swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "HanlinAgentCoreTests", dependencies: ["HanlinAgentCore", "HanlinPersistenceAdapters", "HanlinSDKTestFixtures", .product(name: "AISDKProvider", package: "swift-ai-sdk")]),
        .testTarget(name: "HanlinPersistenceAdaptersTests", dependencies: ["HanlinPersistenceAdapters"])
    ],
    swiftLanguageModes: [.v6]
)
