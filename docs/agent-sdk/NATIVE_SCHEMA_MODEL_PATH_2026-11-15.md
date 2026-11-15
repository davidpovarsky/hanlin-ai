# Explicit native MODEL response path

The existing engine can request one concrete model output contract with
`HanlinNativeStructuredResponse(messageID:validateCompleteParts:)`. The same optional value is
forwarded by `HanlinAgentSession.stream` and `continueInteraction`. No tool result substitutes for
MODEL output, no second model loop runs, and no text/fence detector interprets ordinary prose.

The first narrow route is the **originally selected** `gpt-6.1-terra` at direct
`https://api.openai.com/v1`, `apiType: "openai-responses"`. This is an explicit opt-in; it changes
neither the model catalog default nor a caller's chosen model. The pinned producer's actual
`OpenAIProvider.responses` adapter maps `Output.object(schema:)` to Responses `text.format` with
`type: json_schema`, `strict: true`. Other models/routes and Apple on-device reject the optional
contract before HTTP. Ordinary descriptors keep `structuredPartChannel == nil`. Only a run
actually configured with this contract emits `structuredResponseStarted(messageID:channel:)`.

The [official model documentation](https://developers.openai.com/api/docs/models/gpt-6.1-terra.md)
lists structured output and streaming, and requires Responses for tool calling. The schema uses
the [documented strict output constraints](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses):
explicit properties, all required, no additional properties, nullable unused values.

The private wire object is an ordered `parts` array of local grouping keys, `kind`, nullable
`text` and nullable `a2uiJSON`. It is a provider projection into the **existing canonical**
`HanlinChatStructuredPart`, not a second transcript or renderer protocol. The host issues the
message UUID (the original application's response-row UUID) and the adapter mints stable part
UUIDs once for that response. Array ordinal becomes message-wide sequence. Text segments require
distinct keys; A2UI messages updating one result may reuse that result's key. A2UI remains the
official `1.0` message, with exact complete bytes and existing catalog approval.

All provider JSON deltas stay private. The adapter ignores upstream repaired/partial output
values, bounds raw bytes, requires a complete successful stop, strictly decodes the complete
object and invokes the **required** host whole-batch official A2UI validator before publishing
any part. The callback must not mutate the live store, grant interaction or perform effects.
The renderer owner supplies that function using disposable official processors and approved
catalogs/limits. One live presentation receive path then admits controls. Session persists each
canonical part before delivery; cancellation/invalidation still checks the original context.
Schema JSON is never duplicated as visible prose. No live support is inferred from a fixture.

Validation at introduction is **NOT_RUN** on Apple; local `swiftc -frontend -parse` is syntax
only. The focused existing manual route selects
`exact_test_selector=HanlinChatCoreTests/HanlinNativeStructuredResponseTests`. It executes all
15 affected Session cases plus 25 Core cases (including five real Responses HTTP-adapter
fixtures), iOS compilation, and three affected catalog cases plus its iOS compilation. The
unchanged pure HostContracts/store cases are outside this operation; the independent checkpoint
recovery retains its own original failures and evidence. No producer rerun is necessary because
its exact source/locks are unchanged. The actual xcresults, not these planned counts, decide pass.

Real HTTP adapter fixtures assert schema request bytes, final mixed text/A2UI/text ordering,
no schema prose leak, malformed/repaired/truncated rejection, atomic validation failure,
unsupported-model preflight, and exactly one tool effect followed by the same canonical model
loop. The Session fixture separately checks original identity and persistence-before-delivery.
They do not prove a live model, official rendered application, native business operation,
XCUITest or physical device. Application single Session/store ownership, immutable UI-row/run
binding, presentation injection, action continuation and secure existing credential path remain
the integration work. Absence of a local environment key or one repository-secret name does not
establish absence of an eligible user's existing app credential.
