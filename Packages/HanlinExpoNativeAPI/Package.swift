// swift-tools-version: 6.2

import PackageDescription

let packageRoot = Context.packageDirectory

let package = Package(
    name: "HanlinExpoNativeAPI",
    platforms: [.iOS("27.0")],
    products: [
        .library(
            name: "HanlinExpoNativeAPI",
            targets: ["HanlinExpoNativeAPI"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HanlinExpoNativeAPI",
            dependencies: [
                "Libffi",
                "ReactNativeHeaders",
                "React",
                "ReactNativeDependencies",
                "hermesvm"
            ],
            path: "Sources/HanlinExpoNativeAPI",
            resources: [
                .process("Artifacts/metadata")
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-Xcc", "-std=gnu++20",
                    "-Xcc", "-DFOLLY_NO_CONFIG",
                    "-Xcc", "-DFOLLY_MOBILE=1",
                    "-Xcc", "-DFOLLY_USE_LIBCPP=1",
                    "-Xcc", "-DTARGET_ENGINE_HERMES=1",
                    "-Xcc", "-DNS_GSD_BACKEND_HERMES=1",
                    "-Xcc", "-DNATIVESCRIPT_REACT_NATIVE=1",
                    "-Xcc", "-Wno-quoted-include-in-framework-header",
                    "-Xcc", "-Wno-non-modular-include-in-framework-module",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/bridge",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/nativescript",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/nativescript/native-api",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/nativescript/native-api/metadata/include",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/nativescript/ios/vendor/libffi/include",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/worklets/Common/cpp",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/worklets/apple",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/generated",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/generated/NativeScriptNativeApiSpec",
                    "-Xcc", "-I\(packageRoot)/Sources/HanlinExpoNativeAPI/generated/rnworklets",
                    "-Xcc", "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xcc", "-FArtifacts/ModularFrameworks",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-Xcc", "-IArtifacts/ReactModularHeaders",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-Xcc", "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers"
                ])
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore")
            ]
        ),
        .binaryTarget(name: "Libffi", path: "Artifacts/Libffi.xcframework"),
        .binaryTarget(name: "ReactNativeHeaders", path: "../HanlinExpoRuntime/Artifacts/ReactNativeHeaders.xcframework"),
        .binaryTarget(name: "React", path: "../HanlinExpoRuntime/Artifacts/React.xcframework"),
        .binaryTarget(name: "ReactNativeDependencies", path: "../HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework"),
        .binaryTarget(name: "hermesvm", path: "../HanlinExpoRuntime/Artifacts/hermesvm.xcframework")
    ],
    swiftLanguageModes: [.v6]
)
