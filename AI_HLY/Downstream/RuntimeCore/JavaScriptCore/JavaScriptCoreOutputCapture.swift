import CryptoKit
import Foundation

/// Confined to the synchronous JavaScriptCore evaluation queue. Full bytes are
/// written as produced; only the result's inline previews are bounded.
final class JavaScriptCoreOutputCapture {
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let directory: URL
    var failure: (any Error)?

    init(directory: URL) throws {
        self.directory = directory
        let output = directory.appending(path: "stdout.log")
        let errors = directory.appending(path: "stderr.log")
        guard FileManager.default.createFile(atPath: output.path, contents: nil),
              FileManager.default.createFile(atPath: errors.path, contents: nil) else {
            throw RuntimeCoreError.runtimeFailure("JavaScriptCore output files could not be created; the job directory is retained.")
        }
        stdout = try FileHandle(forWritingTo: output)
        do { stderr = try FileHandle(forWritingTo: errors) }
        catch { try? stdout.close(); throw error }
    }

    func close() { try? stdout.close(); try? stderr.close() }

    func append(_ text: String, isError: Bool) throws {
        try (isError ? stderr : stdout).write(contentsOf: Data(text.utf8))
    }

    func result(id: UUID, value: RuntimeJSONValue?, exitCode: Int, milliseconds: Int64, previewBytes: Int) throws -> RuntimeExecutionResult {
        try stdout.synchronize()
        try stderr.synchronize()
        var artifacts: [String: RuntimeOutputArtifact] = [:]
        var previews: [String: String] = [:]
        var remaining = max(0, previewBytes)
        for channel in ["stdout", "stderr"] {
            let url = directory.appending(path: channel + ".log")
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            var digest = SHA256()
            var count: Int64 = 0
            var preview = Data()
            while let data = try reader.read(upToCount: 65_536), !data.isEmpty {
                digest.update(data: data)
                count += Int64(data.count)
                let bytes = min(remaining, data.count)
                preview.append(data.prefix(bytes))
                remaining -= bytes
            }
            artifacts[channel] = .init(path: url.path, bytes: count, sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
            previews[channel] = String(decoding: preview, as: UTF8.self)
        }
        return RuntimeExecutionResult(executionID: id, stdout: previews["stdout"] ?? "", stderr: previews["stderr"] ?? "", value: value,
            exitCode: exitCode, durationMilliseconds: milliseconds, didTimeOut: false, wasCancelled: false,
            outputWasTruncated: artifacts.values.reduce(Int64(0)) { $0 + $1.bytes } > previewBytes, outputFiles: artifacts)
    }
}
