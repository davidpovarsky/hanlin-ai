import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptExtensions
import HanlinScriptUI
import Testing

@Suite("Scripting extension snapshot store")
struct HanlinScriptExtensionStoreTests {
    @Test("Decodes the visual properties used by the smart-eating widgets")
    func smartEatingWidgetStyle() throws {
        let node = HanlinScriptUINode(kind: .text, properties: [
            "font": .integer(14),
            "fontWeight": .string("semibold"),
            "foregroundStyle": .string("systemGreen"),
            "padding": .integer(8),
            "frame": .object(try .init(uniqueMembers: [
                ("width", .integer(32)), ("height", .integer(18)),
            ])),
            "opacity": .number(0.75),
            "lineLimit": .integer(2),
            "minimumScaleFactor": .number(0.6),
            "strikethrough": .object(try .init(uniqueMembers: [
                ("pattern", .string("solid")),
            ])),
        ])

        let style = HanlinExtensionNodeStyle(node: node)
        #expect(style.fontSize == 14)
        #expect(style.fontWeight == "semibold")
        #expect(style.foregroundStyle == "systemGreen")
        #expect(style.padding == 8)
        #expect(style.frameWidth == 32)
        #expect(style.frameHeight == 18)
        #expect(style.opacity == 0.75)
        #expect(style.lineLimit == 2)
        #expect(style.minimumScaleFactor == 0.6)
        #expect(style.strikethrough)
    }

    @Test("Extracts every Scripting Live Activity presentation region")
    func liveActivityUILayout() throws {
        func region(_ kind: HanlinScriptUIPrimitive, _ text: String) -> HanlinScriptUINode {
            .init(kind: kind, children: [.init(kind: .text, properties: ["text": .string(text)])])
        }
        let root = HanlinScriptUINode(kind: .liveActivityUI, children: [
            region(.liveActivityContent, "lock"),
            region(.liveActivityCompactLeading, "leading"),
            region(.liveActivityCompactTrailing, "trailing"),
            region(.liveActivityMinimal, "minimal"),
            region(.liveActivityExpandedLeading, "expanded-leading"),
            region(.liveActivityExpandedTrailing, "expanded-trailing"),
            region(.liveActivityExpandedCenter, "expanded-center"),
            region(.liveActivityExpandedBottom, "expanded-bottom"),
        ])

        let layout = try HanlinLiveActivityUILayout(root: root)
        #expect(layout.content.properties["text"] == .string("lock"))
        #expect(layout.compactLeading.properties["text"] == .string("leading"))
        #expect(layout.compactTrailing.properties["text"] == .string("trailing"))
        #expect(layout.minimal.properties["text"] == .string("minimal"))
        #expect(layout.expandedLeading?.properties["text"] == .string("expanded-leading"))
        #expect(layout.expandedTrailing?.properties["text"] == .string("expanded-trailing"))
        #expect(layout.expandedCenter?.properties["text"] == .string("expanded-center"))
        #expect(layout.expandedBottom?.properties["text"] == .string("expanded-bottom"))
    }

    @Test("Rejects malformed Live Activity region trees")
    func rejectsMalformedLiveActivityUILayout() {
        let text = HanlinScriptUINode(kind: .text, properties: ["text": .string("value")])
        let incomplete = HanlinScriptUINode(kind: .liveActivityUI, children: [
            .init(kind: .liveActivityContent, children: [text]),
        ])
        #expect(throws: HanlinLiveActivityUILayoutError.missingRegion(.liveActivityCompactLeading)) {
            try HanlinLiveActivityUILayout(root: incomplete)
        }

        let duplicate = HanlinScriptUINode(kind: .liveActivityUI, children: [
            .init(kind: .liveActivityContent, children: [text]),
            .init(kind: .liveActivityContent, children: [text]),
        ])
        #expect(throws: HanlinLiveActivityUILayoutError.duplicateRegion(.liveActivityContent)) {
            try HanlinLiveActivityUILayout(root: duplicate)
        }
    }

    @Test("Persists an integrity-checked extension-safe snapshot")
    func roundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-extension-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = HanlinScriptExtensionIdentity(
            installedPackageID: try .init(validating: "installed.demo"),
            packageID: try .init(validating: "package.demo"),
            generation: 7,
            entrypointID: "widget.main"
        )
        let snapshot = HanlinScriptExtensionSnapshot(
            generatedAt: Date(timeIntervalSince1970: 12),
            widgets: [.init(
                identity: identity,
                displayName: "Demo",
                family: "systemLarge",
                actionIdentity: .init(
                    installedPackageID: identity.installedPackageID,
                    packageID: identity.packageID,
                    generation: identity.generation,
                    entrypointID: "app-intents.main"
                ),
                validUntil: Date(timeIntervalSince1970: 120),
                root: .init(kind: .text, properties: ["text": .string("Hello")])
            )],
            intentEntities: [.init(identity: identity, id: "demo", displayName: "Demo")]
        )
        let store = HanlinScriptExtensionStore(root: root)
        try store.save(snapshot)
        #expect(try store.load() == snapshot)

        let invocation = HanlinScriptIntentInvocation(identity: identity, continueInForeground: true)
        let commandID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let command = HanlinScriptResumeCommand(
            id: commandID,
            createdAt: Date(timeIntervalSince1970: 13),
            invocation: invocation
        )
        try store.enqueue(command)
        #expect(try store.pendingCommands() == [command])
        try store.acknowledge(command.id)
        #expect(try store.pendingCommands().isEmpty)
    }
}
