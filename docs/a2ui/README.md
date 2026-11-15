# Isolated official A2UI prototype — Wave 1

[איתן | ARCH] [MAIN_SESSION], 2026-11-15. Lease W1-001. Source tasks
A2UI-01 `1220489258069695` and A2UI-03 `1220489258419968` remain **open**.
A2UI-02 `1220489383643571` remains deferred. This is an unconnected prototype,
not an inline-chat feature or a new persisted envelope.

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

The only source additions are in
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

## Deliberate activation gate

The SDK-backed source and17 SDK tests are behind **HANLIN_A2UI_POC**. The manager
authorized this temporary prototype gate without changing the lease. No build
flag, manifest, dependency lock or project file was changed. This explicit flag
protects the synchronized app source groups from unresolved optional imports.
When enabled, missing imports fail compilation; there is no `canImport` fake
implementation or success fallback.

The actual native run43662884686 compiled `c40e617b` with the exact SDK and
executed all25 cases:8 portable PASS and17 SDK FAIL during fixture load. The
fixtures used invalid v1 component ID `submit-label`; the corrected candidate
uses `submitLabel` and preserves the invalid spelling as a negative SDK case.
See [the diagnosis and evidence](NATIVE_VALIDATION_FIX_2026-11-15.md).
The corrected candidate's native compile/17 SDK cases are pending, not PASS.
Inline app integration and hardware verification remain NOT_RUN. A disabled
flag, syntax-only parse or zero selected cases cannot satisfy either task.
See [TEST_EXECUTION_MANIFEST.md](TEST_EXECUTION_MANIFEST.md) for exact cases,
commands, fixture identities and evidence.

The prepared [isolated proof route](EXACT_PIN_PROOF_ROUTE.md) uses all25 actual
cases in a temporary consumer, exact root/transitive resolution evidence and
unchanged source bytes. It does not require shared product wiring. Its planner
and verifier have local checks. Tomer's existing verifier already reached the
real failure above; the corrected candidate awaits the same enabled25-case
proof. No shared product wiring is added by this correction.

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
