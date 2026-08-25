import HanlinPlatformContracts
@testable import HanlinScriptingApplicationRuntime
import Testing

private actor AssistantRequestRecorder {
    private var requests: [HanlinScriptingAssistantRequest] = []

    func append(_ request: HanlinScriptingAssistantRequest) {
        requests.append(request)
    }

    func first() -> HanlinScriptingAssistantRequest? {
        requests.first
    }
}

@Suite("Scripting application runtime", .serialized)
struct HanlinScriptingApplicationRuntimeTests {
    @MainActor
    @Test("Compiles and renders independently of the application target")
    func rendersIndependently() throws {
        let packageID = try HanlinInstalledPackageID(validating: "fast-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"Navigation.present({ element: createElement(Text, null, "Ready") });"#,
            filename: "compiled/index.js",
            storageAllowed: false
        )
        defer { session.dispose() }

        #expect(session.model.root.kind == .text)
        #expect(session.model.root.properties["text"] == .string("Ready"))
    }

    @MainActor
    @Test("Dispatches Assistant requests from JavaScriptCore to the native loader")
    func dispatchesAssistantRequest() async throws {
        let recorder = AssistantRequestRecorder()
        let packageID = try HanlinInstalledPackageID(validating: "assistant-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            const assistantResult = useObservable(Assistant.isAvailable ? "Idle" : "Unavailable");
            Navigation.present({ element: createElement(Button, {
              title: assistantResult,
              action: () => {
                const pending = Assistant.requestStreaming({
                  messages: { role: "user", content: "Hello" },
                  provider: "openai"
                });
                assistantResult.value = "Dispatched";
                pending.then(async stream => {
                  let text = "";
                  for await (const chunk of stream) {
                    if (chunk.type === "text") text += chunk.content;
                  }
                  assistantResult.value = text;
                }).catch(error => {
                  assistantResult.value = `${error.name}:${error.message}`;
                });
              }
            }) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            assistantAllowed: true,
            assistantLoader: { request in
                await recorder.append(request)
                return AsyncThrowingStream { continuation in
                    continuation.yield(.text("Hello "))
                    continuation.yield(.reasoning("verified"))
                    continuation.yield(.text("world"))
                    continuation.yield(.usage(.init(inputTokens: 1, outputTokens: 2)))
                    continuation.finish()
                }
            }
        )
        defer { session.dispose() }

        guard case let .string(handlerID)? = session.model.root.properties["onPress"] else {
            Issue.record("The Assistant test button did not expose an event handler")
            return
        }
        try session.model.apply(.event(handlerID: handlerID, payload: .null))
        for _ in 0 ..< 100 {
            if await recorder.first() != nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(session.model.root.properties["title"] != .string("Idle"))
        let request = await recorder.first()
        #expect(request?.kind == .streaming)
        #expect(request?.provider == .builtIn("openai"))
        #expect(request?.messagesJSON != nil)
    }
}
