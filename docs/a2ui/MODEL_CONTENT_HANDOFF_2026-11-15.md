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

Native SDK compilation/execution: pending. Actual app/host/XCUITest, RTL/AX,
physical iPad, persisted model replay and media acceptance: NOT_RUN.
