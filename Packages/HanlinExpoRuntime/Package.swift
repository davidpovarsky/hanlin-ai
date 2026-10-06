// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinExpoRuntime",
    platforms: [.iOS("27.0")],
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
                "ReactNativeHeaders",
                "React",
                "ReactNativeDependencies",
                "hermesvm",
                "ExpoModulesJSI",
                "ExpoModulesCore",
                "ExpoModulesWorklets",
                "ExpoUI",
                "ExpoBrownfield"
            ],
            path: "Sources/HanlinExpoRuntime",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-Wno-quoted-include-in-framework-header",
                    "-Xcc", "-Wno-non-modular-include-in-framework-module",
                    "-Xcc", "-FArtifacts/ModularFrameworks",
                    "-Xcc", "-FPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xcc", "-IArtifacts/ReactModularHeaders",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-IArtifacts/ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers",
                    "-Xcc", "-IArtifacts/ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers/jsinspector-modern",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework/ios-arm64_x86_64-simulator/Headers/jsinspector-modern"
                ])
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .binaryTarget(name: "ReactNativeHeaders", path: "Artifacts/ReactNativeHeaders.xcframework"),
        .binaryTarget(name: "React", path: "Artifacts/React.xcframework"),
        .binaryTarget(name: "ReactNativeDependencies", path: "Artifacts/ReactNativeDependencies.xcframework"),
        .binaryTarget(name: "hermesvm", path: "Artifacts/hermesvm.xcframework"),
        .binaryTarget(name: "ExpoModulesJSI", path: "Artifacts/ExpoModulesJSI.xcframework"),
        .binaryTarget(name: "ExpoModulesCore", path: "Artifacts/ExpoModulesCore.xcframework"),
        .binaryTarget(name: "ExpoModulesWorklets", path: "Artifacts/ExpoModulesWorklets.xcframework"),
        .binaryTarget(name: "ExpoUI", path: "Artifacts/ExpoUI.xcframework"),
        .binaryTarget(name: "ExpoBrownfield", path: "Artifacts/ExpoBrownfield.xcframework"),
    ],
    swiftLanguageModes: [.v6]
)
