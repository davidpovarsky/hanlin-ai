// SPDX-License-Identifier: Apache-2.0
import Foundation
import JSON
extension JSONSchemaRegistry {
    /// Loads the integrity-checked packaged Draft 2020-12 meta-schema registry.
    ///
    /// - Returns: Explicit immutable official resources with retained provenance.
    /// - Throws: Missing/corrupt packaged resource, parsing, resource or configuration errors, or cancellation.
    ///
    /// - Parameters:
    ///   - limits: Finite inclusive capacities and work quotas for this call.
    public static func draft2020_12(limits: JSONLimits = .balanced) throws -> Self {
        var meter = try JSONWorkMeter(limits: limits, domain: .schemaCompilation)
        return try Self(admitted: loadBuiltins(meter: &meter))
    }
    package static func loadBuiltins(meter: inout JSONWorkMeter) throws -> [JSONSchemaDocument] {
        let files: [(String, String, UInt64, String)] = [
            ("schema.json", "https://json-schema.org/draft/2020-12/schema", 2452, "41da76f5afb7ce062d248f762463a92f7ca47e4e0f905b224ba6afeef91ded0f"),
            ("meta/applicator.json", "https://json-schema.org/draft/2020-12/meta/applicator", 1659, "c4a6e4147b91fef7fea6dc058cb1bf93402f7414b76578a8b16aaf1dad6aacef"),
            ("meta/content.json", "https://json-schema.org/draft/2020-12/meta/content", 519, "08343747764e4a5814262793cf4d652057a7913863c5950d43297e8e1fdac5b6"),
            ("meta/core.json", "https://json-schema.org/draft/2020-12/meta/core", 1564, "c2d12a8e4dd11d336dfc83a3f663aa4c69f0b49b3beb094ffeb25b5316f4803d"),
            ("meta/format-annotation.json", "https://json-schema.org/draft/2020-12/meta/format-annotation", 448, "abc775adfefd89d22358170d9bf93f4ebd2349563bbbedd60f02bef7c812bcc0"),
            ("meta/format-assertion.json", "https://json-schema.org/draft/2020-12/meta/format-assertion", 445, "c52242b9a1bb786b26c3e82c7add428c31f9c96e575dce99e56ea5feaa6da20c"),
            ("meta/meta-data.json", "https://json-schema.org/draft/2020-12/meta/meta-data", 892, "8f76d6e14f41b9b92ef933b708cdc5144c8b5268651ad11918485fb1754f1c76"),
            ("meta/unevaluated.json", "https://json-schema.org/draft/2020-12/meta/unevaluated", 506, "2dbfbcb73994b670b0976492adee1fffb46c21682784d2f5a4ca561f9e2d0cb4"),
            ("meta/validation.json", "https://json-schema.org/draft/2020-12/meta/validation", 2834, "7010a31e541f32d2be721e2de348df75c9b36876a3ed304877fc0abda1d37a58"),
        ]
        _ = try meter.adding(.schemaDocuments, meter.used(.schemaDocuments), UInt64(files.count))
        var documents: [JSONSchemaDocument] = []
        #if os(WASI)
        // SwiftPM Bundle.module calls Foundation Bundle.main, which traps when
        // no directory is preopened. Resolve the documented command-relative
        // bundle directly so missing permissions/resources throw a schema error.
        guard let command = CommandLine.arguments.first, command.hasPrefix("/") else {
            throw JSONSchemaCompilationFailure(.metaSchema)
        }
        let root = URL(fileURLWithPath: command).deletingLastPathComponent()
            .appendingPathComponent("HanlinAgentSDK_HanlinExactJSONSchema.bundle", isDirectory: true)
        #else
        // The generated Bundle.module accessor traps if packaging is incomplete.
        // Resolve the same app/framework/command layouts through checked lookup.
        var candidates: [URL] = []
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        #endif
        if let directory = Bundle.main.resourceURL { candidates.append(directory) }
        #if canImport(ObjectiveC)
        let codeBundle = Bundle(for: JSONSchemaBundleAnchor.self)
        if let directory = codeBundle.resourceURL { candidates.append(directory) }
        #endif
        candidates.append(Bundle.main.bundleURL)
        if let command = CommandLine.arguments.first {
            candidates.append(URL(fileURLWithPath: command).deletingLastPathComponent())
        }
        #if canImport(ObjectiveC)
        // Native SwiftPM uses a helper as Bundle.main. The code-owner .xctest
        // bundle has sibling resources. Search that fixed layout last; existing
        // locations and corruption pins remain authoritative.
        let ownerBundle = codeBundle.bundleURL
        if ownerBundle.pathExtension == "xctest" {
            candidates.append(ownerBundle.deletingLastPathComponent())
        }
        #endif
        let root = try builtinResourceRoot(in: candidates, meter: &meter)
        #endif
        for (path, identifier, size, expectedHash) in files {
            try meter.checkpoint(); try meter.charge(.schemaDocuments); try meter.resetValueBounds()
            try meter.require(.inputBytes, size); try meter.charge(.schemaBytes, size); try meter.retain(size)
            let url = root.appendingPathComponent("Draft2020-12").appendingPathComponent(path)
            let handle: FileHandle
            do { handle = try FileHandle(forReadingFrom: url) }
            catch { throw JSONSchemaCompilationFailure(.metaSchema) }
            defer { try? handle.close() }
            var data = Data()
            while UInt64(data.count) < size {
                let amount = min(Int(size) - data.count, 1024)
                try meter.checkpoint(); try meter.retain(UInt64(amount))
                let chunk: Data
                do { chunk = try handle.read(upToCount: amount) ?? Data() }
                catch { throw JSONSchemaCompilationFailure(.metaSchema) }
                guard !chunk.isEmpty else { throw JSONSchemaCompilationFailure(.metaSchema) }
                for _ in chunk { try meter.work() }
                data.append(chunk)
                try meter.release(UInt64(amount))
            }
            try meter.checkpoint(); try meter.retain(1)
            do {
                guard try handle.read(upToCount: 1)?.isEmpty ?? true else { throw JSONSchemaCompilationFailure(.metaSchema) }
            } catch { throw JSONSchemaCompilationFailure(.metaSchema) }
            try meter.release(1)
            guard UInt64(data.count) == size else { throw JSONSchemaCompilationFailure(.metaSchema) }
            try verifyBuiltin(data, size: size, expectedHash: expectedHash, meter: &meter)
            var bytes: [UInt8] = []
            for byte in data { try meter.work(); try meter.retain(1); bytes.append(byte) }
            let raw = try JSONParser().parse(bytes, meter: &meter)
            switch raw { case .object, .boolean: break; default: throw JSONSchemaCompilationFailure(.metaSchema) }
            let uri = try JSONSchemaURI.parse(identifier, relativeTo: nil, meter: &meter)
            try meter.retain(JSONLogicalWeights.frame)
            documents.append(JSONSchemaDocument(admitted: raw, retrievalURI: uri))
            try meter.release(size * 2)
        }
        return documents
    }

