# Ordered model output presentation

Active wave: 2026-11-15. Tasks A2UI-02 `1220489383643571`, A2UI-03
`1220489258419968`; all acceptance remains open.

The existing result store can now register an explicit model-message/part owner.
It never invents a provider tool call ID. Tool mounts reject model origins, and
the model projection rejects tool origins, wrong run/message/part identities,
duplicate part IDs, more than128 parts, and more than1MiB of text. Lookup and
expansion never receive frames. Keys bind the generation at registration and
never follow a replacement. Existing sealing/discarding behavior remains.

`HanlinChatContentProjection` is read-only presentation, not a transport, message
store or persisted envelope. Its parts are ordered Markdown and registered official
A2UI Surface projections. Injection into the existing ChatBubbleView requires the
exact run and message plus equality of the complete concatenated original text;
missing/mismatched injection preserves the original Markdown. Removed surfaces
show an unavailable state. Inline and expanded content share the existing owner
and ChatEmbeddedResultHost. The legacy Markdown context menu wraps only Markdown,
never the interactive ordered Surface siblings.

## Actual connection still needed

The manager routed canonical structured model output and immutable host callback
context to the sole SDK writer, chat `01a1df7e-a78d-7352-bbf2-d802bf9c2420`.
`HanlinHostContracts` owns session/run/providerCallID/hostGeneration; generation
must originate with invocation, not the currently selected host at completion.
Do not fabricate absent exports. The canonical SDK will own versioning, streaming,
framing, sequence, original transcript persistence/replay and provider advertisement.
The app adapter will register/feed/seal/discard the existing store outside View.body,
then publish projection snapshots. This patch does not infer UI from prose or
fenced JSON, add a second renderer, or claim production provider connectivity.

## Validation scope

Before native execution, changed dependency closure: owner/key and registration,
tool/model projection sources, ChatBubbleView display seam, tool mount discrimination,
and the added ordered content view. The31 SDK cases include the27 prior cases and
four new behavioral cases. Existing eight portable ingress scenarios are unaffected
and are not rerun just to refresh their timestamp. Historical35/35 proof remains
at run43683448355/job132718843240; it is not a new execution or proof of this patch.

The manual `a2ui_model_content` route in the existing workflow selects only the
affected SDK suite. It retains compiler/SDK/OS/architecture, schemes, exact source
inputs, resolved lock, process status, logs and xcresult, and validates31 actual
passed case identities. No automatic triggers or release publication were added.
Local syntax parsing and synthetic verifier checks are component tooling only.

Native SDK compilation/execution: **31 EXECUTED_PASS /0 FAILED**, source
`1686b890eab0c9f2556757e8a7d013973dca0c94`, [run43722450726](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43722450726),
job132837160857 (200seconds). Xcode27.2/27B52, Swift6.4.2, arm64 macOS27.0.1,
macOSSDK27.2. Raw xcresult contains exactly31 unique passed identities; all
retained source input hashes match the tested Git blobs. Official SDK pin remains
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079`; raw resolved lock remains
`af74be77f91276268a10e0b32f13e04d538f4a01110ad93d8c9e484177dd9fae`.
Artifact14165036525,287304bytes, API SHA256
`f55106cd4d29f1e505cb9ad83dccd374f01d2ead912445b6eb38a0affa5d1a14`.
Provenance and case identities: `evidence/model-content-43722450726.json`.

Follow-on source also namespaces saved Markdown block selections by stable part ID
while preserving the complete original-message digest. This avoids highlighting a
same-named block in another independently parsed part. That iOS view code remains
native-compilation pending and does not enter the tested SDK harness closure.

Actual app/host/XCUITest, RTL/AX, physical iPad, persisted model replay and media
acceptance: NOT_RUN.31 component passes do not satisfy these gates.

## Successful EOF and interaction lifetime

The manager explicitly confirmed that successful producer EOF must close input
without revoking a still-valid Surface interaction owner. `finishRun` stops only
receive tasks, blocks late frames, new registrations and replacements for that run,
and leaves local bindings and the original weak action sink active. `sealRun` and
discard retain their terminal revocation behavior for failed/cancelled producers,
host invalidation and chat teardown. Calling EOF after revocation cannot revive it.
The SDK action broker still must validate the original host-generation context;
EOF is neither a new producer frame nor a grant to target a currently selected host.
Persisted replay never restores an event sink by itself.

Three additional SDK controls test real Button submission with a post-EOF local
edit, terminal revocation of queued/retained events, late registration/frame rejection,
receive-task cancellation, replacement rejection and independent-run isolation.
The next native operation selects only17 affected/new ownership controls, not
the17 unchanged direct SDK cases or8 portable framing cases. The complete defined
suite is8+34; this focused execution cannot claim42 tests ran.
