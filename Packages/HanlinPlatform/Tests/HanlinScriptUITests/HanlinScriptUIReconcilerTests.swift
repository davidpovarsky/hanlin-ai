import HanlinPlatformContracts
import HanlinScriptUI
import Testing

@Suite("ScriptUI reconciler")
struct HanlinScriptUIReconcilerTests {
    @Test("Produces deterministic patches that recreate an unkeyed tree")
    func unkeyedDiff() throws {
        let old = stack([
            text("one"),
            text("two")
        ], properties: ["spacing": .integer(4)])
        let new = stack([
            text("updated"),
            text("two"),
            .init(kind: .divider)
        ], properties: ["spacing": .integer(8)])
        let first = try HanlinScriptUIReconciler.diff(from: old, to: new)
        let second = try HanlinScriptUIReconciler.diff(from: old, to: new)
        #expect(first == second)
        #expect(try HanlinScriptUIReconciler.apply(first, to: old) == new)
    }

    @Test("Reorders keyed children before applying their property patches")
    func keyedDiff() throws {
        let old = stack([
            text("alpha", key: "a"),
            text("beta", key: "b")
        ])
        let new = stack([
            text("beta updated", key: "b"),
            text("alpha", key: "a")
        ])
        let patches = try HanlinScriptUIReconciler.diff(from: old, to: new)
        #expect(patches.first == .reorder(parent: .init(), keys: ["b", "a"]))
        #expect(try HanlinScriptUIReconciler.apply(patches, to: old) == new)
    }

    @Test("Rejects duplicate keys and bounded patch overflow")
    func failures() throws {
        let duplicated = stack([text("one", key: "same"), text("two", key: "same")])
        let replacement = stack([text("one", key: "a"), text("two", key: "b")])
        #expect(throws: HanlinScriptUIError.self) {
            try HanlinScriptUIReconciler.diff(from: duplicated, to: replacement)
        }
        #expect(throws: HanlinScriptUIError.patchLimit) {
            try HanlinScriptUIReconciler.diff(
                from: stack([]),
                to: stack([text("1"), text("2")]),
                maximumPatches: 1
            )
        }
    }

    @MainActor
    @Test("Model dispatches events and disposes effects")
    func model() throws {
        var events: [(String, HanlinValue)] = []
        let model = HanlinScriptUIModel(root: text("initial")) { events.append(($0, $1)) }
        try model.apply(.registerEffect(.init(id: "effect.1", dependencies: [.integer(1)])))
        try model.apply(.event(handlerID: "handler.1", payload: .string("tap")))
        #expect(Set(model.effects.keys) == ["effect.1"])
        #expect(events.count == 1)
        try model.apply(.releaseEffect(id: "effect.1"))
        #expect(model.effects.isEmpty)
    }

    @MainActor
    @Test("Navigation, presentation, scene, and resume state are explicit")
    func navigationAndResume() throws {
        var events: [(String, HanlinValue)] = []
        let model = HanlinScriptUIModel(root: stack([])) { events.append(($0, $1)) }
        let route = HanlinScriptUIRoute(id: "details", payload: .object(["id": .integer(42)]))
        try model.apply(.registerRoute(route, destination: text("Details")))
        try model.apply(.navigate(route))
        try model.apply(.selectTab("settings"))
        try model.apply(.present(.init(
            id: "sheet.1",
            style: .sheet,
            content: text("Sheet")
        )))
        try model.apply(.scenePhase(.active))
        try model.apply(.resume(.init(
            source: "widget",
            queryParameters: ["item": .integer(7)],
            widgetParameter: "daily"
        )))
        #expect(model.navigationPath == [route])
        #expect(model.selectedTab == "settings")
        #expect(model.activePresentation?.id == "sheet.1")
        #expect(model.scenePhase == .active)
        #expect(model.lastResumePayload?.source == "widget")
        #expect(events.last?.0 == "Script.onResume")
        try model.apply(.pop(count: 1))
        try model.apply(.dismissPresentation(id: "sheet.1"))
        #expect(model.navigationPath.isEmpty)
        #expect(model.activePresentation == nil)
    }

    @MainActor
    @Test("Unknown routes and invalid pops fail closed")
    func navigationFailures() throws {
        let model = HanlinScriptUIModel(root: stack([])) { _, _ in }
        #expect(throws: HanlinScriptUIError.unknownRoute("missing")) {
            try model.apply(.navigate(.init(id: "missing")))
        }
        #expect(throws: HanlinScriptUIError.invalidPopCount(1)) {
            try model.apply(.pop(count: 1))
        }
    }

    private func text(_ value: String, key: String? = nil) -> HanlinScriptUINode {
        .init(kind: .text, key: key, properties: [
            "text": .string(value),
            "accessibilityLabel": .string(value)
        ])
    }

    private func stack(
        _ children: [HanlinScriptUINode],
        properties: [String: HanlinValue] = [:]
    ) -> HanlinScriptUINode {
        .init(kind: .vStack, properties: properties, children: children)
    }
}
