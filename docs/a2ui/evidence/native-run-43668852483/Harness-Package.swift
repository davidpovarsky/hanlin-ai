// swift-tools-version: 6.1
import PackageDescription

let products: [Target.Dependency] = [
    .product(name: "A2UISwiftCore", package: "a2ui"),
    .product(name: "A2UISwiftUI", package: "a2ui"),
    .product(name: "BasicCatalog", package: "a2ui"),
    .product(name: "BasicCatalogSwiftUI", package: "a2ui"),
]
let enabled: [SwiftSetting] = [
    .define("HANLIN_A2UI_POC", .when(configuration: .debug)),
    .define("DEBUG", .when(configuration: .debug)),
]
let package = Package(
    name: "HanlinA2UIProof",
    platforms: [.macOS("27.0")],
    dependencies: [.package(url: "https://github.com/a2ui-project/a2ui", revision: "3ed9601862ecc78027e20ac80ad8b1b98a5d9079")],
    targets: [
        .target(name: "AI_Hanlin", dependencies: products, swiftSettings: enabled),
        .testTarget(name: "AI_HLYTests", dependencies: ["AI_Hanlin"] + products,
                    resources: [.copy("A2UIFixtures")], swiftSettings: enabled),
    ],
    swiftLanguageModes: [.v6]
)
