import Foundation
import HanlinPlatformContracts

public enum ReadSkillResourceTool {
    public static let toolName = "read_skill_resource"

    public static var schema: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": toolName,
                "description": "Read a resource file (such as reference documentation, scripts, templates, or prompt assets) from a previously loaded skill bundle. Use this tool when a skill's instructions mention additional resources or when you need detailed domain guidelines.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "skill_id": [
                            "type": "string",
                            "description": "The unique identifier of the loaded skill (e.g. 'code', 'web-search')."
                        ],
                        "relative_path": [
                            "type": "string",
                            "description": "Relative path to the resource file within the skill bundle (e.g. 'references/api_guide.md'). Traversal outside the skill root is prohibited."
                        ],
                        "line_offset": [
                            "type": "integer",
                            "description": "Optional 1-based line number to start reading from. Default is 1."
                        ],
                        "line_limit": [
                            "type": "integer",
                            "description": "Optional maximum number of lines to return. Default is 200 (maximum 1000)."
                        ]
                    ],
                    "required": ["skill_id", "relative_path"]
                ]
            ]
        ]
    }

    public struct Arguments: Decodable, Sendable {
        public let skill_id: String
        public let relative_path: String
        public let line_offset: Int?
        public let line_limit: Int?
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        catalog: HanlinSkillCatalog = .shared
    ) async -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Error: Invalid arguments for read_skill_resource. Expected JSON with 'skill_id' and 'relative_path'."
        }

        guard let skillID = try? HanlinSkillID(validating: args.skill_id) else {
            return "Error: Invalid skill ID format '\(args.skill_id)'."
        }

        guard session.isSkillLoaded(skillID) else {
            return "Error: Skill '\(args.skill_id)' is not currently loaded. Call load_skill first."
        }

        let cleanPath = args.relative_path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !cleanPath.isEmpty,
              !cleanPath.hasPrefix("/"),
              !cleanPath.contains("\0") else {
            return "Error: Invalid resource path '\(args.relative_path)'."
        }

        let components = cleanPath.split(separator: "/")
        if components.contains("..") || components.contains(".") {
            return "Error: Directory traversal is not permitted in resource paths."
        }

        guard let resourceURL = catalog.resolveResourceURL(skillID: skillID, relativePath: cleanPath) else {
            return "Error: Resource '\(args.relative_path)' not found in skill '\(args.skill_id)'."
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resourceURL.path) else {
            return "Error: Resource '\(args.relative_path)' not found in skill '\(args.skill_id)'."
        }

        guard let attr = try? fileManager.attributesOfItem(atPath: resourceURL.path),
              let fileSize = attr[.size] as? Int64 else {
            return "Error: Unable to read attributes for '\(args.relative_path)'."
        }

        if isBinaryFile(path: cleanPath) {
            let mime = mimeType(for: cleanPath)
            let formatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            return "Binary resource file: \(cleanPath) (\(formatted), MIME: \(mime)). Binary files cannot be displayed as text."
        }

        // Attempt reading text content
        guard let data = try? Data(contentsOf: resourceURL),
              let fullText = String(data: data, encoding: .utf8) else {
            let mime = mimeType(for: cleanPath)
            let formatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            return "Binary resource file: \(cleanPath) (\(formatted), MIME: \(mime)). File is not valid UTF-8 text."
        }

        let lines = fullText.components(separatedBy: "\n")
        let totalLines = lines.count

        let offset = max(1, args.line_offset ?? 1)
        let limit = min(1000, max(1, args.line_limit ?? 200))

        if offset > totalLines {
            return "File '\(cleanPath)' has \(totalLines) lines. Offset \(offset) is beyond the end of file."
        }

        let startIndex = offset - 1
        let endIndex = min(totalLines, startIndex + limit)
        let selectedLines = lines[startIndex..<endIndex]
        let content = selectedLines.joined(separator: "\n")

        var header = "Resource '\(cleanPath)' [lines \(offset)-\(endIndex) of \(totalLines)]:\n\n"
        var result = header + content

        if endIndex < totalLines {
            result += "\n\n[Truncated. Use line_offset=\(endIndex + 1) to read more lines.]"
        }

        return result
    }

    private static func isBinaryFile(path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let textExtensions: Set<String> = [
            "md", "txt", "json", "js", "ts", "py", "sh", "yaml", "yml", "csv", "xml", "html", "css", "swift", "m", "h", "c", "cpp"
        ]
        return !textExtensions.contains(ext)
    }

    private static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "text/markdown"
        case "txt": return "text/plain"
        case "json": return "application/json"
        case "js": return "application/javascript"
        case "ts": return "application/typescript"
        case "py": return "text/x-python"
        case "sh": return "text/x-shellscript"
        case "swift": return "text/x-swift"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}
