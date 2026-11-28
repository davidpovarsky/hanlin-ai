// SPDX-License-Identifier: Apache-2.0
import JSON

/// Invocation-owned explicit continuations. Operational errors never become branch invalidity.
package struct JSONSchemaEvaluation {
    typealias Frame = JSONEvaluationFrame
    typealias Keyword = JSONSchemaPlan.Keyword
    package let plan: JSONSchemaPlan
    package let options: JSONSchemaOptions

    private func equalPath(_ a: [JSONLocationComponent], _ b: [JSONLocationComponent], meter: inout JSONWorkMeter) throws -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices {
            try meter.work()
            switch (a[i],b[i]) {
            case (.index(let x),.index(let y)): if x != y { return false }
            case (.key(let x),.key(let y)): if try !JSONComparison.textEquals(x.string,y.string,meter: &meter) { return false }
            default: return false
            }
        }
        return true
    }
    private func makeFrame(node: Int, instance: JSON, path: [JSONLocationComponent], trace: [JSONKey], scope: [Int],
                           returning: Frame.Return?, ancestors: [Frame], meter: inout JSONWorkMeter) throws -> Frame {
        try meter.require(.evaluationFrames, UInt64(ancestors.count)+1)
        var nextScope: [Int] = [], found = false, bytes = JSONLogicalWeights.frame
        for resource in scope {
            try meter.work(); try meter.retain(8); bytes += 8; nextScope.append(resource)
            if resource == plan.nodes[node].resource { found = true }
        }
        if !found { try meter.retain(8); bytes += 8; nextScope.append(plan.nodes[node].resource) }
        for frame in ancestors {
            try meter.work(); guard frame.node == node else { continue }
            if try equalPath(frame.path,path,meter: &meter), frame.scope.count == nextScope.count {
                var equal = true
                for i in nextScope.indices { try meter.work(); if frame.scope[i] != nextScope[i] { equal = false; break } }
                if equal { throw JSONSchemaEvaluationFailure(.nonproductiveReference) }
            }
        }
        var ownedPath: [JSONLocationComponent] = [], ownedTrace: [JSONKey] = []
        try meter.retain(JSONLogicalWeights.frame)
        for item in path { try meter.work(); try meter.retain(16); bytes += 16; ownedPath.append(item) }
        for token in trace { try meter.work(); try meter.retain(16); bytes += 16; ownedTrace.append(token) }
        return .init(node: node, instance: instance, path: ownedPath, trace: ownedTrace, scope: nextScope, returning: returning, ownedBytes: bytes)
    }
    private func push(_ step: Frame.Step, frame: inout Frame, meter: inout JSONWorkMeter) throws {
        try meter.work(); try meter.retain(16); frame.ownedBytes += 16; frame.steps.append(step)
    }
    private func pointer(_ path: [JSONLocationComponent], meter: inout JSONWorkMeter) throws -> JSONPointer {
        var tokens: [JSONKey] = []
        for component in path {
            try meter.work(); try meter.retain(16)
            switch component {
            case .key(let key): tokens.append(key)
            case .index(let i): try meter.work(20); tokens.append(try JSONKey(String(i),meter: &meter))
            }
        }
        let result = try JSONPointer.decodedTokens(tokens,meter: &meter)
        try meter.release(UInt64(tokens.count)*16); return result
    }
    private struct DiagnosticOmission: Error {}
    private func outputAdding(_ metric: JSONResourceMetric, _ current: UInt64, _ amount: UInt64,
                              meter: inout JSONWorkMeter) throws -> UInt64 {
        let (next, overflow) = current.addingReportingOverflow(amount)
        // Optional diagnostic output must not latch a terminal meter failure.
        // Overflow and every owned work/retention/annotation quota still throw.
        if !overflow, metric == .diagnosticBytes, options.diagnosticPolicy == .bestEffort,
           next > meter.limits[metric] { throw DiagnosticOmission() }
        return try meter.adding(metric, current, amount)
    }
    private func outputSize(_ keyword: Keyword?, frame: Frame, metric: JSONResourceMetric = .diagnosticBytes, meter: inout JSONWorkMeter) throws -> UInt64 {
        // Conservative encoded UTF-8 admission, including both Pointer locations and the absolute URI.
        var size: UInt64 = 64
        for component in frame.path {
            try meter.work(); size = try outputAdding(metric,size,16 + 1,meter: &meter)
            switch component {
            case .index: size = try outputAdding(metric,size,20,meter: &meter)
            case .key(let key):
                for byte in key.string.utf8 { try meter.work(); size = try outputAdding(metric,size,byte == 47 || byte == 126 ? 2 : 1,meter: &meter) }
            }
        }
        for key in frame.trace {
            try meter.work(); size = try outputAdding(metric,size,17,meter: &meter)
            for byte in key.string.utf8 { try meter.work(); size = try outputAdding(metric,size,byte == 47 || byte == 126 ? 2 : 1,meter: &meter) }
        }
        let node = plan.nodes[frame.node], root = plan.resources[node.resource].root
        for _ in plan.resources[node.resource].uri.string.utf8 { try meter.work(); size = try outputAdding(metric,size,1,meter: &meter) }
        for key in node.pointer.tokens.dropFirst(plan.nodes[root].pointer.tokens.count) {
            size = try outputAdding(metric,size,17,meter: &meter)
            for byte in key.string.utf8 { try meter.work(); size = try outputAdding(metric,size,byte == 47 || byte == 126 ? 6 : 3,meter: &meter) }
        }
        if let keyword { for _ in keyword.rawValue.utf8 { try meter.work(); size = try outputAdding(metric,size,4,meter: &meter) }; size = try outputAdding(metric,size,34,meter: &meter) }
        return size
    }
    private func locations(_ key: JSONKey?, frame: Frame, meter: inout JSONWorkMeter) throws -> (JSONPointer,JSONPointer,JSONSchemaURI) {
        let instance = try pointer(frame.path,meter: &meter)
        let tokens = [AnySequence(frame.trace),AnySequence(key.map { CollectionOfOne($0) } ?? CollectionOfOne(JSONKey("")))].lazy.flatMap { $0 }
        let relative = key == nil ? try JSONPointer.decodedTokens(frame.trace,meter: &meter) : try JSONPointer.decodedTokens(tokens,meter: &meter)
        let node = plan.nodes[frame.node], root = plan.resources[node.resource].root
        var bytes: [UInt8] = []
        func append(_ byte: UInt8, meter: inout JSONWorkMeter) throws { try meter.work(); try meter.require(.stringBytes,UInt64(bytes.count)+1); try meter.retain(1); bytes.append(byte) }
        for byte in plan.resources[node.resource].uri.string.utf8 { try append(byte,meter: &meter) }
        try append(35,meter: &meter)
        let resourceTokens = [AnySequence(node.pointer.tokens.dropFirst(plan.nodes[root].pointer.tokens.count)),AnySequence(key.map { CollectionOfOne($0) } ?? CollectionOfOne(JSONKey("")))].lazy.flatMap { $0 }
        var remaining = node.pointer.tokens.count - plan.nodes[root].pointer.tokens.count + (key == nil ? 0 : 1)
        for token in resourceTokens {
            if remaining == 0 { break }; remaining -= 1
            try append(47,meter: &meter)
            for byte in token.string.utf8 {
                try meter.work()
                if byte == 47 || byte == 126 { try append(126,meter: &meter); try append(byte == 47 ? 49 : 48,meter: &meter) }
                else if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || [45,46,95,33,36,38,39,40,41,42,43,44,59,61,58,64,63].contains(byte) {
                    try append(byte,meter: &meter)
                } else {
                    func hex(_ nibble: UInt8) -> UInt8 { nibble < 10 ? nibble+48 : nibble+55 }
                    try append(37,meter: &meter)
                    try append(hex(byte >> 4),meter: &meter); try append(hex(byte & 15),meter: &meter)
                }
            }
        }
        try meter.retain(UInt64(bytes.count))
        let text = String(decoding: bytes,as: UTF8.self)
        let absolute = try JSONSchemaURI.parse(text,relativeTo: nil,meter: &meter)
        try meter.release(UInt64(bytes.count)*2)
        return (instance,relative,absolute)
    }
    private func issue(_ keyword: Keyword?, frame: inout Frame, meter: inout JSONWorkMeter) throws {
        frame.outcome.valid = false
        if options.output == .flag { return }
        let size: UInt64
        do { size = try outputSize(keyword,frame: frame,meter: &meter) }
        catch is DiagnosticOmission {
            frame.outcome.diagnosticsComplete = false; return
        }
        let fits = meter.used(.issues) < meter.limits[.issues] && size <= meter.limits[.diagnosticBytes] - min(meter.used(.diagnosticBytes),meter.limits[.diagnosticBytes])
        if !fits && options.diagnosticPolicy == .bestEffort { frame.outcome.diagnosticsComplete = false; return }
        try meter.charge(.issues); try meter.charge(.diagnosticBytes,size)
        let before = meter.used(.retainedBytes)
        let key = try JSONKey(keyword?.rawValue ?? "",meter: &meter)
        let (instance,relative,absolute) = try locations(keyword == nil ? nil : key,frame: frame,meter: &meter)
        try meter.retain(64)
        frame.outcome.ownedIssueBytes += meter.used(.retainedBytes)-before
        frame.outcome.issues.append(.init(instanceLocation: instance,keywordLocation: relative,absoluteKeywordLocation: absolute,keyword: key))
    }
    private func annotations(_ frame: inout Frame, meter: inout JSONWorkMeter) throws {
        guard frame.outcome.valid, options.collectAnnotations, let object = plan.nodes[frame.node].raw.objectValue else { return }
        let node = plan.nodes[frame.node]
        for member in object {
            try meter.work()
            let keyword = try Keyword.classify(member.key,meter: &meter)
            let include: Bool
            if let keyword, node.vocabulary.applies(keyword) {
                switch keyword {
                case .title,.description,.default,.examples,.deprecated,.readOnly,.writeOnly: include = true
                case .format,.contentEncoding,.contentMediaType,.contentSchema: include = frame.instance.stringValue != nil
                default: include = false
                }
            } else { include = true }
            guard include else { continue }
            try annotation(member.value,key: member.key,keyword: keyword,frame: &frame,meter: &meter)
        }
    }
    private func annotation(_ value: JSON,key: JSONKey,keyword: Keyword?,frame: inout Frame,meter: inout JSONWorkMeter) throws {
            try meter.charge(.annotationEntries)
            var bytes: UInt64 = JSONLogicalWeights.annotationEntry
            try meter.charge(.annotationBytes,bytes)
            var cursor = JSONWritingCursor(value: value,options: .init())
            while try cursor.next(meter: &meter) != nil { try meter.work(); try meter.charge(.annotationBytes); bytes += 1 }
            var locationBytes = try outputSize(keyword,frame: frame,metric: .annotationBytes,meter: &meter)
            // Unknown keyword spelling is also bounded before output construction.
            if keyword == nil { for _ in key.string.utf8 { try meter.work(); locationBytes = try meter.adding(.annotationBytes,locationBytes,4) } }
            try meter.charge(.annotationBytes,locationBytes); bytes += locationBytes
            let before = meter.used(.retainedBytes)
            let (instance,relative,absolute) = try locations(key,frame: frame,meter: &meter)
            try meter.retain(bytes + 64)
            frame.outcome.ownedAnnotationBytes += bytes
            frame.outcome.ownedAnnotationOutputBytes += meter.used(.retainedBytes)-before
            frame.outcome.annotations.append(.init(instanceLocation: instance,keywordLocation: relative,absoluteKeywordLocation: absolute,keyword: key,value: value))
    }
    private func capture(_ keyword: Keyword,frame: inout Frame,meter: inout JSONWorkMeter) throws -> Int {
        for i in frame.applicatorAnnotations.indices { try meter.work(); if frame.applicatorAnnotations[i].keyword == keyword { return i } }
        try meter.charge(.annotationEntries); try meter.charge(.annotationBytes,32); try meter.retain(32); frame.ownedBytes += 32
        frame.applicatorAnnotations.append(.init(keyword: keyword)); return frame.applicatorAnnotations.count-1
    }
    private func applicatorAnnotations(_ frame: inout Frame,meter: inout JSONWorkMeter) throws {
        guard options.collectAnnotations else { return }
        for capture in frame.applicatorAnnotations {
            try meter.work(); let keyword = capture.keyword
            let value: JSON
            switch keyword {
            case .properties,.patternProperties,.additionalProperties,.unevaluatedProperties:
                var values: [JSON] = []
                for key in capture.locations.keys {
                    try meter.work(); try meter.charge(.annotationBytes,48); try meter.retain(48)
                    frame.outcome.ownedAnnotationBytes += 48; frame.outcome.ownedAnnotationOutputBytes += 48
                    values.append(.string(key.string))
                }
                try meter.charge(.annotationBytes,32); try meter.retain(32); frame.outcome.ownedAnnotationBytes += 32; frame.outcome.ownedAnnotationOutputBytes += 32
                value = .array(values)
            case .contains:
                var values: [JSON] = []
                for index in capture.locations.items {
                    try meter.work(20,subsystem: .numericWorkUnits); try meter.charge(.annotationBytes,68); try meter.retain(68)
                    frame.outcome.ownedAnnotationBytes += 68; frame.outcome.ownedAnnotationOutputBytes += 68
                    values.append(.number(JSONNumber(integer: index)))
                }
                try meter.charge(.annotationBytes,32); try meter.retain(32); frame.outcome.ownedAnnotationBytes += 32; frame.outcome.ownedAnnotationOutputBytes += 32
                value = .array(values)
            case .prefixItems:
                guard let index = capture.locations.items.last else {
                    try meter.charge(.annotationBytes,32); try meter.retain(32); frame.outcome.ownedAnnotationBytes += 32; frame.outcome.ownedAnnotationOutputBytes += 32
                    value = .boolean(true)
                    try annotation(value,key: JSONKey(keyword.rawValue,meter: &meter),keyword: keyword,frame: &frame,meter: &meter)
                    continue
                }
                try meter.work(20,subsystem: .numericWorkUnits); try meter.charge(.annotationBytes,52); try meter.retain(52)
                frame.outcome.ownedAnnotationBytes += 52; frame.outcome.ownedAnnotationOutputBytes += 52
                value = .number(JSONNumber(integer: index))
            case .items,.unevaluatedItems:
                guard !capture.locations.items.isEmpty else { continue }
                try meter.charge(.annotationBytes,32); try meter.retain(32); frame.outcome.ownedAnnotationBytes += 32; frame.outcome.ownedAnnotationOutputBytes += 32
                value = .boolean(true)
            default: throw JSONSchemaEvaluationFailure(.backend)
            }
            try annotation(value,key: JSONKey(keyword.rawValue,meter: &meter),keyword: keyword,frame: &frame,meter: &meter)
        }
    }
    private func discardAnnotations(_ outcome: inout Frame.Outcome, meter: inout JSONWorkMeter) throws {
        try meter.release(outcome.ownedAnnotationOutputBytes); try meter.releaseAnnotationState(outcome.ownedAnnotationBytes)
        outcome.annotations = []; outcome.ownedAnnotationBytes = 0; outcome.ownedAnnotationOutputBytes = 0
    }
    private func release(_ outcome: inout Frame.Outcome, meter: inout JSONWorkMeter) throws {
        try outcome.evaluated.release(meter: &meter)
        try meter.release(outcome.ownedIssueBytes)
        try discardAnnotations(&outcome,meter: &meter)
        outcome = .init()
    }
    private func merge(_ child: inout Frame.Outcome, into parent: inout Frame.Outcome, evaluated: Bool, meter: inout JSONWorkMeter) throws {
        if evaluated { try parent.evaluated.merge(child.evaluated,meter: &meter) }
        for issue in child.issues { try meter.work(); try meter.retain(64); parent.issues.append(issue) }
        for annotation in child.annotations { try meter.work(); try meter.retain(64); parent.annotations.append(annotation) }
        try meter.release(UInt64(child.issues.count + child.annotations.count)*64)
        parent.ownedIssueBytes += child.ownedIssueBytes; child.ownedIssueBytes = 0
        parent.ownedAnnotationBytes += child.ownedAnnotationBytes; child.ownedAnnotationBytes = 0
        parent.ownedAnnotationOutputBytes += child.ownedAnnotationOutputBytes; child.ownedAnnotationOutputBytes = 0
        parent.diagnosticsComplete = parent.diagnosticsComplete && child.diagnosticsComplete
        child.issues = []; child.annotations = []
    }
    private func initialize(_ frame: inout Frame, meter: inout JSONWorkMeter) throws {
        let node = plan.nodes[frame.node]
        if let boolean = node.raw.booleanValue {
            if !boolean { try issue(nil,frame: &frame,meter: &meter) }
            try push(.finish,frame: &frame,meter: &meter); return
        }
        for member in node.raw.objectValue! {
            try meter.work()
            guard let keyword = try Keyword.classify(member.key,meter: &meter), node.vocabulary.applies(keyword) else { continue }
            if try !JSONSchemaAssertions.test(keyword,declaration: member.value,instance: frame.instance,meter: &meter) {
                try issue(keyword,frame: &frame,meter: &meter)
            }
        }
        if let subject = frame.instance.stringValue {
            for pattern in node.patterns {
                try meter.work(); guard pattern.keyword == .pattern else { continue }; if try !pattern.program.search(subject,meter: &meter) { try issue(.pattern,frame: &frame,meter: &meter) }
            }
            if options.formatAssertion || node.formatAssertion, try node.raw.objectValue!.lookup("format",meter: &meter) != nil {
                let declaration = try node.raw.objectValue!.lookup("format",meter: &meter)!.stringValue!
                if let name = try JSONSchemaFormats.name(declaration,meter: &meter),
                   try !JSONSchemaFormats.test(subject,name: name,meter: &meter) { try issue(.format,frame: &frame,meter: &meter) }
            }
        }
        if options.collectAnnotations, frame.instance.objectValue != nil {
            for keyword in [Keyword.properties,.patternProperties,.additionalProperties,.unevaluatedProperties] {
                if node.vocabulary.applies(keyword), try node.raw.objectValue!.lookup(keyword.rawValue,meter: &meter) != nil { _ = try capture(keyword,frame: &frame,meter: &meter) }
            }
        }
        if options.collectAnnotations, frame.instance.arrayValue?.isEmpty == true,
           node.vocabulary.applies(.prefixItems), try node.raw.objectValue!.lookup("prefixItems",meter: &meter) != nil { _ = try capture(.prefixItems,frame: &frame,meter: &meter) }
        let steps: [Frame.Step] = [.references(0), .composition(.allOf,0,0), .composition(.anyOf,0,0), .composition(.oneOf,0,0),
            .composition(.not,0,0), .condition, .properties(0,0,false), .patterns(0,0,false), .additionalProperties(0), .propertyNames(0),
            .dependentSchemas(0), .prefixItems(0), .items(0), .contains(0,0), .unevaluatedProperties(0), .unevaluatedItems(0), .finish]
        for step in steps.reversed() { try push(step,frame: &frame,meter: &meter) }
    }
    private func children(_ keyword: Keyword, node: Int, index: Int, meter: inout JSONWorkMeter) throws -> (Int,JSONSchemaPlan.Child)? {
        let values = plan.nodes[node].children
        if index >= values.count { return nil }
        for i in index..<values.count { try meter.work(); if values[i].keyword == keyword { return (i,values[i]) } }
        return nil
    }
    private func ordinal(_ keyword: Keyword, node: Int, ordinal: Int, meter: inout JSONWorkMeter) throws -> JSONSchemaPlan.Child? {
        var found = 0
        for child in plan.nodes[node].children { try meter.work(); if child.keyword == keyword { if found == ordinal { return child }; found += 1 } }
        return nil
    }
    private func trace(_ frame: Frame, keyword: Keyword, token: JSONKey?, meter: inout JSONWorkMeter) throws -> [JSONKey] {
        var result: [JSONKey] = []
        for key in frame.trace { try meter.work(); try meter.retain(16); result.append(key) }
        try meter.retain(16); result.append(try JSONKey(keyword.rawValue,meter: &meter))
        if let token { try meter.retain(16); result.append(token) }
        return result
    }
    private struct Request { let child: JSONSchemaPlan.Child; let instance: JSON; let component: JSONLocationComponent?; let returning: Frame.Return }
    private func accept(_ child: inout Frame.Outcome, returning: Frame.Return, frame: inout Frame, meter: inout JSONWorkMeter) throws {
        switch returning {
        case .reference, .dependency:
            frame.outcome.valid = frame.outcome.valid && child.valid
            try merge(&child,into: &frame.outcome,evaluated: child.valid,meter: &meter)
        case .property(let keyword,let key):
            frame.outcome.valid = frame.outcome.valid && child.valid
            if child.valid { try frame.outcome.evaluated.insert(key,meter: &meter); if options.collectAnnotations { let i = try capture(keyword,frame: &frame,meter: &meter); try frame.applicatorAnnotations[i].locations.insert(key,meter: &meter) } }
            try merge(&child,into: &frame.outcome,evaluated: false,meter: &meter)
        case .item(let keyword,let index):
            frame.outcome.valid = frame.outcome.valid && child.valid
            if child.valid { try frame.outcome.evaluated.insert(index,meter: &meter); if options.collectAnnotations { let i = try capture(keyword,frame: &frame,meter: &meter); try frame.applicatorAnnotations[i].locations.insert(index,meter: &meter) } }
            try merge(&child,into: &frame.outcome,evaluated: false,meter: &meter)
        case .propertyName:
            frame.outcome.valid = frame.outcome.valid && child.valid
            try merge(&child,into: &frame.outcome,evaluated: false,meter: &meter)
        case .composition(let keyword):
            if keyword == .not {
                if child.valid { try issue(.not,frame: &frame,meter: &meter) }
            } else if keyword == .allOf {
                frame.outcome.valid = frame.outcome.valid && child.valid
                try merge(&child,into: &frame.outcome,evaluated: child.valid,meter: &meter)
            } else {
                guard case .composition(let key,let index,let matches) = frame.steps.last else { throw JSONSchemaEvaluationFailure(.backend) }
                frame.steps[frame.steps.count-1] = .composition(key,index,matches+(child.valid ? 1 : 0))
                if child.valid { try merge(&child,into: &frame.branch,evaluated: true,meter: &meter) }
            }
        case .condition:
            let keyword: Keyword = child.valid ? .then : .else
            if child.valid { try merge(&child,into: &frame.outcome,evaluated: true,meter: &meter) }
            if try children(keyword,node: frame.node,index: 0,meter: &meter) != nil {
                try push(.composition(keyword,0,0),frame: &frame,meter: &meter)
            }
        case .contains(let index):
            guard case .contains(let next,let count) = frame.steps.last else { throw JSONSchemaEvaluationFailure(.backend) }
            frame.steps[frame.steps.count-1] = .contains(next,count+(child.valid ? 1 : 0))
            if child.valid { try frame.containsMatches.insert(index,meter: &meter); try merge(&child,into: &frame.branch,evaluated: false,meter: &meter) }
        }
        try release(&child,meter: &meter)
    }
    package mutating func evaluate(_ instance: JSON, at root: Int, meter: inout JSONWorkMeter) throws -> JSONValidationResult {
        meter.schemaEvaluationPhase(true)
        defer { meter.schemaEvaluationPhase(false) }
        var frames: [Frame] = []
        do {
            var first = try makeFrame(node: root,instance: instance,path: [],trace: [],scope: [],returning: nil,ancestors: [],meter: &meter)
            try initialize(&first,meter: &meter); frames.append(first)
        }
        while !frames.isEmpty {
            try meter.work()
            var frame = frames.removeLast()
            guard let step = frame.steps.popLast() else { throw JSONSchemaEvaluationFailure(.backend) }
            try meter.release(16); frame.ownedBytes -= 16
            if case .finish = step {
                if frame.outcome.valid { try applicatorAnnotations(&frame,meter: &meter); try annotations(&frame,meter: &meter) }
                else { try discardAnnotations(&frame.outcome,meter: &meter) }
                while var capture = frame.applicatorAnnotations.popLast() {
                    try meter.work(); try capture.locations.release(meter: &meter); try meter.releaseAnnotationState(32); try meter.release(32); frame.ownedBytes -= 32
                }
                try frame.staticProperties.release(meter: &meter); try frame.containsMatches.release(meter: &meter)
                try release(&frame.branch,meter: &meter); try meter.release(frame.ownedBytes)
                if let returning = frame.returning {
                    guard !frames.isEmpty else { throw JSONSchemaEvaluationFailure(.backend) }
                    try accept(&frame.outcome,returning: returning,frame: &frames[frames.count-1],meter: &meter)
                } else {
                    try frame.outcome.evaluated.release(meter: &meter)
                    return .init(isValid: frame.outcome.valid,outputStyle: options.output,issues: frame.outcome.issues,annotations: frame.outcome.annotations,diagnosticsComplete: frame.outcome.diagnosticsComplete)
                }
                continue
            }
            let request = try dispatch(step,frame: &frame,meter: &meter)
            frames.append(frame)
            if let request {
                var path: [JSONLocationComponent] = []
                for component in frame.path { try meter.work(); try meter.retain(16); path.append(component) }
                if let component = request.component { try meter.retain(16); path.append(component) }
                let trace = try trace(frame,keyword: request.child.keyword,token: request.child.token,meter: &meter)
                var next = try makeFrame(node: request.child.target,instance: request.instance,path: path,trace: trace,scope: frame.scope,
                                         returning: request.returning,ancestors: frames,meter: &meter)
                try meter.release(UInt64(trace.count + path.count)*16)
                try initialize(&next,meter: &meter); frames.append(next)
            }
        }
        throw JSONSchemaEvaluationFailure(.backend)
    }
    private func dispatch(_ step: Frame.Step, frame: inout Frame, meter: inout JSONWorkMeter) throws -> Request? {
        let node = plan.nodes[frame.node]
        switch step {
        case .references(let index):
            guard index < node.references.count else { return nil }
            let reference = node.references[index]
            var target = reference.target
            if let name = reference.dynamicAnchor {
                outer: for resource in frame.scope {
                    try meter.work()
                    for anchor in plan.resources[resource].anchors {
                        try meter.work()
                        if anchor.dynamic, try JSONComparison.textEquals(anchor.name.string,name.string,meter: &meter) {
                            target = anchor.node; break outer
                        }
                    }
                }
            }
            try push(.references(index+1),frame: &frame,meter: &meter)
            return .init(child: .init(keyword: reference.keyword,token: nil,target: target),instance: frame.instance,component: nil,returning: .reference)
        case .composition(let keyword,let cursor,let matches):
            if let (index,child) = try children(keyword,node: frame.node,index: cursor,meter: &meter) {
                try push(.composition(keyword,index+1,matches),frame: &frame,meter: &meter)
                let returning: Frame.Return = keyword == .then || keyword == .else ? .dependency : .composition(keyword)
                return .init(child: child,instance: frame.instance,component: nil,returning: returning)
            }
            if keyword == .anyOf || keyword == .oneOf {
                guard try children(keyword,node: frame.node,index: 0,meter: &meter) != nil else { return nil }
                if matches > 0 && (keyword != .oneOf || matches == 1) {
                    try merge(&frame.branch,into: &frame.outcome,evaluated: true,meter: &meter)
                } else { try issue(keyword,frame: &frame,meter: &meter) }
                try release(&frame.branch,meter: &meter)
            }
            return nil
        case .condition:
            guard let (_,child) = try children(.if,node: frame.node,index: 0,meter: &meter) else { return nil }
            return .init(child: child,instance: frame.instance,component: nil,returning: .condition)
        case .properties(let memberIndex,_,_):
            guard let object = frame.instance.objectValue else { return nil }
            for i in memberIndex..<object.count {
                let member = object[i]
                for child in node.children {
                    try meter.work()
                    if child.keyword == .properties, let key = child.token,
                       try JSONComparison.textEquals(key.string,member.key.string,meter: &meter) {
                        try frame.staticProperties.insert(member.key,meter: &meter)
                        try push(.properties(i+1,0,false),frame: &frame,meter: &meter)
                        return .init(child: child,instance: member.value,component: .key(member.key),returning: .property(child.keyword,member.key))
                    }
                }
            }
            return nil
        case .patterns(let memberIndex,let patternIndex,_):
            guard let object = frame.instance.objectValue else { return nil }
            for i in memberIndex..<object.count {
                let member = object[i]
                for p in (i == memberIndex ? patternIndex : 0)..<node.patterns.count {
                    try meter.work()
                    let pattern = node.patterns[p]
                    guard pattern.keyword == .patternProperties, let key = pattern.key else { continue }
                    if try pattern.program.search(member.key.string,meter: &meter) {
                        try frame.staticProperties.insert(member.key,meter: &meter)
                        for child in node.children {
                            try meter.work()
                            if child.keyword == .patternProperties, let token = child.token,
                               try JSONComparison.textEquals(token.string,key.string,meter: &meter) {
                                try push(.patterns(i,p+1,false),frame: &frame,meter: &meter)
                                return .init(child: child,instance: member.value,component: .key(member.key),returning: .property(child.keyword,member.key))
                            }
                        }
                        throw JSONSchemaEvaluationFailure(.backend)
                    }
                }
            }
            return nil
        case .additionalProperties(let start):
            guard let object = frame.instance.objectValue,
                  let (_,child) = try children(.additionalProperties,node: frame.node,index: 0,meter: &meter) else { return nil }
            for i in start..<object.count {
                try meter.work(); let member = object[i]
                if try !frame.staticProperties.contains(member.key,meter: &meter) {
                    try push(.additionalProperties(i+1),frame: &frame,meter: &meter)
                    return .init(child: child,instance: member.value,component: .key(member.key),returning: .property(child.keyword,member.key))
                }
            }
            return nil
        case .propertyNames(let index):
            guard let object = frame.instance.objectValue, index < object.count,
                  let (_,child) = try children(.propertyNames,node: frame.node,index: 0,meter: &meter) else { return nil }
            let member = object[index]
            try push(.propertyNames(index+1),frame: &frame,meter: &meter)
            return .init(child: child,instance: .string(member.key.string),component: .key(member.key),returning: .propertyName)
        case .dependentSchemas(let cursor):
            guard let object = frame.instance.objectValue else { return nil }
            var next = cursor
            while let (index,child) = try children(.dependentSchemas,node: frame.node,index: next,meter: &meter) {
                next = index+1
                if let key = child.token, try object.lookup(key.string,meter: &meter) != nil {
                    try push(.dependentSchemas(next),frame: &frame,meter: &meter)
                    return .init(child: child,instance: frame.instance,component: nil,returning: .dependency)
                }
            }
            return nil
        case .prefixItems(let index):
            guard let array = frame.instance.arrayValue, index < array.count,
                  let child = try ordinal(.prefixItems,node: frame.node,ordinal: index,meter: &meter) else { return nil }
            try push(.prefixItems(index+1),frame: &frame,meter: &meter)
            return .init(child: child,instance: array[index],component: .index(index),returning: .item(child.keyword,index))
        case .items(let next):
            guard let array = frame.instance.arrayValue,
                  let (_,child) = try children(.items,node: frame.node,index: 0,meter: &meter) else { return nil }
            var prefix = 0
            for candidate in node.children { try meter.work(); if candidate.keyword == .prefixItems { prefix += 1 } }
            let index = max(next,prefix)
            guard index < array.count else { return nil }
            try push(.items(index+1),frame: &frame,meter: &meter)
            return .init(child: child,instance: array[index],component: .index(index),returning: .item(child.keyword,index))
        case .contains(let index,let matches):
            guard let array = frame.instance.arrayValue,
                  let (_,child) = try children(.contains,node: frame.node,index: 0,meter: &meter) else { return nil }
            if index < array.count {
                try push(.contains(index+1,matches),frame: &frame,meter: &meter)
                return .init(child: child,instance: array[index],component: .index(index),returning: .contains(index))
            }
            try meter.work(20,subsystem: .numericWorkUnits)
            let count = JSONNumber(integer: matches)
            let minimum = node.vocabulary.contains(.validation) ? (try node.raw.objectValue!.lookup("minContains",meter: &meter)?.numberValue ?? JSONNumber(integer: 1)) : JSONNumber(integer: 1)
            let maximum = node.vocabulary.contains(.validation) ? (try node.raw.objectValue!.lookup("maxContains",meter: &meter)?.numberValue) : nil
            var valid = try count.compare(to: minimum,meter: &meter) != .orderedAscending
            if let maximum { valid = try count.compare(to: maximum,meter: &meter) != .orderedDescending && valid }
            if valid {
                if options.collectAnnotations { let i = try capture(.contains,frame: &frame,meter: &meter); try frame.applicatorAnnotations[i].locations.merge(frame.containsMatches,meter: &meter) }
                try frame.outcome.evaluated.merge(frame.containsMatches,meter: &meter)
                try merge(&frame.branch,into: &frame.outcome,evaluated: false,meter: &meter)
            } else { try issue(.contains,frame: &frame,meter: &meter) }
            try frame.containsMatches.release(meter: &meter); try release(&frame.branch,meter: &meter)
            return nil
        case .unevaluatedProperties(let start):
            guard let object = frame.instance.objectValue,
                  let (_,child) = try children(.unevaluatedProperties,node: frame.node,index: 0,meter: &meter) else { return nil }
            for i in start..<object.count {
                try meter.work(); let member = object[i]
                if try !frame.outcome.evaluated.contains(member.key,meter: &meter) {
                    try push(.unevaluatedProperties(i+1),frame: &frame,meter: &meter)
                    return .init(child: child,instance: member.value,component: .key(member.key),returning: .property(child.keyword,member.key))
                }
            }
            return nil
        case .unevaluatedItems(let start):
            guard let array = frame.instance.arrayValue,
                  let (_,child) = try children(.unevaluatedItems,node: frame.node,index: 0,meter: &meter) else { return nil }
            for i in start..<array.count {
                try meter.work()
                if try !frame.outcome.evaluated.contains(i,meter: &meter) {
                    try push(.unevaluatedItems(i+1),frame: &frame,meter: &meter)
                    return .init(child: child,instance: array[i],component: .index(i),returning: .item(child.keyword,i))
                }
            }
            return nil
        case .finish: throw JSONSchemaEvaluationFailure(.backend)
        }
    }
}
