// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinCacheProof", platforms: [.macOS(.v26)],
 dependencies: [.package(url: "https://github.com/nicklockwood/LRUCache.git", exact: "1.3.0")],
 targets: [
 .target(name: "HanlinCacheProof", dependencies: [.product(name: "LRUCache", package: "LRUCache")]),
 .testTarget(name: "HanlinCacheProofTests", dependencies: ["HanlinCacheProof"])
 ], swiftLanguageModes: [.v6])
