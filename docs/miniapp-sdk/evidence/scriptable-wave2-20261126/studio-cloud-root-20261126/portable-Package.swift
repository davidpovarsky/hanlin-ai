// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MiniAppsStudioCloudRootProof", products: [.library(name: "HanlinMiniApps", targets: ["HanlinMiniApps"])], targets: [.target(name: "HanlinMiniApps"), .testTarget(name: "HanlinMiniAppsTests", dependencies: ["HanlinMiniApps"])], swiftLanguageModes: [.v6])
