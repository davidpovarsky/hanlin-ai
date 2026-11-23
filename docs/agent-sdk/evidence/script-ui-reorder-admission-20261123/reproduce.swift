import HanlinScriptUI

@main
struct Reproduce {
    static func main() throws {
        let root = HanlinScriptUINode(kind: .vStack, children: [
            .init(kind: .text, key: "a"),
            .init(kind: .text, key: "b")
        ])
        let patches: [HanlinScriptUIPatch] = [
            .reorder(parent: .init(), keys: ["a", "a", "b"]),
            .reorder(parent: .init(), keys: ["a", "b"])
        ]
        _ = try HanlinScriptUIReconciler.apply(patches, to: root)
    }
}
