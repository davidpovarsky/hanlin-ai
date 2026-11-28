// SPDX-License-Identifier: Apache-2.0
import JSON

/// Invocation-owned traversal of the compiler's finite graph; references are never unrolled.
package struct JSONSchemaProviderInspection {
    let profile: JSONSchemaProviderProfile
    let limits: JSONSchemaProviderLimits
    var nodes: UInt64 = 0, edges: UInt64 = 0, declarations: UInt64 = 0, metadata: UInt64 = 0
    var properties: UInt64 = 0, enumValues: UInt64 = 0, countedText: UInt64 = 0
    var issues: [JSONSchemaProviderIssue] = []
    var incompatible = false, truncated = false

    mutating func charge(_ metric: JSONSchemaProviderMetric, _ amount: UInt64, meter: inout JSONWorkMeter) throws {
        let current: UInt64, cap: UInt64
        switch metric {
        case .schemaNodes: current = nodes; cap = limits.schemaNodes
        case .referenceEdges: current = edges; cap = limits.referenceEdges
        case .declarations: current = declarations; cap = limits.declarations
        case .metadataBytes: current = metadata; cap = limits.metadataBytes
        }
        let (next, overflow) = current.addingReportingOverflow(amount)
        guard !overflow, next <= cap else {
            let error = JSONSchemaProviderFailure.limitExceeded(metric: metric, limit: cap, attempted: overflow ? nil : next)
            meter.recordFailure(error); throw error
        }
        try meter.work(amount)
        switch metric {
        case .schemaNodes: nodes = next
        case .referenceEdges: edges = next
        case .declarations: declarations = next
        case .metadataBytes: metadata = next
        }
    }
    mutating func issue(_ code: JSONSchemaProviderIssueCode, _ path: [JSONLocationComponent], unverified: Bool = false, meter: inout JSONWorkMeter) throws {
        incompatible = true; try meter.work()
        guard UInt64(issues.count) < meter.limits[.issues] else { truncated = true; return }
        // Path slots, key bytes and fixed explanations overlap the source/plan.
        try meter.require(.pointerTokens, UInt64(path.count))
        for component in path {
            try meter.work(); try meter.retain(32)
            if case .key(let key) = component {
                for _ in key.string.utf8 { try meter.work(); try meter.charge(.diagnosticBytes); try meter.retain(1) }
            }
        }
        let value = JSONSchemaProviderIssue(code: code, path: path, unverified: unverified)
        for _ in value.explanation.utf8 { try meter.work(); try meter.charge(.diagnosticBytes); try meter.retain(1) }
        try meter.retain(64); issues.append(value)
    }
    mutating func total(_ current: UInt64, _ amount: UInt64, ceiling: UInt64, path: [JSONLocationComponent], meter: inout JSONWorkMeter) throws -> UInt64 {
        let (next, overflow) = current.addingReportingOverflow(amount)
        guard !overflow else {
            let error = JSONSchemaProviderFailure.limitExceeded(metric: .declarations, limit: limits.declarations, attempted: nil)
            meter.recordFailure(error); throw error
        }
        if next > ceiling { try issue(.profileCapacity, path, meter: &meter) }
        return next
    }
    mutating func counted(_ text: String, path: [JSONLocationComponent], meter: inout JSONWorkMeter) throws -> UInt64 {
        var bytes: UInt64 = 0
        for _ in text.utf8 { try meter.work(); bytes += 1 }
        // Explicitly local conservative UTF-8 rule, not a claim about provider character units.
        countedText = try total(countedText, bytes, ceiling: 120_000, path: path, meter: &meter)
        return bytes
    }
    mutating func metadataText(_ text: String, meter: inout JSONWorkMeter) throws {
        for _ in text.utf8 { try charge(.metadataBytes, 1, meter: &meter) }
    }
    func result() -> JSONSchemaProviderCompatibility {
        .init(profile: profile, issues: issues, truncated: truncated, isCompatible: !incompatible,
              checkedSchemaNodes: nodes, checkedReferenceEdges: edges, checkedDeclarations: declarations)
    }
    private func ascii(_ text: String, meter: inout JSONWorkMeter) throws -> Bool {
        for byte in text.utf8 { try meter.work(); if byte > 127 { return false } }
        return true
    }
    private func lookup(_ object: JSONObject, _ key: String, meter: inout JSONWorkMeter) throws -> JSON? { try object.lookup(key, meter: &meter) }

    mutating func inspect(_ compiled: CompiledJSONSchema, meter: inout JSONWorkMeter) throws -> JSONSchemaProviderCompatibility {
        let plan = compiled.plan, rootDocument = plan.nodes[plan.root].document
        struct Frame { let node: Int; let path: [JSONLocationComponent]; let depth: UInt64 }
        try meter.retain(64)
        var stack = [Frame(node: plan.root, path: [], depth: 1)]
        while let frame = stack.popLast() {
            try meter.checkpoint(); try charge(.schemaNodes, 1, meter: &meter)
            let node = plan.nodes[frame.node], path = frame.path
            guard case .object(let object) = node.raw else {
                try issue(.booleanSchema, path, meter: &meter); continue
            }
            let type = try lookup(object, "type", meter: &meter)
            let anyOf = try lookup(object, "anyOf", meter: &meter)
            let ref = try lookup(object, "$ref", meter: &meter)
            if frame.node == plan.root, type != .string("object") || anyOf != nil || ref != nil {
                try issue(.objectRootRequired, path, meter: &meter)
            }
            if frame.depth > 10 { try issue(.profileCapacity, path, meter: &meter) }
            var types: [String] = []
            if case .string(let value) = type { types = [value] }
            else if case .array(let array) = type {
                for value in array { try meter.work(); if case .string(let name) = value { try meter.retain(16); types.append(name) } }
                if types.count != 2 || !types.contains("null") { try issue(.unverifiedDeclaration, path + [.key(JSONKey("type"))], unverified: true, meter: &meter) }
            }
            for name in types {
                if try !ascii(name, meter: &meter) || !["object", "array", "string", "number", "integer", "boolean", "null"].contains(name) {
                    try issue(.unverifiedDeclaration, path + [.key(JSONKey("type"))], unverified: true, meter: &meter)
                }
            }
            if type == nil && anyOf == nil && ref == nil || type != nil && (anyOf != nil || ref != nil) || anyOf != nil && ref != nil {
                try issue(.unverifiedDeclaration, path, unverified: true, meter: &meter)
            }
            if types.contains("object") {
                if try lookup(object, "additionalProperties", meter: &meter) != .boolean(false) {
                    try issue(.closedObjectRequired, path + [.key(JSONKey("additionalProperties"))], meter: &meter)
                }
                let declared = try lookup(object, "properties", meter: &meter)?.objectValue
                let required = try lookup(object, "required", meter: &meter)?.arrayValue
                if declared == nil { try issue(.unverifiedDeclaration, path + [.key(JSONKey("properties"))], unverified: true, meter: &meter) }
                var complete = required != nil && (required?.count ?? 0) == (declared?.count ?? 0)
                if let required {
                    for value in required {
                        try meter.work()
                        guard case .string(let name) = value else { complete = false; continue }
                        if try declared?.lookup(name, meter: &meter) == nil { complete = false }
                    }
                }
                if !complete { try issue(.allPropertiesRequired, path + [.key(JSONKey("required"))], meter: &meter) }
                properties = try total(properties, UInt64(declared?.count ?? 0), ceiling: 5_000, path: path, meter: &meter)
            } else if try lookup(object, "properties", meter: &meter) != nil || lookup(object, "required", meter: &meter) != nil || lookup(object, "additionalProperties", meter: &meter) != nil {
                try issue(.unverifiedDeclaration, path, unverified: true, meter: &meter)
            }
            if types.contains("array"), try lookup(object, "items", meter: &meter) == nil {
                try issue(.unverifiedDeclaration, path + [.key(JSONKey("items"))], unverified: true, meter: &meter)
            }
            for member in object {
                try charge(.declarations, 1, meter: &meter)
                let key = member.key.string, location = path + [.key(member.key)]
                guard try ascii(key, meter: &meter) else { try issue(.unverifiedDeclaration, location, unverified: true, meter: &meter); continue }
                switch key {
                case "type", "properties", "required", "additionalProperties", "items", "anyOf", "$ref": break
                case "$defs":
                    if case .object(let definitions) = member.value {
                        for definition in definitions { _ = try counted(definition.key.string, path: location + [.key(definition.key)], meter: &meter) }
                    }
                case "description", "title":
                    if case .string(let text) = member.value { try metadataText(text, meter: &meter) }
                case "enum":
                    if case .array(let values) = member.value {
                        enumValues = try total(enumValues, UInt64(values.count), ceiling: 1_000, path: location, meter: &meter)
                        var stringBytes: UInt64 = 0
                        for (index, value) in values.enumerated() {
                            try meter.work()
                            if case .string(let text) = value {
                                let bytes = try counted(text, path: location + [.index(index)], meter: &meter)
                                stringBytes = try total(stringBytes, bytes, ceiling: values.count > 250 ? 15_000 : UInt64.max, path: location, meter: &meter)
                            } else if value.objectValue != nil || value.arrayValue != nil {
                                try issue(.unverifiedDeclaration, location + [.index(index)], unverified: true, meter: &meter)
                            }
                        }
                    }
                case "pattern", "format":
                    if !types.contains("string") { try issue(.unverifiedDeclaration, location, unverified: true, meter: &meter) }
                    if key == "format", case .string(let format) = member.value,
                       try !ascii(format, meter: &meter) || !["date-time", "time", "date", "duration", "email", "hostname", "ipv4", "ipv6", "uuid"].contains(format) {
                        try issue(.unsupportedFormat, location, meter: &meter)
                    }
                case "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf":
                    if !types.contains("number") && !types.contains("integer") { try issue(.unverifiedDeclaration, location, unverified: true, meter: &meter) }
                case "minItems", "maxItems":
                    if !types.contains("array") { try issue(.unverifiedDeclaration, location, unverified: true, meter: &meter) }
                case "allOf", "oneOf", "not", "if", "then", "else", "$dynamicRef", "$dynamicAnchor", "dependentRequired", "dependentSchemas", "unevaluatedProperties", "unevaluatedItems", "patternProperties", "prefixItems", "contains", "propertyNames", "uniqueItems":
                    try issue(.unsupportedKeyword, location, meter: &meter)
                default: try issue(.unverifiedDeclaration, location, unverified: true, meter: &meter)
                }
            }
            if let declared = try lookup(object, "properties", meter: &meter)?.objectValue {
                for member in declared { _ = try counted(member.key.string, path: path + [.key(JSONKey("properties")), .key(member.key)], meter: &meter) }
            }
            if let ref {
                if case .string(let text) = ref, text.utf8.first != 35 { try issue(.externalReference, path + [.key(JSONKey("$ref"))], meter: &meter) }
                var chain: [Int] = [], current = frame.node
                while true {
                    try meter.work()
                    var repeated = false
                    for previous in chain { try meter.work(); if previous == current { repeated = true; break } }
                    if repeated { try issue(.nonProductiveReference, path + [.key(JSONKey("$ref"))], meter: &meter); break }
                    try meter.retain(16); chain.append(current)
                    let target = plan.nodes[current]
                    guard let raw = target.raw.objectValue,
                          try lookup(raw, "type", meter: &meter) == nil,
                          try lookup(raw, "anyOf", meter: &meter) == nil,
                          let reference = target.references.first else { break }
                    try charge(.referenceEdges, 1, meter: &meter)
                    if plan.nodes[reference.target].document != rootDocument { try issue(.externalReference, path + [.key(JSONKey("$ref"))], meter: &meter); break }
                    current = reference.target
                }
            }
            for child in node.children {
                try charge(.referenceEdges, 1, meter: &meter)
                guard [JSONSchemaPlan.Keyword.properties, .defs, .items, .anyOf].contains(child.keyword) else { continue }
                var location = path + [.key(JSONKey(child.keyword.rawValue))]
                if let token = child.token {
                    if child.keyword == .anyOf {
                        guard let index = Int(token.string), index >= 0 else { throw JSONFailure(.configuration, code: .invalidOperation) }
                        location.append(.index(index))
                    } else { location.append(.key(token)) }
                }
                try meter.require(.pointerTokens, UInt64(location.count))
                try meter.retain(64)
                for _ in location { try meter.work(); try meter.retain(32) }
                stack.append(.init(node: child.target, path: location, depth: child.keyword == .defs ? 1 : child.keyword == .anyOf ? frame.depth : frame.depth + 1))
            }
        }
        try referenceDepth(compiled, meter: &meter)
        return result()
    }
    /// Check non-recursive reference expansion too. Only active-path back edges are
    /// skipped: a shared DAG node is revisited at each actual incoming depth.
    private mutating func referenceDepth(_ compiled: CompiledJSONSchema, meter: inout JSONWorkMeter) throws {
        let plan = compiled.plan, document = plan.nodes[plan.root].document
        struct Frame { let node: Int; let depth: UInt64; let leaving: Bool }
        try meter.retain(UInt64(plan.nodes.count) + 64)
        var active = Array(repeating: false, count: plan.nodes.count)
        var activeDepth: [UInt64] = []
        for _ in plan.nodes { try meter.work(); try meter.retain(8); activeDepth.append(0) }
        var stack = [Frame(node: plan.root, depth: 1, leaving: false)]
        for node in plan.nodes {
            try meter.work()
            guard node.document == document else { continue }
            for child in node.children {
                try meter.work()
                guard child.keyword == .defs else { continue }
                try charge(.referenceEdges, 1, meter: &meter)
                try meter.retain(64); stack.append(.init(node: child.target, depth: 1, leaving: false))
            }
        }
        while let frame = stack.popLast() {
            try meter.work()
            if frame.leaving { active[frame.node] = false; continue }
            if active[frame.node] {
                if frame.depth == activeDepth[frame.node] {
                    let path = try typedPath(plan.nodes[frame.node].pointer, raw: compiled.document.raw, meter: &meter)
                    try issue(.nonProductiveReference, path, meter: &meter)
                }
                continue
            }
            let node = plan.nodes[frame.node]
            if frame.depth > 10 {
                let path = try typedPath(node.pointer, raw: compiled.document.raw, meter: &meter)
                try issue(.profileCapacity, path, meter: &meter); continue
            }
            active[frame.node] = true; activeDepth[frame.node] = frame.depth
            try meter.retain(64); stack.append(.init(node: frame.node, depth: frame.depth, leaving: true))
            for reference in node.references {
                try meter.work()
                guard plan.nodes[reference.target].document == document else { continue }
                try charge(.referenceEdges, 1, meter: &meter)
                try meter.retain(64); stack.append(.init(node: reference.target, depth: frame.depth, leaving: false))
            }
            for child in node.children {
                try meter.work()
                guard [JSONSchemaPlan.Keyword.properties, .items, .anyOf].contains(child.keyword) else { continue }
                try charge(.referenceEdges, 1, meter: &meter)
                try meter.retain(64); stack.append(.init(node: child.target, depth: child.keyword == .anyOf ? frame.depth : frame.depth + 1, leaving: false))
            }
        }
    }
    private func typedPath(_ pointer: JSONPointer, raw: JSON, meter: inout JSONWorkMeter) throws -> [JSONLocationComponent] {
        var current = raw, path: [JSONLocationComponent] = []
        for token in pointer.tokens {
            try meter.work(); try meter.retain(32)
            switch current {
            case .object(let object):
                guard let value = try object.lookup(token.string, meter: &meter) else { throw JSONFailure(.configuration, code: .invalidOperation) }
                path.append(.key(token)); current = value
            case .array(let array):
                guard let index = Int(token.string), index >= 0 && index < array.count else { throw JSONFailure(.configuration, code: .invalidOperation) }
                path.append(.index(index)); current = array[index]
            default: throw JSONFailure(.configuration, code: .invalidOperation)
            }
        }
        return path
    }

}
