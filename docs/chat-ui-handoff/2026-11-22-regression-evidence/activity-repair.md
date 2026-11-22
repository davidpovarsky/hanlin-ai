# Activity regression repair — 2026-11-22

## Proven causes

Build 145801's activity visibility policy accepted only tool invocation kinds.
The production provider adapter still emitted real reasoningStarted, reasoningDelta,
and reasoningCompleted events with stable IDs, but composition discarded them.
The header phase resolver and live-owner selection independently excluded reasoning,
so merely restoring a label would not have restored the blue sweep.

Before any provider output, the canonical SDK stepStarted receipt was reduced to
an internal operational-state string. That string is intentionally hidden, while
modelRoundStarted only tracked transcript ancestry. Therefore a provider with no
reasoning channel had no truthful visible activity. A model round cannot substitute
for a request receipt because inline tool execution also starts rounds.

## Original reference verification

Read the complete 2,391-line V17 original, including integration and motion notes.
The provided local reference has normalized LF line endings plus one extra final LF.
Removing that extra LF and restoring CRLF reproduces the original 111,252 bytes and SHA-256:

f984930f659c34b791d610b3716b7cfb3d9545040b2c4d567b181a4ec46cc14e

The shared production HanlinActivityTitle / ChatShimmerEffect already implements
the V17 sweep across letters (default 1.95 seconds), scene/branch visibility, reduced
motion and VoiceOver restrictions. This repair retains that implementation.

## Changes

- Preserve real reasoning steps with lifecycle identity through composition.
- Preserve real tool calls/executions; continue hiding exact internal discovery,
  loading and progress-reporting tool names and generic transport prose.
- Restore the shared blue title on a live reasoning leaf, real running tool, or the
  closest visible collapsed ancestor. Completed, failed, cancelled, approval-wait
  and historical states cannot animate as current work.
- Stop reasoning animation at the first actual answer text while allowing an
  independently running tool to continue.
- Retain completed reasoning as static history with its actual completed duration
  when no approved short summary exists. Raw provider reasoning is still subject
  to the existing approved-summary sanitizer.
- Add explicit modelRequestStarted(id:) / modelRequestEnded(id:) events and optional
  pendingModelRequestID on AgentRun. APIManager's actual SDK step events provide
  those receipts (integrated by the release owner).
- Clear waiting at first semantic reasoning/answer/tool/approval/search output and
  terminal events. End receipts clear only a matching request ID.
- Show the precise Waiting for model response title only for that current admitted
  request. Expanded trees put the blue sweep on its waiting leaf; collapsed trees
  put it on the root. No fake tool-history step is added.
- Optional request storage decodes old runs without inventing activity, suppresses
  terminal stored receipts, and resets when continuing an old message.
- Preserve the existing mounted tool-details and finite disclosure geometry fix.
- Close an active reasoning segment on a matching modelRequestEnded receipt without
  changing answer-segment finalization. An end receipt from another round cannot close it.
- Add a read-only A2UI visible-output receipt after actual admission: the event must
  belong to the original active session/UI run/canonical run/message/part/sequence,
  must be newly consumed, and its official surface must contain a real root.
  Metadata before root, exact replay, rejection, closed surfaces, historical content
  and drained runs cannot claim new visible output. APIManager uses the receipt with
  its already captured user operation; the presentation code does not look up a
  current TaskLocal operation or alter dispatch authority.
- The root ID is a production constraint: HanlinA2UIIngress accepts only version 1.0;
  HanlinA2UISession registers the v10 catalog and validates complete graphs using
  rootID "root". Legacy protocols with a selectable root are not admitted.

## Verification performed

SentinelX host: host_7ec8382e82747448
Repository: C:\Users\DAVID\Code\hanlin-ipad-interactions-20261122
Final check job: job_6ef377e45ae9
Started: 2026-11-22T13:11:43.4264292Z
Finished: 2026-11-22T13:12:22.1890128Z
Exit: 0

Exact successful output:

    PASS: 202 production activity lifetime and motion-policy checks
    PASS: 16 changed application/test Swift files parse; A2UI feature flag enabled

The complete compiler arguments, parse inputs, executable SHA-256 and exact source
SHA-256 values are in activity-checks.json. All 19 source inputs were hashed before
and after the run and were unchanged during validation.

Portable checks compile the actual production header, visibility and motion policies
with Swift 6.3.3, -swift-version 6 -strict-concurrency=complete -warnings-as-errors.
They cover reasoning-only visibility, first-answer cutoff, concurrent tools,
collapsed/expanded ownership, genuine request receipts without reasoning,
no-dispatch/no-output distinctions, stale history, consent wait, and existing finite
disclosure geometry.

All sixteen changed app/test Swift sources were syntax-parsed with swiftc -frontend -parse -D HANLIN_A2UI_POC.
This is not Apple SDK type checking. Scoped git diff --check passed after preserving LF.

Five native app tests were added in AgentActivityHeaderPhaseTests.swift:
- provider reasoning -> real adapter/accumulator/composer -> first answer;
- real tools and reasoning retained while discovery stays only in the audit;
- request admission vs inline round, late old end, first semantic output, cancellation;
- older stored runs without a request receipt;
- admitted non-text output/real step end closes only the matching reasoning segment
  and leaves the final answer correctly classified.

The existing A2UI native product fixture also now asserts real root admission,
missing-root metadata, exact duplicate rejection, original UI-run identity and
the absence of live receipts after producer drain. It adds no pacing or test-matrix
expansion. Those assertions were not executed in this Windows session.

Those native app tests were not executed in this Windows session. The existing
native fixture/Apple compilation belongs to the release integration. No simulator
was launched by this activity repair, and no on-device visual/interaction success
is claimed here.

## Integration notes

Changed application areas: AgentEvent, AgentActivityModels, AgentEventAccumulator,
ProviderEventAdapter, LegacyAgentActivityAdapter, visibility/composition/composer/
header policies, only the activity subtree of ChatViewComponents, and the bounded
presentation-consumer/A2UI/SessionOwner read-only receipt seam.

Root owns the corresponding APIManager receipt yields, global localization keys,
the adapter's missing pre-dispatch terminal event, background LiveActivity, native
fixture validation and release. Approval/dispatch authorization behavior was not
modified by this activity repair.

New localized strings coordinated with root:
- Thought for %@ — Hebrew: חשב במשך %@; Simplified Chinese: 思考了%@
- Waiting for model response — Hebrew: ממתין לתגובת המודל; Simplified Chinese: 等待模型响应

Required device acceptance remains repeated expand/collapse during real reasoning,
parallel tools, cancellation and consent; providers without reasoning; first answer;
history reopening; RTL; and reduced motion. A successful build alone is not evidence
of complete V17 visual parity or the absence of an iPad-specific crash.
