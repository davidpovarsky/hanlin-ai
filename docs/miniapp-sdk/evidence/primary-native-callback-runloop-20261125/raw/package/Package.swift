// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "HanlinNativeMainRunLoopProof",
    platforms: [.macOS(.v13)],
    products: [],
    targets: [
        .target(name: "HanlinNativeScriptCoreSupport", path: "Sources/HanlinNativeScriptCoreSupport", publicHeadersPath: "include"),
        .testTarget(name: "NativeScriptMainRunLoopCallbackTests", dependencies: ["HanlinNativeScriptCoreSupport"], path: "Tests")
    ],
    swiftLanguageModes: [.v6]
)
