// swift-tools-version: 6.2

import PackageDescription

let packageRoot = Context.packageDirectory

let package = Package(
    name: "HanlinExpoNativeAPI",
    platforms: [.iOS("27.0")],
    products: [
        .library(
            name: "HanlinExpoNativeAPI",
            targets: ["HanlinExpoNativeAPI", "HanlinExpoNativeAPICore", "HanlinExpoWorklets"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HanlinExpoNativeAPI",
            dependencies: [
                "HanlinExpoNativeAPICore",
                "HanlinExpoWorklets"
            ],
            path: "Sources/HanlinExpoNativeAPI",
            resources: [
                .process("Resources/metadata")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup"
                ])
            ]
        ),
        .target(
            name: "HanlinExpoWorklets",
            dependencies: [],
            path: "Sources/HanlinExpoWorklets",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=gnu++20",
                    "-fobjc-arc",
                    "-DFOLLY_NO_CONFIG",
                    "-DFOLLY_MOBILE=1",
                    "-DFOLLY_USE_LIBCPP=1",
                    "-DREACT_NATIVE_PRODUCTION=1",
                    "-DRN_DEBUG_STRING_CONVERTIBLE=0",
                    "-DWORKLETS_VERSION=\"0.13.1\"",
                    "-Wno-quoted-include-in-framework-header",
                    "-Wno-non-modular-include-in-framework-module",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/include",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/Common/cpp",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/apple",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/generated",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/generated/rnworklets",
                    "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers"
                ])
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .unsafeFlags([
                    "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup"
                ])
            ]
        ),
        .target(
            name: "HanlinExpoNativeAPICore",
            dependencies: [
                "HanlinExpoWorklets",
                "Libffi"
            ],
            path: "Sources/HanlinExpoNativeAPICore",
            exclude: [
                "nativescript/native-api/ffi/objc/shared",
                "nativescript/native-api/ffi/objc/hermes/NativeApiJsiGsd.mm"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=gnu++20",
                    "-fno-objc-arc",
                    "-DFOLLY_NO_CONFIG",
                    "-DFOLLY_MOBILE=1",
                    "-DFOLLY_USE_LIBCPP=1",
                    "-DFOLLY_CFG_NO_COROUTINES=1",
                    "-DTARGET_ENGINE_HERMES=1",
                    "-DNS_GSD_BACKEND_HERMES=1",
                    "-DNATIVESCRIPT_REACT_NATIVE=1",
                    "-DREACT_NATIVE_PRODUCTION=1",
                    "-DRN_DEBUG_STRING_CONVERTIBLE=0",
                    "-Wno-quoted-include-in-framework-header",
                    "-Wno-non-modular-include-in-framework-module",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/include",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/bridge",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/ios",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/native-api",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/native-api/ffi/objc/hermes",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/native-api/ffi/objc/shared",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/native-api/ffi/objc/shared/bridge",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/native-api/metadata/include",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/nativescript/ios/vendor/libffi/include",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/generated",
                    "-I\(packageRoot)/Sources/HanlinExpoNativeAPICore/generated/NativeScriptNativeApiSpec",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/include",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/Common/cpp",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/apple",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/generated",
                    "-I\(packageRoot)/Sources/HanlinExpoWorklets/generated/rnworklets",
                    "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactModularHeaders",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
                    "-I\(packageRoot)/../HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers"
                ])
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("QuartzCore"),
                .unsafeFlags([
                    "-F\(packageRoot)/../HanlinExpoRuntime/Artifacts/ModularFrameworks",
                    "-Xlinker", "-undefined",
                    "-Xlinker", "dynamic_lookup"
                ])
            ]
        ),
        .binaryTarget(name: "Libffi", path: "Artifacts/Libffi.xcframework")
    ],
    swiftLanguageModes: [.v6]
)
