import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptExtensions
import HanlinScriptUI
import Testing
import SwiftUI

@Suite("Dual Native Widget Engines & Schema V2 Verification")
@MainActor
struct HanlinDualWidgetEnginesTests {

    @Test("Schema V2 save and load round-trip with all 3 engines")
    func schemaV2RoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-dual-widget-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "package.dual.engine"),
            packageID: try .init(validating: "package.dual.engine"),
            generation: 1,
            entrypointID: "widget.main"
        )

        // 1. Legacy snapshot
        let legacySnapshot = HanlinScriptWidgetSnapshot(
            identity: identity,
            displayName: "Legacy Widget",
            family: "systemSmall",
            validUntil: Date(timeIntervalSince1970: 1000),
            engine: .legacy,
            payload: .legacy(HanlinScriptUINode(kind: .text, properties: ["text": .string("Legacy Fallback")])),
            root: HanlinScriptUINode(kind: .text, properties: ["text": .string("Legacy Fallback")])
        )

        // 2. Expo snapshot
        let expoDesc = ExpoWidgetDescriptor(
            layout: "function(props, env) { return { type: 'TextView', props: { text: 'Expo Native' } }; }",
            props: ["name": .string("Hanlin")],
            sourceName: "ExpoCounter"
        )
        let expoSnapshot = HanlinScriptWidgetSnapshot(
            identity: identity,
            displayName: "Expo Widget",
            family: "systemMedium",
            validUntil: Date(timeIntervalSince1970: 2000),
            engine: .expo,
            payload: .expo(expoDesc),
            root: HanlinScriptUINode(kind: .text, properties: ["text": .string("Expo Native")])
        )

        // 3. ScriptWidget snapshot
        let scriptDesc = ScriptWidgetDescriptor(
            script: "render(<vstack><text>ScriptWidget Native</text></vstack>)",
            environment: ["colorScheme": .string("dark")]
        )
        let scriptWidgetSnapshot = HanlinScriptWidgetSnapshot(
            identity: identity,
            displayName: "ScriptWidget Dashboard",
            family: "systemLarge",
            validUntil: Date(timeIntervalSince1970: 3000),
            engine: .scriptwidget,
            payload: .scriptwidget(scriptDesc),
            root: HanlinScriptUINode(kind: .text, properties: ["text": .string("ScriptWidget Native")])
        )

        let snapshot = HanlinScriptExtensionSnapshot(
            schemaVersion: 2,
            generatedAt: Date(timeIntervalSince1970: 500),
            widgets: [legacySnapshot, expoSnapshot, scriptWidgetSnapshot]
        )

        let store = HanlinScriptExtensionStore(root: tempDir)
        try store.save(snapshot)

        let loaded = try #require(try store.load())
        #expect(loaded.schemaVersion == 2)
        #expect(loaded.widgets.count == 3)

        // Verify engines
        #expect(loaded.widgets[0].engine == .legacy)
        #expect(loaded.widgets[1].engine == .expo)
        #expect(loaded.widgets[2].engine == .scriptwidget)

        // Verify payloads
        if case let .legacy(node) = loaded.widgets[0].payload {
            #expect(node.kind == .text)
            #expect(node.properties["text"] == .string("Legacy Fallback"))
        } else {
            Issue.record("Expected legacy payload")
        }

        if case let .expo(desc) = loaded.widgets[1].payload {
            #expect(desc.sourceName == "ExpoCounter")
            #expect(desc.props?["name"] == .string("Hanlin"))
        } else {
            Issue.record("Expected expo payload")
        }

        if case let .scriptwidget(desc) = loaded.widgets[2].payload {
            #expect(desc.script.contains("ScriptWidget Native"))
            #expect(desc.environment?["colorScheme"] == .string("dark"))
        } else {
            Issue.record("Expected scriptwidget payload")
        }
    }

    @Test("Schema V1 backwards compatibility: unversioned snapshot decodes as legacy")
    func schemaV1BackwardsCompatibility() throws {
        let v1JSON = """
        {
            "schemaVersion": 1,
            "sha256": "ignored_in_raw_decode",
            "snapshot": {
                "schemaVersion": 1,
                "generatedAt": "1970-01-01T00:00:10.000Z",
                "widgets": [{
                    "identity": {
                        "installedPackageID": "pkg.v1",
                        "packageID": "pkg.v1",
                        "generation": 1,
                        "entrypointID": "w1"
                    },
                    "displayName": "V1 Widget",
                    "family": "systemSmall",
                    "validUntil": "1970-01-01T00:01:00.000Z",
                    "relevance": 1.0,
                    "root": {
                        "kind": "text",
                        "properties": { "text": "Old Root" }
                    }
                }],
                "intentEntities": [],
                "liveActivities": [],
                "translationApps": []
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct TestEnvelope: Decodable {
            let schemaVersion: UInt32
            let snapshot: HanlinScriptWidgetSnapshotContainer
        }
        struct HanlinScriptWidgetSnapshotContainer: Decodable {
            let widgets: [HanlinScriptWidgetSnapshot]
        }

        let envelope = try decoder.decode(TestEnvelope.self, from: v1JSON.data(using: .utf8)!)
        #expect(envelope.schemaVersion == 1)
        let widget = try #require(envelope.snapshot.widgets.first)
        #expect(widget.engine == .legacy)
        #expect(widget.displayName == "V1 Widget")
        #expect(widget.root.kind == .text)
        #expect(widget.root.properties["text"] == .string("Old Root"))
    }

    @Test("ScriptWidgetElement: parses and renders all 29 native SwiftUI tags")
    func scriptWidgetAll29Tags() throws {
        let all29Tags = [
            "hstack", "vstack", "zstack", "hgrid", "vgrid",
            "text", "date", "image", "gif", "spacer",
            "rect", "capsule", "ellipse", "circle", "gauge",
            "chart", "link", "divider", "line", "roundedrect",
            "icon", "label", "progress", "ring", "badge",
            "chip", "stat", "button", "toggle"
        ]

        #expect(all29Tags.count == 29)

        for tag in all29Tags {
            let elem = HanlinScriptWidgetElement(
                tag: tag,
                props: [
                    "title": "Tag \(tag)",
                    "text": "Content for \(tag)",
                    "value": NSNumber(value: 42.0),
                    "min": NSNumber(value: 0.0),
                    "max": NSNumber(value: 100.0),
                    "color": "#FF5500",
                    "systemName": "star.fill"
                ],
                children: [
                    HanlinScriptWidgetElement(tag: "text", rawText: "Child of \(tag)")
                ],
                rawText: "Raw \(tag)"
            )

            // Must produce a non-nil SwiftUI AnyView without crash
            let view = HanlinScriptWidgetElementView.buildView(element: elem)
            #expect(String(describing: type(of: view)) == "AnyView")
        }
    }

    @Test("Mixed Tree: ScriptWidget JSX subtree embedded inside Expo layout node")
    func mixedTreeScriptWidgetInsideExpo() throws {
        let scriptWidgetChildDict: [String: Any] = [
            "tag": "vstack",
            "props": ["spacing": NSNumber(value: 4)],
            "children": [
                [
                    "tag": "badge",
                    "props": ["color": "#00AAFF"],
                    "text": "Mixed JSX Subtree"
                ],
                [
                    "tag": "text",
                    "props": ["bold": true],
                    "text": "Native ScriptWidget in Expo!"
                ]
            ]
        ]

        let expoParentNode: [String: Any] = [
            "type": "VStackView",
            "props": [
                "spacing": NSNumber(value: 8),
                "children": [
                    [
                        "type": "TextView",
                        "props": ["text": "Expo Header", "font": "headline"]
                    ],
                    [
                        "type": "ScriptWidgetSubtree",
                        "props": [
                            "element": scriptWidgetChildDict
                        ]
                    ]
                ]
            ]
        ]

        let renderedView = HanlinExpoWidgetsViewRenderer.renderNode(expoParentNode)
        #expect(String(describing: type(of: renderedView)) == "AnyView")
    }

    @Test("ExpoWidgetsViewRenderer renders native shapes, gauges, and charts")
    func expoWidgetsViewRendererPrimitives() throws {
        let sampleNodes: [[String: Any]] = [
            ["type": "TextView", "props": ["text": "Hello Expo", "font": "title2", "color": "#123456"]],
            ["type": "RectangleView", "props": ["fill": "#FF0000", "width": NSNumber(value: 50), "height": NSNumber(value: 20)]],
            ["type": "RoundedRectangleView", "props": ["cornerRadius": NSNumber(value: 12), "fill": "blue"]],
            ["type": "CapsuleView", "props": ["fill": "green"]],
            ["type": "CircleView", "props": ["fill": "purple"]],
            ["type": "EllipseView", "props": ["fill": "orange"]],
            ["type": "DividerView", "props": [:]],
            ["type": "SpacerView", "props": ["minLength": NSNumber(value: 10)]],
            ["type": "ProgressView", "props": ["value": NSNumber(value: 0.6), "total": NSNumber(value: 1.0)]],
            ["type": "GaugeView", "props": ["value": NSNumber(value: 75), "min": NSNumber(value: 0), "max": NSNumber(value: 100), "label": "CPU"]],
            ["type": "ChartView", "props": ["chartType": "bar", "data": [["x": "Mon", "y": NSNumber(value: 10)], ["x": "Tue", "y": NSNumber(value: 20)]]]],
            ["type": "Button", "props": ["title": "Tap Me", "target": "__expo_widgets_target_0"]],
            ["type": "LinkView", "props": ["title": "Open Web", "url": "https://example.com"]],
            ["type": "ImageView", "props": ["systemName": "sun.max.fill"]]
        ]

        for node in sampleNodes {
            let v = HanlinExpoWidgetsViewRenderer.renderNode(node)
            #expect(String(describing: type(of: v)) == "AnyView")
        }
    }
}
