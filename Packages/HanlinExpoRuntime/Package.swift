// swift-tools-version: 6.2

import PackageDescription

let packageRoot = Context.packageDirectory

let package = Package(
    name: "HanlinExpoRuntime",
    platforms: [.iOS("27.0")],
    products: [
        .library(name: "HanlinExpoWidgetNative", targets: ["HanlinExpoWidgetNative"]),
        .library(
            name: "HanlinExpoRuntime",
            targets: ["HanlinExpoRuntime"]
        )
    ],
    dependencies: [
        .package(name: "HanlinExpoNativeAPI", path: "../HanlinExpoNativeAPI")
    ],
    targets: [
        .target(
            name: "HanlinExpoWidgetNative",
            dependencies: ["ExpoUI", "ExpoModulesCore", "ExpoModulesWorklets", "ExpoModulesJSI", "ReactNativeHeaders"],
            exclude: ["LICENSE-EXPO.txt"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.linkedFramework("SwiftUI"), .linkedFramework("WidgetKit")]
        ),
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
                "ExpoBrownfield",
                .product(name: "HanlinExpoNativeAPI", package: "HanlinExpoNativeAPI")
            ],
            path: "Sources/HanlinExpoRuntime",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=gnu++20",
                    "-Xcc", "-DREACT_NATIVE_PRODUCTION=1",
                    "-Xcc", "-DRN_DEBUG_STRING_CONVERTIBLE=0",
                    "-Xcc", "-Wno-quoted-include-in-framework-header",
                    "-Xcc", "-Wno-non-modular-include-in-framework-module",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/include",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/bridge",
                    "-Xcc", "-F\(packageRoot)/Artifacts/ModularFrameworks",
                    "-Xcc", "-F../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xcc", "-FArtifacts/ModularFrameworks",
                    "-Xcc", "-FPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xcc", "-I\(packageRoot)/Artifacts/ReactModularHeaders",
                    "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-Xcc", "-IArtifacts/ReactModularHeaders",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-Xcc", "-I\(packageRoot)/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-I\(packageRoot)/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-I\(packageRoot)/Artifacts/ReactNativeDependencies.xcframework/Headers",
                    "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers",
                    "-Xcc", "-IArtifacts/ReactNativeDependencies.xcframework/Headers",
                    "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers"
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