    /// Fixed-layout lookup is checked; a present corrupt bundle is selected and
    /// rejected by the existing pins rather than bypassed via another candidate.
    package static func builtinResourceRoot(in candidates: [URL], meter: inout JSONWorkMeter) throws -> URL {
        for candidate in candidates {
            try meter.checkpoint()
            let pathBytes = UInt64(candidate.path.utf8.count)
            try meter.require(.stringBytes, pathBytes)
            try meter.work(pathBytes + 1)
            try meter.retain(pathBytes + 128)
            defer { try? meter.release(pathBytes + 128) }
            // SwiftPM's Apple/Swift Build and Linux resource directory spellings.
            for name in ["HanlinAgentSDK_HanlinExactJSONSchema.bundle", "HanlinAgentSDK_HanlinExactJSONSchema.resources"] {
                try meter.work(UInt64(name.utf8.count) + 1)
                let url = candidate.appendingPathComponent(name, isDirectory: true)
                if let bundle = Bundle(url: url), let root = bundle.resourceURL { return root }
            }
        }
        throw JSONSchemaCompilationFailure(.metaSchema)
    }
    package static func verifyBuiltin(_ data: Data, size: UInt64, expectedHash: String,
                                      meter: inout JSONWorkMeter) throws {
        try meter.work()
        guard UInt64(data.count) == size else { throw JSONSchemaCompilationFailure(.metaSchema) }
        let hash = try JSONSHA256Core.hexadecimal(data, accounting: &meter)
        defer { try? meter.release(64) }
        try meter.work(64)
        guard hash.utf8.elementsEqual(expectedHash.utf8) else { throw JSONSchemaCompilationFailure(.metaSchema) }
    }
}

#if canImport(ObjectiveC)
private final class JSONSchemaBundleAnchor {}
#endif
