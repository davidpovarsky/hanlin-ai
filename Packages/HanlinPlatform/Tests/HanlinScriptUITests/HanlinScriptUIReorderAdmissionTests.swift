import Foundation
import HanlinPlatformContracts
@testable import HanlinScriptUI
import Testing

@Suite("ScriptUI reorder admission")
struct HanlinScriptUIReorderAdmissionTests {
    @Test("The original duplicate-key poisoning sequence throws before changing the tree")
    func duplicateReorderSequenceIsRejected() throws {
        let original = tree()
        var published = original
        let patches: [HanlinScriptUIPatch] = [
            .reorder(parent: .init(), keys: ["a", "a", "b"]),
            .reorder(parent: .init(), keys: ["a", "b"])
        ]
        let decoded = try JSONDecoder().decode(
            [HanlinScriptUIPatch].self,
            from: JSONEncoder().encode(patches)
        )
        #expect(throws: HanlinScriptUIError.duplicateKey("a")) {
            published = try HanlinScriptUIReconciler.apply(decoded, to: published)
        }
        #expect(published == original)
    }

    @Test("Duplicate current child keys are rejected before dictionary construction")
    func duplicateCurrentChildKeysAreRejected() {
        let root = HanlinScriptUINode(kind: .vStack, children: [
            .init(kind: .text, key: "a"),
            .init(kind: .text, key: "a")
        ])
        #expect(throws: HanlinScriptUIError.duplicateKey("a")) {
            try HanlinScriptUIReconciler.apply([
                .reorder(parent: .init(), keys: ["a"])
            ], to: root)
        }
    }

    @Test("A current child without a key cannot be reordered")
    func missingCurrentChildKeysAreRejected() {
        let root = HanlinScriptUINode(kind: .vStack, children: [
            .init(kind: .text, key: "a"),
            .init(kind: .text)
        ])
        #expect(throws: HanlinScriptUIError.keySetMismatch) {
            try HanlinScriptUIReconciler.apply([
                .reorder(parent: .init(), keys: ["a"])
            ], to: root)
        }
    }

    @Test("Missing and unknown requested child keys remain rejected")
    func mismatchedRequestedKeySetsAreRejected() {
        for keys in [["a"], ["a", "missing"], ["a", "b", "missing"], []] {
            #expect(throws: HanlinScriptUIError.keySetMismatch) {
                try HanlinScriptUIReconciler.apply([
                    .reorder(parent: .init(), keys: keys)
                ], to: tree())
            }
        }
    }

    @Test("Valid keyed reordering preserves full nodes and subsequent property patches")
    func validReorderPreservesNodesAndPropertyPatches() throws {
        let original = tree()
        let updated: [String: HanlinValue] = ["text": .string("beta updated")]
        let expected = HanlinScriptUINode(
            kind: original.kind, key: original.key, properties: original.properties,
            children: [
                .init(kind: .text, key: "b", properties: updated),
                original.children[0]
            ]
        )
        let result = try HanlinScriptUIReconciler.apply([
            .reorder(parent: .init(), keys: ["b", "a"]),
            .setProperties(path: .init([0]), properties: updated)
        ], to: original)
        #expect(result == expected)
        let empty = HanlinScriptUINode(kind: .fragment)
        #expect(try HanlinScriptUIReconciler.apply([
            .reorder(parent: .init(), keys: [])
        ], to: empty) == empty)
    }

    @Test("An invalid nested reorder does not commit an earlier patch in its batch")
    func invalidNestedBatchKeepsPublishedRootAndAllowsRecovery() throws {
        let original = HanlinScriptUINode(kind: .vStack, key: "outer", children: [tree()])
        var published = original
        #expect(throws: HanlinScriptUIError.duplicateKey("a")) {
            published = try HanlinScriptUIReconciler.apply([
                .setProperties(path: .init([0, 0]), properties: ["text": .string("uncommitted")]),
                .reorder(parent: .init([0]), keys: ["a", "a", "b"])
            ], to: published)
        }
        #expect(published == original)
        published = try HanlinScriptUIReconciler.apply([
            .reorder(parent: .init([0]), keys: ["b", "a"])
        ], to: published)
        #expect(published.children[0].children == Array(original.children[0].children.reversed()))
    }

    private func tree() -> HanlinScriptUINode {
        .init(kind: .vStack, key: "root", properties: ["spacing": .integer(8)], children: [
            .init(kind: .text, key: "a", properties: ["text": .string("alpha")]),
            .init(kind: .text, key: "b", properties: ["text": .string("beta")])
        ])
    }
}
