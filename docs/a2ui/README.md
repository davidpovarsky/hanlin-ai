# Isolated official A2UI prototype — Wave 1

[איתן | ARCH] [MAIN_SESSION], 2026-11-15. Lease W1-001. Source tasks
A2UI-01 `1220489258069695` and A2UI-03 `1220489258419968` remain **open**.
A2UI-02 `1220489383643571` remains deferred. Source includes optional mounting in
the existing chat host. Production transport, app/inline/device acceptance and
persisted-envelope work remain outside this packet.

The current source adds transient result ownership and projection primitives in
`HanlinA2UIResultOwner.swift`. Registration binds caller-supplied run/result/call
identity to a fresh generation; exact-key lookup has no creation or replay side
effects. The owner receives complete frames at consecutive ordinals starting at0;
an ordered rejected delivery still consumes its ordinal. No stream framing,
persisted payload, production transport or callback continuation is introduced.

`seal` cancels the attached receiver and revokes the weak event sink while keeping
the actual SDK model/node identities visible. The renderer disables controls.
`discard`, replacement and explicit run/chat discard close the real session.
Projection copies share the same owner and have no appearance-based teardown.
The caller must retain the sink, explicitly seal finished runs and discard owners
on cancellation, supersession, removal or chat teardown. This store is transient
presentation state, not message or tool authority. A sealed result cannot resume.
Ended runs reject late result registrations/replacements; discarding the chat
permanently ends that store. Old generations cannot be reset into authority.

The optional mount source now supplies only explicitly registered projections to
the actual ChatBubbleView.assistantTextSection -> AgentTranscriptToolResultView
-> generic ChatEmbeddedResultHost path. Environment injection defaults to nil;
there is no production frame source, event route or run continuation. Existing
display gates and nil/flag-off resolver/modern/legacy branches are preserved.
Inline and expanded content share one projection without appearance teardown.

Result owners now refuse a deleted surface ID for that result's remaining lifetime.
The SDK callback exposes no emitting model instance, so delayed membership cannot
distinguish a same-ID reincarnation. Only observed removal of an actually owned
SDK surface after its delete retires the ID, even if the SDK also reports an error.
This is host admission policy, not SDK schema validation;
other owners/fresh generations may reuse IDs. Standalone SDK session delete/recreate
behavior is unchanged.

**Current candidate native status: NOT_RUN.** The frozen961 benchmark's34 methods
are retained, plus one same-ID race regression:8 portable +27 SDK =35. Six iOS-only
A2UIHostedResultTests methods are authored for the actual chat/host/native-input
path and excluded from the isolated macOS harness. Their compilation/execution is
NOT_RUN. Windows syntax parsing is not Apple import/API/type checking. Historical
f65425-case and96134-case outcomes cannot accept this later correction or UI mount.

The actual961 attempt [run43674291306](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43674291306)
failed compilation (exit65) on recursive nested Testing.require expansion at
A2UITests.swift507, before any tests. All34 are NOT_RUN; raw test-case count is0.
The same expression survived in e1d3d242. The follow-up moves registration into a
returning helper with sequential requires, releasing its unwrapped sink before
the weak-lifetime test sets sink=nil. Current35/6 cases retain their assertions
and remain NOT_RUN. [Failure evidence](evidence/native-run-43674291306.json)
records exact source/workflow/artifact provenance. Local Windows macro typecheck
is unavailable because this Windows Swift invocation cannot import Testing; no native job was dispatched.

The later actualfa810 run43679728130 compiled and executed35 Swift Testing cases:
33 PASS /2 FAIL (`eventSinkIsWeakAndCannotKeepAuthorityAlive` and
`retiredSurfaceCannotReanimateQueuedEventsInSameResult`, both `.ended`). The6
hosted iOS cases were NOT_RUN. [Actual outcomes](evidence/native-run-43679728130.json)
remain failed evidence, not35PASS.

