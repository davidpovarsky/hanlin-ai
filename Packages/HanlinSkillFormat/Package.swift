// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HanlinSkillFormat",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "HanlinSkillFormat", targets: ["HanlinSkillFormat"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", revision: "a27b21e0c81c5bf42049b897a62aaf387e80f279")],
    targets: [
        .target(name: "HanlinSkillFormat", dependencies: [.product(name: "Yams", package: "Yams")],
                cSettings: [.define("YAML_DECLARE_STATIC")]),
        .testTarget(name: "HanlinSkillFormatTests", dependencies: ["HanlinSkillFormat"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
