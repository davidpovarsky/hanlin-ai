// swift-tools-version: 6.2
import PackageDescription

// Validation-only package. Sources and tests are copied byte-for-byte from
// the checked-out app commit by run.sh; no product source is substituted.
let package = Package(
    name: "ComposerValidation",
    platforms: [.iOS(.v26)],
    products: [.library(name: "AI_Hanlin", targets: ["AI_Hanlin"])],
    targets: [
        .target(name: "AI_Hanlin", path: "Sources/AI_Hanlin"),
        .testTarget(name: "AI_HanlinTests", dependencies: ["AI_Hanlin"], path: "Tests/AI_HanlinTests")
    ]
)
