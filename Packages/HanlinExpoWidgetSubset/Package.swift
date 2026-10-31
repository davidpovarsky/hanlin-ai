// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinExpoWidgetSubset",
    platforms: [.iOS("27.0")],
    products: [.library(name: "HanlinExpoWidgetSubset", targets: ["HanlinExpoWidgetSubset"])],
    targets: [.target(name: "HanlinExpoWidgetSubset", swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-application-extension"])])]
)
