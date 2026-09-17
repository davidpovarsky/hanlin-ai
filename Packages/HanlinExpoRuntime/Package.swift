// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinExpoRuntime",
    platforms: [.iOS(.v26)],
    products: [
        .library(
            name: "HanlinExpoRuntime",
            targets: ["HanlinExpoRuntime"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HanlinExpoRuntime",
            dependencies: [
                "React",
                "ReactNativeDependencies",
                "hermesvm",
                "ExpoModulesCore",
                "ExpoModulesWorklets",
                "ExpoUI",
                "ExpoBrownfield"
            ],
            path: "Sources/HanlinExpoRuntime",
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .binaryTarget(name: "React", path: "Artifacts/React.xcframework"),
        .binaryTarget(name: "ReactNativeDependencies", path: "Artifacts/ReactNativeDependencies.xcframework"),
        .binaryTarget(name: "hermesvm", path: "Artifacts/hermesvm.xcframework"),
        .binaryTarget(name: "ExpoModulesCore", path: "Artifacts/ExpoModulesCore.xcframework"),
        .binaryTarget(name: "ExpoModulesWorklets", path: "Artifacts/ExpoModulesWorklets.xcframework"),
        .binaryTarget(name: "ExpoUI", path: "Artifacts/ExpoUI.xcframework"),
        .binaryTarget(name: "ExpoBrownfield", path: "Artifacts/ExpoBrownfield.xcframework"),
    ],
    swiftLanguageModes: [.v6]
)
