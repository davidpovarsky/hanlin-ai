// swift-tools-version: 6.4
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "Swift-JSON",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "JSON", targets: ["JSON"]),
        .library(name: "JSONSchema", targets: ["JSONSchema"]),
        .library(name: "JSONSchemaExamples", targets: ["JSONSchemaExamples"]),
        .library(name: "JSONStreaming", targets: ["JSONStreaming"]),
        .library(name: "JSONPatch", targets: ["JSONPatch"]),
        .library(name: "JSONHTML", targets: ["JSONHTML"]),
        .library(name: "JSONBridges", targets: ["JSONBridges"]),
        .library(name: "JSONNavigation", targets: ["JSONNavigation"]),
        .library(name: "JSONInspection", targets: ["JSONInspection"]),
        .library(name: "JSONTransform", targets: ["JSONTransform"]),
        .library(name: "JSONValueDSL", targets: ["JSONValueDSL"]),
        .library(name: "JSONSchemaDSL", targets: ["JSONSchemaDSL"]),
        .executable(name: "swift-json", targets: ["JSONCLI"])
    ],
    targets: [
        .target(name: "JSON"),
        .target(name: "JSONDSLCore", dependencies: ["JSON"]),
        .target(name: "JSONValueDSL", dependencies: ["JSON", "JSONDSLCore"]),
        .target(name: "JSONSchemaDSL", dependencies: ["JSON", "JSONSchema", "JSONDSLCore"]),
        .testTarget(name: "JSONDSLTests", dependencies: ["JSON", "JSONSchema", "JSONDSLCore", "JSONValueDSL", "JSONSchemaDSL"]),
        // Opt-in N1 product candidate; promotion does not change core navigation semantics.
        .target(name: "JSONNavigation", dependencies: ["JSON"]),
        .target(name: "JSONInspection", dependencies: ["JSON", "JSONNavigation"]),
        .testTarget(name: "JSONInspectionTests", dependencies: ["JSONInspection", "JSONNavigation", "JSON"], resources: [.copy("ProjectionFixtures"), .copy("P2Fixtures"), .copy("GraphFixtures"), .copy("StoreFixtures")]),
        .testTarget(name: "JSONNavigationTests", dependencies: ["JSONNavigation", "JSON"], exclude: ["Fixtures"]),
        .target(name: "JSONBridges", dependencies: ["JSON"]),
        .testTarget(name: "JSONIntegrationTests", dependencies: ["JSON", "JSONSchema", "JSONStreaming", "JSONPatch", "JSONInspection", "JSONTransform", "JSONValueDSL", "JSONSchemaDSL"]),
        .testTarget(name: "JSONBridgesTests", dependencies: ["JSONBridges", "JSON"]),
        .target(name: "JSONRegexRuntime", dependencies: ["JSON"]),
        .target(name: "JSONSchema", dependencies: ["JSON", "JSONRegexRuntime"], resources: [.copy("Resources/Draft2020-12")]),
        .target(name: "JSONSchemaExamples", dependencies: ["JSON", "JSONSchema"]),
        .testTarget(name: "JSONSchemaExamplesTests", dependencies: ["JSONSchemaExamples", "JSON", "JSONSchema"]),
        .target(name: "JSONStreaming", dependencies: ["JSON"]),
        .target(name: "JSONPatch", dependencies: ["JSON"]),
        .target(name: "JSONHTML", dependencies: ["JSON"], exclude: ["Assets"]),
        .target(name: "JSONFilterRuntime", dependencies: ["JSON"]),
        .target(name: "JSONTransform", dependencies: ["JSON", "JSONFilterRuntime"]),
        .testTarget(name: "JSONTransformTests", dependencies: ["JSON", "JSONTransform", "JSONFilterRuntime"]),
        .target(name: "JSONCLIEngine", dependencies: ["JSON", "JSONSchema", "JSONStreaming", "JSONPatch", "JSONHTML", "JSONFilterRuntime", "JSONTransform"]),
        .executableTarget(name: "JSONCLI", dependencies: ["JSONCLIEngine"]),
        .testTarget(name: "JSONCLITests", dependencies: ["JSONCLIEngine", "JSONFilterRuntime", "JSON", "JSONPatch", "JSONSchema", "JSONHTML"]),
        .testTarget(name: "JSONHTMLTests", dependencies: ["JSONHTML", "JSON"], resources: [.copy("Fixtures")]),
        .testTarget(name: "JSONTests", dependencies: ["JSON"], exclude: ["ImplementationPlan.md"]),
        .testTarget(name: "JSONSchemaTests", dependencies: ["JSONSchema"], exclude: ["ImplementationPlan.md"]),
        .testTarget(name: "JSONStreamingTests", dependencies: ["JSONStreaming"], exclude: ["ImplementationPlan.md"]),
        .testTarget(name: "JSONPatchTests", dependencies: ["JSONPatch"], exclude: ["ImplementationPlan.md"]),
        .testTarget(name: "JSONRegexRuntimeTests", dependencies: ["JSONRegexRuntime"], exclude: ["ImplementationPlan.md"])
    ],
    swiftLanguageModes: [.v6]
)
