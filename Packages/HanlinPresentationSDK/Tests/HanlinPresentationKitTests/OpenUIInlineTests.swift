import Foundation
import Testing
@testable import HanlinPresentationKit

private let message = PresentationMessageIdentity(appID: "hanlin", conversationID: UUID(), messageID: UUID())

@Test func mixedRenderersKeepOriginalChronologyAndStablePartIdentity() {
    let prefix = "Before.\n```openui-lang renderTarget=react\nroot = Stack([]);\n```\nBetween.\n"
    let suffix = "```openui-lang renderTarget=swiftui\nroot = Stack([TextContent(\"Hi\")]);\n```\nAfter."
    let first = OpenUIInlineParts.split(prefix, identity: message, catalogs: [.init("original")], isStreaming: true)
    let last = OpenUIInlineParts.split(prefix + suffix, identity: message, catalogs: [.init("original")], isStreaming: false)
    #expect(last.count == 5)
    #expect(first.prefix(2).map(\.id) == last.prefix(2).map(\.id))
    #expect(last[1].payload == .openUI(program: "root = Stack([]);\n", target: .react))
    #expect(last[3].payload == .openUI(program: "root = Stack([TextContent(\"Hi\")]);\n", target: .swiftui))
}

@Test func codeExamplesAndPartialTargetHeadersAreNotExecuted() {
    let quoted = "````markdown\n```openui-lang renderTarget=react\nroot = Stack([]);\n```\n````"
    #expect(OpenUIInlineParts.split(quoted, identity: message, catalogs: [], isStreaming: false).map(\.payload) == [.markdown(quoted)])
    let partial = OpenUIInlineParts.split("Before\n```openui-lang renderTarget=swi", identity: message, catalogs: [], isStreaming: true)
    #expect(partial.map(\.payload) == [.markdown("Before\n")])
}
