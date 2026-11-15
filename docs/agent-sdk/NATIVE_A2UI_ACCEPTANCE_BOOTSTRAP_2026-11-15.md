# Isolated native A2UI app acceptance bootstrap

The explicit opt-in is DEBUG + iOS simulator only: launch environment
HANLIN_NATIVE_A2UI_ACCEPTANCE=1. AppDataManager creates a NEW in-memory SwiftData container,
with CloudKit disabled, before any read/preload. It seeds only two fixture chats, the actual
eligible selected gpt-6.1-terra model at direct api.openai.com/v1/responses, and a fake local-only
key. It does not open/delete/reset the user database. Reopen history within the same process is
supported; cross-process persistence is deliberately not claimed by this in-memory fixture.

This bootstrap bypasses unrelated production preloads, orphan cleanup, classic acceptance row
reset, runtime startup and AppGroup compact-credential publication. Existing application routes
outside the opt-in retain their behavior. No automatic CI/build/release frontier is added.

APIManager's existing chatEngineFactory uses the same HanlinChatEngine/makeAISDKFetch transport
with an ephemeral URLSession and a strict URLProtocol. All actual APIManager/Session/Host/owner/
ChatView/row/store/official A2UI delivery remains enabled. Only HTTP bytes are fixtures. Unexpected
URL/model/method/stream/schema/input, missing plan and extra requests fail; there is no provider
network fallback. Production Responses adapter parses actual SSE and official whole-batch
validation still gates all canonical delivery. This is deterministic integration, not live model.

## Payload seam for the A2UI writer

Launch HANLIN_NATIVE_A2UI_FIXTURE_PLAN with JSON matching
HanlinNativeA2UIAcceptanceProvider.Plan, bounded262144 UTF8 bytes:

    {"steps":[{"expectedInputContains":["FIRST_PROMPT_MARKER"],
      "forbiddenInputContains":[],"expectedActionID":null,"expectedSubmittedValue":null,
      "structuredObjectJSON":"<complete native {parts:[...]} object as a JSON string>",
      "delayMilliseconds":0},
      {"expectedInputContains":["SUBMIT_MARKER"],"forbiddenInputContains":["UNSENT_DRAFT_MARKER"],
      "expectedActionID":"original_submit_action","expectedSubmittedValue":"edited fixture value",
      "structuredObjectJSON":"<complete native follow-up object>","delayMilliseconds":0}]}

At most8 requests, at most128KiB structured object per step, delay0...2000ms. Every expected marker
is matched against decoded actual provider-input strings using exact UTF8. Every request after the
first MUST also contain the existing Host continuation prefix with expectedActionID and the
expectedSubmittedValue. No fake action callback or alternate engine starts that request. A2UI
owns real valid official1.0 payloads, rendered controls, XCUITest and AX assertions. Use one-step
plans to prove reopen/dismiss/cancellation did not issue a second model request.

The stub checks actual direct Responses model/method/stream, strict native json_schema root,
required parts, additionalProperties=false, item required fields/types/enums and bounds before
emitting any SSE. All intercepted HTTP attempts, counted at startLoading before URL/schema/plan/input rejections, are observable through static observedRequestCount
and lastRequestFailure for A2UI-owned AX/test display; they are not manufactured success markers.

Source syntax/diff checked only. Enabled simulator app compilation and actual original app UI
controls remain NOT_RUN, blocked by the coherent app/Runtime build graph. Do not dispatch another
full build for this source-only seam while that prerequisite is unresolved. Package/native-adapter
proofs do not establish this app bootstrap's compilation or UI acceptance.

The native and classic AgentRuntimeUIAcceptance modes are mutually exclusive; enabling both fails
fixture bootstrap after choosing the isolated container. Never enable the classic environment for
this proof. The native fixture does not reset either container or preferences to resolve a conflict.
