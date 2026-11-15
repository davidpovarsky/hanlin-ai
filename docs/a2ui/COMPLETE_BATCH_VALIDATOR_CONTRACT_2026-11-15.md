# Native-schema complete-batch validation

Callable in the app composition target, with the active A2UI products linked:

```swift
@MainActor
HanlinA2UICompleteBatchValidator.validate(_ parts: [HanlinChatStructuredPart]) throws
```

Inject this as the required `validateCompleteParts` callback in the SDK's
`HanlinNativeStructuredResponse(messageID:validateCompleteParts:)`. It must finish before
the same engine/session publishes, persists or admits **any** part of that complete batch.
The original app row UUID can supply the native response messageID explicitly. This function
does not infer parts from prose, fences or repaired partial JSON.

The function validates canonical version/sequence/kind/replay rules with the canonical SDK
sequence checker, bounds the complete batch using the presentation adapter's shared limits,
and validates every complete UTF8 official1.0 frame through the existing ingress. It then uses
one temporary `HanlinA2UISession` per `(messageID,partID)` owner, one at a time. Each consumes
its original ordered frames through the same official processor, registered Basic/Hanlin
catalogs and shared retirement/lifetime policy. Different owners can reuse wire surface IDs
and part UUIDs in different messages. A deleted ID cannot acquire a new incarnation in its owner.

After streaming schema validation, the official public `GraphTopologyValidator.validate`
validates the final public SDK component models with strict root/reference/orphan/cycle rules
and their resolved catalog IDs. No parallel schema, graph or binding validator is introduced.
Forward references can resolve across frames before this final completeness check.

The validator never registers a real store/interaction, renders a view, calls a host or fetches
media. BasicCatalog's no-handler factory uses no OpenURLHandler (its openUrl validates only),
and the processor's outbound listener remains nil, so no RPC authority is enabled. Every
temporary processor/session is closed via defer on success and throw. Only finite error codes
leave the helper; raw SDK errors, component values and JSON are not forwarded.

Official API facts were inspected at exact A2UI revision3ed9601862ecc78027e20ac80ad8b1b98a5d9079:
`GraphTopologyValidator.swift`, `ComponentModel.swift`, `MessageProcessor.swift`,
`ValidationConfig.swift`, `BasicCatalog.swift`. The component model projection uses public
id/type/properties/catalogID fields; all validation algorithms remain official SDK code.

Six focused native tests cover successful official schemas and late references, final graph
and schema rejection, owner isolation/retirement, whole-batch rejection before scratch creation,
canonical/budget rules, RPC absence and disposal on both exits. Native execution is pending
at this source commit. Combined affected proof selects6 validator +6 consumer +17 ownership
cases; unrelated direct SDK/producer/media test cases are not repeated.
