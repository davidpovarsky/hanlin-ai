// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinAgentUIAdapter",
    platforms: [.iOS("18.0"), .macOS(.v15)],
    products: [
        .library(name: "HanlinAgentUIAdapter", targets: ["HanlinAgentUIAdapter"])
    ],
    dependencies: [
        .package(path: "../HanlinPlatform"),
        .package(path: "../../../StreamChatAI-iOS-Demo")
    ],
    targets: [
        .target(
            name: "HanlinAgentUIAdapter",
            dependencies: [
                .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
                .product(name: "HanlinChatCore", package: "HanlinPlatform"),
                .product(name: "AgentUI", package: "StreamChatAI-iOS-Demo")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "HanlinAgentUIAdapterTests",
            dependencies: [
                "HanlinAgentUIAdapter"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
