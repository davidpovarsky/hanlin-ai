// swift-tools-version: 6.2
import PackageDescription

// These targets directly import/re-export ExpoWidgets. Match its actual Clang
// import contract while retaining this package's Swift6 language mode.
// Scripts/SDK/tests/test_widget_cxx_imports.py checks both producer parity and
// the generated unified package/project consumer settings.
let expoPackageRoot = Context.packageDirectory + "/../HanlinExpoRuntime"
let expoWidgetImportSettings: [SwiftSetting] = [
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-Xcc", "-std=gnu++20",
        "-Xcc", "-DREACT_NATIVE_PRODUCTION=1",
        "-Xcc", "-DRN_DEBUG_STRING_CONVERTIBLE=0",
        "-Xcc", "-Wno-quoted-include-in-framework-header",
        "-Xcc", "-Wno-non-modular-include-in-framework-module",
        "-Xcc", "-I\(expoPackageRoot)/../HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/include",
        "-Xcc", "-I\(expoPackageRoot)/../HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/bridge",
        "-Xcc", "-F\(expoPackageRoot)/Artifacts/ModularFrameworks",
        "-Xcc", "-F../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
        "-Xcc", "-FArtifacts/ModularFrameworks",
        "-Xcc", "-FPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks",
        "-Xcc", "-I\(expoPackageRoot)/Artifacts/ReactModularHeaders",
        "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
        "-Xcc", "-IArtifacts/ReactModularHeaders",
        "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactModularHeaders",
        "-Xcc", "-I\(expoPackageRoot)/Artifacts/ModularFrameworks/react.framework/Headers",
        "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
        "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers",
        "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers",
        "-Xcc", "-I\(expoPackageRoot)/Artifacts/ModularFrameworks/react.framework/Headers/react",
        "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
        "-Xcc", "-IArtifacts/ModularFrameworks/react.framework/Headers/react",
        "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ModularFrameworks/react.framework/Headers/react",
        "-Xcc", "-I\(expoPackageRoot)/Artifacts/ReactNativeDependencies.xcframework/Headers",
        "-Xcc", "-I../Packages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers",
        "-Xcc", "-IArtifacts/ReactNativeDependencies.xcframework/Headers",
        "-Xcc", "-IPackages/HanlinExpoRuntime/Artifacts/ReactNativeDependencies.xcframework/Headers"
    ])
]

let package = Package(
    name: "HanlinWidgetSDK",
    platforms: [.iOS("27.0")],
    products: [.library(name: "HanlinWidgetUI", targets: ["HanlinWidgetUI"])],
    dependencies: [
        .package(path: "../HanlinPlatform"),
        .package(path: "../HanlinPresentationSDK"),
        .package(path: "../HanlinExpoRuntime")
    ],
    targets: [
        .target(name: "HanlinWidgetUI", dependencies: ["HanlinScriptingWidgets"],
                swiftSettings: expoWidgetImportSettings),
        .target(name: "HanlinScriptingWidgets", dependencies: [
            .product(name: "HanlinExtensionContracts", package: "HanlinPlatform"),
            .product(name: "HanlinPlatformContracts", package: "HanlinPlatform"),
            .product(name: "HanlinScriptExtensions", package: "HanlinPlatform"),
            .product(name: "HanlinScriptUI", package: "HanlinPlatform"),
            .product(name: "HanlinExpoWidgetNative", package: "HanlinExpoRuntime"),
            .product(name: "HanlinExpoWidgetsOriginal", package: "HanlinExpoRuntime"),
            .product(name: "HanlinLocalization", package: "HanlinPresentationSDK")
        ], swiftSettings: expoWidgetImportSettings)
    ],
    swiftLanguageModes: [.v6]
)
