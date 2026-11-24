// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ReturnAckSlice", targets: [
    .target(name: "ReturnAckSlice"),
    .testTarget(name: "ReturnAckSliceTests", dependencies: ["ReturnAckSlice"]),
], swiftLanguageModes: [.v6])
