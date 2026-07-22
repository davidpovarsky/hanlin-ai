// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "IOSSystemLite",
    platforms: [.iOS(.v26)],
    products: [.library(name: "IOSSystemLite", targets: ["IOSSystemLite"])],
    targets: [
        .target(
            name: "IOSSystemLite",
            dependencies: ["ios_system", "files", "text", "tar", "curl_ios", "libssh2", "openssl", "awk"],
            resources: [.process("Resources")]
        ),
        .binaryTarget(name: "ios_system", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/ios_system.xcframework.zip", checksum: "d429e68102926f58bedd8e8b7105dcd169478cd6da1cef494a5f468482d1c8f5"),
        .binaryTarget(name: "files", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/files.xcframework.zip", checksum: "b0ee1f58c65ba306f178cd559fd6bce79ec8f275280526908c2a992bfcafedd5"),
        .binaryTarget(name: "text", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/text.xcframework.zip", checksum: "6fed763c6e941817b2a2af2051871bdfb8a1af4177fad1ab7837f72023dffb79"),
        .binaryTarget(name: "tar", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/tar.xcframework.zip", checksum: "207ab260f8dfb3101938c9e2a949cfd7b76f0e90a000637bbfd6aff47b014a68"),
        .binaryTarget(name: "curl_ios", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/curl_ios.xcframework.zip", checksum: "d7e2f05c9f2689d103db32f83ab045bfb6ab28ce84e3017e0c23e4b4db7ab169"),
        .binaryTarget(name: "libssh2", url: "https://github.com/holzschu/libssh2-apple/releases/download/v1.11.0/libssh2-dynamic.xcframework.zip", checksum: "cacfe1789b197b727119f7e32f561eaf9acc27bf38cd19975b74fce107f868a6"),
        .binaryTarget(name: "openssl", url: "https://github.com/holzschu/openssl-apple/releases/download/v1.1.1w/openssl-dynamic.xcframework.zip", checksum: "329e8317cf9bee8e138da5d032330a7a1bd2473cf44c9c083cb2f0636abb8b80"),
        .binaryTarget(name: "awk", url: "https://github.com/holzschu/ios_system/releases/download/v3.0.5/awk.xcframework.zip", checksum: "283f368df6c44ed9d49d15651ca4281706cdd86eb2b6ddb81808c8a3b18a4f7d")
    ]
)
