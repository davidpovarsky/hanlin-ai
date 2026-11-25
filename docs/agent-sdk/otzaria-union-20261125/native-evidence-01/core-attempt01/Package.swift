// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "OtzariaCoreContinuationProof",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git",
                 revision: "abf0921c6e89e6521cc2b510ff11016b45a0ef08"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")
    ],
    targets: [
        .testTarget(
            name: "SwiftAISDKTests",
            dependencies: [
                .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
                .product(name: "AISDKProvider", package: "swift-ai-sdk"),
                .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
                .product(name: "OpenAICompatibleProvider", package: "swift-ai-sdk")
            ],
            path: "OriginalTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
