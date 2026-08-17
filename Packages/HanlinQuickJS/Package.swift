// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "HanlinQuickJS",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "HanlinQuickJS", targets: ["CQuickJS"])
    ],
    targets: [
        .target(
            name: "CQuickJS",
            path: "Sources/CQuickJS",
            publicHeadersPath: "include",
            cSettings: [
                .define("QUICKJS_NG_BUILD"),
                .define("_GNU_SOURCE"),
                .unsafeFlags(["-funsigned-char"])
            ]
        )
    ],
    cLanguageStandard: .gnu11
)