Root cause was destructive negative observation: timing out a pending shared
AsyncStream iterator cancels that stream, preventing the later phase from reading
it. The correction checks monotonic recorder counts before/after100ms and leaves
positive reads strict. It does not catch ended as success, reset recorders, remove
regressions or alter product authority. The independent positive explicitly
requires the real action/context/key. Three real Swift AsyncStream checks using
the actual generic test helpers passed locally; this is not an SDK substitute.
Run `py -3 docs/a2ui/validate_async_observation.py` to reproduce. See
[local observer results](evidence/async-observation-results.json) and Swift's
[documented cancellation behavior](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md#cancellation-handlers).
The corrected source still needs the authorized changed-source35-case native run.

## Official source and revision

Use [a2ui-project/a2ui](https://github.com/a2ui-project/a2ui), exact revision
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079` (upstream commit timestamp
2026-11-14 00:38:20 UTC). GitHub's commits API and the source at that revision
were read. This is a source revision pin proposal; the app has **no installed
A2UI package or resolved transitive dependency graph** in this tranche.

The official monorepo exports these root SPM products:

| Product | Modules / purpose |
| --- | --- |
| A2UISwiftCore | A2UIJSON, A2UICore: parser, validation, model, graph resolution |
| A2UISwiftUI | Surface and SwiftUI binding adapters |
| BasicCatalog | Official component schemas and functions |
| BasicCatalogSwiftUI | Native component implementations including TextField and Button |

The pinned [Package.swift](https://github.com/a2ui-project/a2ui/blob/3ed9601862ecc78027e20ac80ad8b1b98a5d9079/Package.swift)
requires Swift tools 6.1 and declares iOS17/macOS14 minima. Hanlin's checked-in
app remains iOS27 / Swift6; no deployment settings changed. Upstream's manifest
also declares swift-json-schema `0.13.1..<0.14.0` and Yams `>=6.2.2` within the
same major version. The integrator must retain the actual resolved graph and
hash it. Exact root revision alone is not proof of frozen transitive versions.

The canonical v1 catalog URI still contains `specification/v1_0/catalogs/basic`;
its source moved to `catalogs/basic/v1/catalog.json`. A 404 at the obsolete raw
source path is not evidence that the Swift renderer is unavailable. This
discovery is recorded here because PROJECT_BOARD.md is outside this lease.

Source paths, pinned URLs and SHA256 identities are in
[upstream-verification.json](evidence/upstream-verification.json). These hashes
certify inspected UTF-8 source, not compiler acceptance or protocol conformance.
The [official SwiftUI README](https://github.com/a2ui-project/a2ui/blob/3ed9601862ecc78027e20ac80ad8b1b98a5d9079/swift/swiftui/README.md)
describes the same Surface/catalog entry points used here. No community
renderer, copied renderer, NativeScript engine or alternate MiniApp engine is used.

## Ownership and behavior

The core source lives in
`AI_HLY/Downstream/ChatPresentation/A2UI/`:

- `HanlinA2UIIngress.swift` checks a complete UTF-8 message's framing, version,
  target ID and resource bounds. It does **not** validate component schemas.
- `HanlinA2UISession.swift` owns one transient upstream MessageProcessor per
  result owner, with independent upstream SurfaceViewModels. It uses the throwing
  `processMessages` API; `process(message:)` reports and swallows errors, so that
  API alone cannot drive the rejection fallback.
- `HanlinA2UIResultView.swift` delegates rendering to upstream Surface and
  BasicCatalogImplementation, including native two-way TextField binding.

The fixture's conceptual Input is the official `TextField` component. The POC
uses Text/Card/Column/TextField/Button and v1 `@path` bindings. Node identity,
graph updates, model resolution, action context and input writes all belong to
the SDK. A Button event goes to an explicitly supplied callback; it is not
connected to Hanlin tools, navigation, the composer or HostServices.

After independent QA on `e7141d55`, outbound delivery uses the SDK's
`ActionHandling` hook with an actor-isolated, revocable event/error relay.
`outboundListener` stays nil: upstream consequently installs no agent-function
caller on surfaces. Unknown function expressions are rejected by the official
catalog validator, direct surface RPC has no listener, and inbound RPC calls
and responses are rejected by ingress. The relay only converts already-resolved
event actions to the official RendererAction model; it does not resolve bindings
or execute actions itself. No cross-app or service authorization is implied.

One session may hold four surfaces, each message is at most65,536 UTF-8 bytes
and64 components, and a session accepts at most1,048,576 cumulative bytes. The
budget resets only with a new owner/session. This intentionally bounded POC is
not a long-running production streaming policy. The `sessionBudget` check runs
**after** ingress has produced a validated Frame: a rejected update/delete to
an SDK-owned surface therefore returns its correlated ID and a fallback for
that same surface. It neither applies the mutation/deletion nor affects another
surface. At an exhausted budget, owner `close()` still works outside the gate;
continuing content needs a new owner/session. This is not an uncorrelated
preflight rejection. Unknown component schemas in a
validated update fall back only for a surface the current SDK processor owns.
Raw IDs from rejected envelopes never route fallback. Unsupported operations,
invalid IDs and foreign targets return errors without adding surfaces or hiding
existing content. A malformed envelope can replace an empty result placeholder;
it cannot replace live surface content. Surface membership comes only from the
SDK, never failure bookkeeping. `close()` first revokes queued callbacks, then uses
the official `MessageProcessor.dispose()` to clear surfaces/graph bounds and
cancel pending SDK calls. It is idempotent and rejects late input. The caller
must dispose sessions when discarding results. A Debug-only test hook seeds a
real pending SDK call to verify cancellation; it is not production transport API.

Locale, layout direction, Dynamic Type, accessibility and sizing are inherited
from the host SwiftUI environment. There is no fixed geometry, nested scrolling,
custom expansion or copied chat shell. Hebrew content and a right-to-left
composition case are supplied; actual hosted RTL/Dynamic Type/VoiceOver behavior
is **not verified**. Core catalog functions currently use upstream's default
locale; locale-sensitive function parity beyond this text-only POC is a later
integration concern, not an asserted capability.

The mount packet changes only optional environment injection/filter/callsite in
ChatViewComponents.swift and the projection branch in AgentTranscriptToolResultView.
ChatEmbeddedResultHost, Runtime, project/lock/flags, APIManager and run lifecycle
remain untouched. No persisted envelope, renderer kind or engine identity is added.

## Deliberate activation gate

The SDK-backed source and27 SDK tests are behind **HANLIN_A2UI_POC**. The manager
authorized this temporary prototype gate without changing the lease. No build
flag, manifest, dependency lock or project file was changed. This explicit flag
protects the synchronized app source groups from unresolved optional imports.
When enabled, missing imports fail compilation; there is no `canImport` fake
implementation or success fallback.

Native run43662884686 exposed the invalid v1 component ID `submit-label`.
The corrected2bae5a3e source then compiled and passed all25 enabled cases in
run43664698104 with the exact SDK. See [the identifier evidence](NATIVE_VALIDATION_FIX_2026-11-15.md).
The [privacy correction](DIAGNOSTIC_PRIVACY_FIX_2026-11-15.md) then passed all25
enabled cases at a43 in run43667371439, including its canaries. The current
[consumer-module correction](CONSUMER_MODULE_FIX_2026-11-15.md) aligns the test
import and temporary recipe with actual `AI_Hanlin`; source f654ac11 passed
all25 actual native cases in [run43668852483](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43668852483).
These isolated results do not establish inline app or physical-device acceptance.
Inline app integration and hardware verification remain NOT_RUN. A disabled
flag, syntax-only parse or zero selected cases cannot satisfy either task.
See [TEST_EXECUTION_MANIFEST.md](TEST_EXECUTION_MANIFEST.md) for exact cases,
commands, fixture identities and evidence.

The prepared [isolated proof route](EXACT_PIN_PROOF_ROUTE.md) now requires all35 authored
cases in a temporary consumer, exact root/transitive resolution evidence and
unchanged source bytes. It does not require shared product wiring. Its planner
and verifier have local checks. Tomer's existing verifier produced the actual
native results, including the consumer-name25-case pass retained in
[evidence](evidence/native-run-43668852483.json).
No shared product wiring is added by this correction.

## Proposed integration, not applied

After the lead approves the envelope/ownership contract and grants one
integrator the shared seams:

1. Add the official root package with requirement `revision:
   "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"`; link the four products above to
   the isolated test consumer and app consumer as appropriate. Resolve once
   and preserve the real Package.resolved provenance. Do not use a moving main
   branch or a similarly named community package.
2. Enable `HANLIN_A2UI_POC` only for the focused exact-pin build and tests first.
   Stage A2UIFixtures in the test bundle. Require all25 actual test cases and
   the resolved revision in retained evidence. No native Runtime rebuild is
   necessary for this isolated renderer proof.
3. Agree how an existing transcript result owns the session, routes complete
   messages, keeps existing replay order, handles replacement/cancellation,
   and authorizes outbound actions. Surface IDs are SDK-local; no new global
   identity or persisted ChatCore schema is proposed by these source files.
4. In a separate integration lease, let the designated integrator place
   HanlinA2UIResultView inside the existing ChatEmbeddedResultHost content
   closure and existing sizing/expansion policy. No patch to that file or
   ChatView is included here. Reuse existing rich-content routing and preserve
   text/unsupported-content behavior. Do not introduce a second renderer route.
5. Execute hosted narrow/wide RTL, accessibility sizes, keyboard, focus, update
   stability and VoiceOver checks, plus physical-device acceptance if required.
   Production replay/action/size policy still needs its own contract and QA.

ChatInput, Runtime/SDK, MiniAppHost, ChatCore, ChatEmbeddedResultHost, frozen
Chat files, project.pbxproj, all manifests/locks and workflow/signing files
were untouched. All additions are downstream-owned. There are no upstream
file modifications; merge risk is additive source discovery and the future
dependency/host seam, which remain centrally controlled.
