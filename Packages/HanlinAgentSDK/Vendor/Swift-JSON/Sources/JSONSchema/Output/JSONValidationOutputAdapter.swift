// SPDX-License-Identifier: Apache-2.0
import JSON

extension JSONValidationResult {
    /// Builds flag or basic Draft 2020-12 output from the diagnostics actually collected.
    ///
    /// Flag-only results cannot be upgraded to invent basic errors. Basic output preserves
    /// `diagnosticsComplete`; output construction is separately bounded.
    /// - Throws: Output-unavailable, resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - style: The requested rendering or output format.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func output(_ style: JSONValidationOutput? = nil, limits: JSONLimits = .balanced) throws -> JSON {
        try outputWithReport(style,limits: limits).result
    }
    /// Builds bounded validation output with successful output-construction accounting.
    ///
    /// - Returns: Flag/basic JSON and counts. It does not re-evaluate the instance.
    /// - Throws: Output-unavailable, resource or configuration failure, or cancellation.
    ///
    /// - Parameters:
    ///   - style: The requested rendering or output format.
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public func outputWithReport(_ style: JSONValidationOutput? = nil, limits: JSONLimits = .balanced) throws -> JSONOperationReport<JSON> {
        var meter = try JSONWorkMeter(limits: limits,domain: .core)
        let selected = style ?? outputStyle
        guard selected == .flag || outputStyle == .basic else { throw JSONSchemaEvaluationFailure(.outputUnavailable) }
        let value = try JSONValidationOutputAdapter.make(self,style: selected,meter: &meter)
        var cursor = JSONWritingCursor(value: value,options: .init()), size: UInt64 = 0
        while try cursor.next(meter: &meter) != nil { try meter.work(); size = try meter.adding(.outputBytes,size,1) }
        return .init(result: value,statistics: meter.statistics())
    }
}

private enum JSONValidationOutputAdapter {
    static func boolean(_ value: Bool,meter: inout JSONWorkMeter) throws -> JSON {
        try meter.work(); try meter.charge(.nodes); try meter.retain(JSONLogicalWeights.node); return .boolean(value)
    }
    static func string(_ value: String,meter: inout JSONWorkMeter) throws -> JSON {
        for _ in value.utf8 { try meter.work(); try meter.charge(.diagnosticBytes) }
        try JSONAdmission.text(value,meter: &meter,owned: true)
        try meter.charge(.nodes); try meter.retain(JSONLogicalWeights.node); return .string(value)
    }
    static func member(_ key: String,_ value: JSON,to members: inout [JSONMember],meter: inout JSONWorkMeter) throws {
        try meter.work(); try meter.require(.objectMembers,UInt64(members.count)+1)
        for _ in key.utf8 { try meter.work(); try meter.charge(.diagnosticBytes) }
        try JSONAdmission.text(key,key: true,meter: &meter,owned: true)
        try meter.retain(JSONLogicalWeights.member)
        members.append(.init(try JSONKey(key,meter: &meter),value: value))
    }
    static func object(_ members: [JSONMember],depth: UInt64,meter: inout JSONWorkMeter) throws -> JSON {
        try meter.require(.maxDepth,depth); try meter.charge(.nodes); try meter.retain(JSONLogicalWeights.node)
        return .object(try JSONObject.indexed(admitted: members, meter: &meter))
    }
    static func array(_ values: [JSON],meter: inout JSONWorkMeter) throws -> JSON {
        try meter.require(.maxDepth,2); try meter.charge(.nodes); try meter.retain(JSONLogicalWeights.node); return .array(values)
    }
    static func location(instance: JSONPointer,keyword: JSONPointer,absolute: JSONSchemaURI?,valid: Bool,meter: inout JSONWorkMeter) throws -> [JSONMember] {
        var members: [JSONMember] = []
        try member("valid",boolean(valid,meter: &meter),to: &members,meter: &meter)
        try member("keywordLocation",string(keyword.encodedString(meter: &meter),meter: &meter),to: &members,meter: &meter)
        try member("instanceLocation",string(instance.encodedString(meter: &meter),meter: &meter),to: &members,meter: &meter)
        if let absolute { try member("absoluteKeywordLocation",string(absolute.string,meter: &meter),to: &members,meter: &meter) }
        return members
    }
    static func make(_ result: JSONValidationResult,style: JSONValidationOutput,meter: inout JSONWorkMeter) throws -> JSON {
        var root: [JSONMember] = []
        try member("valid",boolean(result.isValid,meter: &meter),to: &root,meter: &meter)
        if style == .flag { return try object(root,depth: 1,meter: &meter) }
        try member("keywordLocation",string("",meter: &meter),to: &root,meter: &meter)
        try member("instanceLocation",string("",meter: &meter),to: &root,meter: &meter)
        try member("diagnosticsComplete",boolean(result.diagnosticsComplete,meter: &meter),to: &root,meter: &meter)
        var values: [JSON] = []
        if result.isValid {
            try meter.require(.annotationEntries,UInt64(result.annotations.count))
            for annotation in result.annotations {
                try meter.charge(.annotationEntries)
                try meter.work(); try meter.require(.arrayItems,UInt64(values.count)+1); try meter.retain(JSONLogicalWeights.arraySlot)
                var members = try location(instance: annotation.instanceLocation,keyword: annotation.keywordLocation,absolute: annotation.absoluteKeywordLocation,valid: true,meter: &meter)
                var annotationCursor = JSONWritingCursor(value: annotation.value,options: .init())
                while try annotationCursor.next(meter: &meter) != nil { try meter.work(); try meter.charge(.annotationBytes) }
                try JSONAdmission.value(annotation.value,meter: &meter,owned: true,depth: 3)
                try member("annotation",annotation.value,to: &members,meter: &meter)
                values.append(try object(members,depth: 3,meter: &meter))
            }
            try member("annotations",array(values,meter: &meter),to: &root,meter: &meter)
        } else {
            try meter.require(.issues,UInt64(result.issues.count))
            for issue in result.issues {
                try meter.charge(.issues)
                try meter.work(); try meter.require(.arrayItems,UInt64(values.count)+1); try meter.retain(JSONLogicalWeights.arraySlot)
                var members = try location(instance: issue.instanceLocation,keyword: issue.keywordLocation,absolute: issue.absoluteKeywordLocation,valid: false,meter: &meter)
                try member("error",string(issue.keyword.string.isEmpty ? "false schema" : issue.keyword.string,meter: &meter),to: &members,meter: &meter)
                values.append(try object(members,depth: 3,meter: &meter))
            }
            try member("errors",array(values,meter: &meter),to: &root,meter: &meter)
        }
        return try object(root,depth: 1,meter: &meter)
    }
}
