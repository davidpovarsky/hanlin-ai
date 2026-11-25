// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinCacheNativeProof", platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", exact: "2.6.0"),
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git", revision: "abf0921c6e89e6521cc2b510ff11016b45a0ef08")
    ],
    targets: [
        .target(
            name: "HanlinPlatformContracts",
            path: "Packages/HanlinPlatform/Sources/HanlinPlatformContracts",
            resources: [.process("Resources")],
            swiftSettings: [.unsafeFlags(["-application-extension"], .when(platforms: [.iOS]))],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-application_extension"], .when(platforms: [.iOS]))]
        ),
        .target(
            name: "HanlinChatCore",
            dependencies: [.product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"), .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"), .target(name: "HanlinPlatformContracts"), .product(name: "SwiftAISDK", package: "swift-ai-sdk"), .product(name: "AISDKProvider", package: "swift-ai-sdk"), .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"), .product(name: "OpenAIProvider", package: "swift-ai-sdk"), .product(name: "AnthropicProvider", package: "swift-ai-sdk"), .product(name: "GoogleProvider", package: "swift-ai-sdk"), .product(name: "OpenAICompatibleProvider", package: "swift-ai-sdk")],
            path: "Packages/HanlinPlatform/Sources/HanlinChatCore"
        ),
        .testTarget(
            name: "HanlinChatCoreTests",
            dependencies: [.product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"), .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"), .target(name: "HanlinChatCore"), .product(name: "SwiftAISDK", package: "swift-ai-sdk"), .product(name: "AISDKProvider", package: "swift-ai-sdk"), .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"), .product(name: "OpenAIProvider", package: "swift-ai-sdk"), .product(name: "AnthropicProvider", package: "swift-ai-sdk"), .product(name: "GoogleProvider", package: "swift-ai-sdk"), .product(name: "OpenAICompatibleProvider", package: "swift-ai-sdk")],
            path: "Packages/HanlinPlatform/Tests/HanlinChatCoreTests"
        ),
        .testTarget(name: "ProducerPromptCacheTests", dependencies: [.product(name: "SwiftAISDK", package: "swift-ai-sdk"), .product(name: "AISDKProvider", package: "swift-ai-sdk"), .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"), .product(name: "OpenAIProvider", package: "swift-ai-sdk")], path: "ProducerTests")
    ])
