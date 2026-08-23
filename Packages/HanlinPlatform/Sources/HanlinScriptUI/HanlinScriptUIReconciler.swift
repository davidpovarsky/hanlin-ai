import Foundation

public enum HanlinScriptUIReconciler {
    public static func diff(
        from old: HanlinScriptUINode,
        to new: HanlinScriptUINode,
        maximumPatches: Int = 10_000
    ) throws -> [HanlinScriptUIPatch] {
        var patches: [HanlinScriptUIPatch] = []
        try collect(from: old, to: new, path: .init(), patches: &patches, maximum: maximumPatches)
        return patches
    }

    public static func apply(
        _ patches: [HanlinScriptUIPatch],
        to root: HanlinScriptUINode,
        maximumPatches: Int = 10_000
    ) throws -> HanlinScriptUINode {
        guard patches.count <= maximumPatches else { throw HanlinScriptUIError.patchLimit }
        return try patches.reduce(root) { value, patch in try applying(patch, to: value) }
    }

    private static func collect(
        from old: HanlinScriptUINode,
        to new: HanlinScriptUINode,
        path: HanlinScriptUIPath,
        patches: inout [HanlinScriptUIPatch],
        maximum: Int
    ) throws {
        guard patches.count < maximum else { throw HanlinScriptUIError.patchLimit }
        guard old.kind == new.kind, old.key == new.key else {
            patches.append(.replace(path: path, node: new))
            return
        }
        if old.properties != new.properties {
            patches.append(.setProperties(path: path, properties: new.properties))
        }
        let oldKeys = old.children.compactMap(\.key)
        let newKeys = new.children.compactMap(\.key)
        let fullyKeyed = oldKeys.count == old.children.count && newKeys.count == new.children.count
        if fullyKeyed, !old.children.isEmpty || !new.children.isEmpty {
            guard Set(oldKeys).count == oldKeys.count else { throw HanlinScriptUIError.duplicateKey(oldKeys.first ?? "") }
            guard Set(newKeys).count == newKeys.count else { throw HanlinScriptUIError.duplicateKey(newKeys.first ?? "") }
            guard Set(oldKeys) == Set(newKeys) else {
                patches.append(.replace(path: path, node: new))
                return
            }
            if oldKeys != newKeys { patches.append(.reorder(parent: path, keys: newKeys)) }
            let oldByKey = Dictionary(uniqueKeysWithValues: old.children.compactMap { node in node.key.map { ($0, node) } })
            for (index, child) in new.children.enumerated() {
                guard let key = child.key, let previous = oldByKey[key] else { throw HanlinScriptUIError.keySetMismatch }
                try collect(from: previous, to: child, path: path.appending(index), patches: &patches, maximum: maximum)
            }
            return
        }
        let shared = min(old.children.count, new.children.count)
        for index in 0 ..< shared {
            try collect(from: old.children[index], to: new.children[index], path: path.appending(index), patches: &patches, maximum: maximum)
        }
        if old.children.count > new.children.count {
            for index in stride(from: old.children.count - 1, through: new.children.count, by: -1) {
                patches.append(.remove(path: path.appending(index)))
            }
        } else if new.children.count > old.children.count {
            for index in old.children.count ..< new.children.count {
                patches.append(.insert(parent: path, index: index, node: new.children[index]))
            }
        }
        guard patches.count <= maximum else { throw HanlinScriptUIError.patchLimit }
    }

    private static func applying(
        _ patch: HanlinScriptUIPatch,
        to root: HanlinScriptUINode
    ) throws -> HanlinScriptUINode {
        switch patch {
        case let .replace(path, node): return try replacing(root, at: path.indices, with: node)
        case let .setProperties(path, properties):
            return try updating(root, at: path.indices) {
                .init(kind: $0.kind, key: $0.key, properties: properties, children: $0.children)
            }
        case let .insert(parent, index, node):
            return try updating(root, at: parent.indices) { current in
                guard (0 ... current.children.count).contains(index) else { throw HanlinScriptUIError.invalidPath(parent.appending(index)) }
                var children = current.children
                children.insert(node, at: index)
                return .init(kind: current.kind, key: current.key, properties: current.properties, children: children)
            }
        case let .remove(path):
            guard let index = path.indices.last else { throw HanlinScriptUIError.invalidPath(path) }
            return try updating(root, at: Array(path.indices.dropLast())) { current in
                guard current.children.indices.contains(index) else { throw HanlinScriptUIError.invalidPath(path) }
                var children = current.children
                children.remove(at: index)
                return .init(kind: current.kind, key: current.key, properties: current.properties, children: children)
            }
        case let .reorder(parent, keys):
            return try updating(root, at: parent.indices) { current in
                let keyed = Dictionary(uniqueKeysWithValues: current.children.compactMap { node in node.key.map { ($0, node) } })
                guard keyed.count == current.children.count, Set(keyed.keys) == Set(keys) else { throw HanlinScriptUIError.keySetMismatch }
                return .init(kind: current.kind, key: current.key, properties: current.properties, children: try keys.map {
                    guard let node = keyed[$0] else { throw HanlinScriptUIError.keySetMismatch }
                    return node
                })
            }
        }
    }

    private static func replacing(
        _ root: HanlinScriptUINode,
        at path: [Int],
        with replacement: HanlinScriptUINode
    ) throws -> HanlinScriptUINode {
        if path.isEmpty { return replacement }
        return try updating(root, at: Array(path.dropLast())) { parent in
            guard let index = path.last, parent.children.indices.contains(index) else {
                throw HanlinScriptUIError.invalidPath(.init(path))
            }
            var children = parent.children
            children[index] = replacement
            return .init(kind: parent.kind, key: parent.key, properties: parent.properties, children: children)
        }
    }

    private static func updating(
        _ node: HanlinScriptUINode,
        at path: [Int],
        transform: (HanlinScriptUINode) throws -> HanlinScriptUINode
    ) throws -> HanlinScriptUINode {
        guard let index = path.first else { return try transform(node) }
        guard node.children.indices.contains(index) else { throw HanlinScriptUIError.invalidPath(.init(path)) }
        var children = node.children
        children[index] = try updating(children[index], at: Array(path.dropFirst()), transform: transform)
        return .init(kind: node.kind, key: node.key, properties: node.properties, children: children)
    }
}
