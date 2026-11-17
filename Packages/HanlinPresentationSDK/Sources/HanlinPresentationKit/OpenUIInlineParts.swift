import Foundation

/// Frames the documented inline fences. OpenUI syntax, expressions, bindings and
/// actions are interpreted exclusively by the pinned upstream OpenUI runtime.
public enum OpenUIInlineParts {
    public static func split(_ text: String, identity: PresentationMessageIdentity,
                             catalogs: [PresentationReference], isStreaming: Bool) -> [MessageRichPart] {
        var parts: [MessageRichPart] = []
        var markdown = ""
        var program = ""
        var target: OpenUIRenderTarget?
        var fenceLength = 0
        var ordinaryFenceLength = 0
        var ordinaryFenceCharacter: Character?

        func append(_ payload: MessageRichPart.Payload, complete: Bool) {
            let order = parts.count
            parts.append(.init(id: "\(identity.messageID.uuidString.lowercased())/part-\(order)",
                               identity: identity, streamOrder: order, catalogVersions: catalogs,
                               payload: payload, isComplete: complete))
        }

        // Keep line terminators, including the final incomplete line while streaming.
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let line = String(raw)
            let terminated = index < lines.count - 1
            let original = line + (terminated ? "\n" : "")
            let indentation = line.prefix(while: { $0 == " " }).count
            let trimmed = String(line.dropFirst(indentation))
            let tickCount = trimmed.prefix(while: { $0 == "`" }).count
            let tildeCount = trimmed.prefix(while: { $0 == "~" }).count

            if let currentTarget = target {
                if indentation <= 3, tickCount >= fenceLength,
                   trimmed.dropFirst(tickCount).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    append(.openUI(program: program, target: currentTarget), complete: true)
                    target = nil; program = ""; fenceLength = 0
                } else { program += original }
                continue
            }

            if let character = ordinaryFenceCharacter {
                markdown += original
                let count = character == "`" ? tickCount : tildeCount
                if indentation <= 3, count >= ordinaryFenceLength,
                   trimmed.dropFirst(count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ordinaryFenceCharacter = nil; ordinaryFenceLength = 0
                }
                continue
            }

            if indentation <= 3, tickCount >= 3 {
                let info = trimmed.dropFirst(tickCount).trimmingCharacters(in: .whitespacesAndNewlines)
                let words = info.split(whereSeparator: { $0.isWhitespace })
                if words.first == "openui-lang" {
                    // An incomplete header can still receive renderTarget next delta.
                    if !terminated && isStreaming { break }
                    if !markdown.isEmpty { append(.markdown(markdown), complete: true); markdown = "" }
                    target = words.contains("renderTarget=swiftui") ? .swiftui : .react
                    fenceLength = tickCount
                    continue
                }
                // Hold only a possible unfinished OpenUI header. Ordinary code is unchanged.
                if !terminated && isStreaming && "openui-lang".hasPrefix(info) { break }
                ordinaryFenceCharacter = "`"; ordinaryFenceLength = tickCount
            } else if indentation <= 3, tildeCount >= 3 {
                ordinaryFenceCharacter = "~"; ordinaryFenceLength = tildeCount
            }
            markdown += original
        }
        if let target { append(.openUI(program: program, target: target), complete: !isStreaming) }
        if !markdown.isEmpty { append(.markdown(markdown), complete: !isStreaming) }
        return parts
    }
}
