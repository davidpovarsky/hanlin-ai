# W1-006 consolidated integration

Owner: Tomer, independent primary `01a1dc9e-91cb-7d12-9102-acd3500aee90`.
Worktree `C:/Users/DAVID/Code/hanlin-wave1-integration-20261115`, branch
`codex/hanlin-wave1-integration-20261115`. Source integration task
K `1219656771637321`; HQ `1220539630159023`. Date: 2026-11-15, Asia/Hebron.

## Assembled sources

Frozen Runtime baseline `dd700c03e9fe9d22e95a031d4684275512ee6e6f` plus one
octopus assembly of Split `fb90d670e05f282405327466d07b1ff81a95addb`, A2UI
`3a24003ea45636feae76f684234119a0ddeccd6b`, and Composer
`d2126940850b48c9c448fff606dfb79607e5e045`. The separate released verification
tranche through Composer `54b5d90a7c137fe895d3d8cc0c37d31b1d8d62a3` joined this
same window once. The later authorized Split delta `053d1535d008c044caaebbd241f9fe29ce85aab3`
joined once after its handoff; its receiver/migration sources are included without
fixture persistence. No Runtime failed trial or unaccepted W1-004 candidate joined.
No producer branch was rebased, merged back or synchronized.

## Registered implementation

- `HanlinProductSplit/Package.swift` exports the actual leaf product with the
  existing `HanlinPlatformContracts` and `HanlinMiniAppCore` products. Production
  explicitly excludes `SplitFixtureStore.swift`, `SplitReceiverFixturePersistence.swift`
  and `SplitMigrationFixturePersistence.swift`. Five real Swift Testing cases
  are registered under `Tests/RegisteredIntegrationTests`; the producer's custom
  portable `@main` remains outside every production/test target.
- `HanlinMiniApps` is a separate application target and scheme with only
  `HanlinMiniAppsApp` synchronized source membership. It links the three canonical
  products, has no AI app/extension dependency or Runtime build phase, and uses
  Swift 6 / iOS 27. Its unsigned simulator-only identity is
  `com.itorah.hanlinminiapps.integration`, not a registered production App ID.
- The existing AI target, build configurations, bundle identity, stores, Host
  source and authority remain unchanged. The graph validator compares every
  existing project object against the frozen baseline, allowing only additive
  project/package/product/source-group parent lists.
- `MiniAppsServices.unconfigured` remains the honest composition state. A failed
  catalog load now leaves a persistent unavailable view and Retry action, so
  dismissing an action alert cannot turn missing services into an empty catalog.
  No fabricated catalog, action handler, permission grant or successful dispatch
  is introduced.
- The existing manual workflow selects this proof through
  `target_validation_group=product_split_integration`. Other execution/release
  modes are excluded for that selection. No automatic trigger was added.

## Verification boundaries and executed evidence

| Check | Actual result | Scope |
| --- | --- | --- |
| Six pairwise read-only merge previews of initial source pins | PASS, no overlapping changed paths/conflict markers | Textual source readiness only |
| Graph validator + real SwiftPM manifest evaluation | PASS on Windows | Product linkage, source/test/fixture separation, unchanged original target objects and identity |
| Nine Python graph/extraction/evidence guards | PASS | Includes rejecting AI membership/dependency, Runtime build phase, signing/lowered deployment, missing linked product, duplicate/zero/skipped result nodes |
| `swift test --package-path Packages/HanlinProductSplit --filter RegisteredSplitIntegrationTests` | **5 actual Swift Testing cases PASS** after durable-source integration, Swift 6.3.3, Windows x86_64 | Complete real canonical contract/core products and new exported leaf product; no source substitution or resource helper omission |
| Swift frontend parse of three MiniApps files + registered tests | PASS | Syntax only, no Apple SDK acceptance |
| Bash syntax, YAML parsing, 25-input dispatch limit, `git diff --check` | PASS | Verification route/configuration only |
| iOS 27 extracted target build / simulator install + launch / registered package tests | **PASS, 5 actual cases**, run 43660671583 at `58fa4e45` | Xcode 27.2 (27B52), SDK 27.2, Apple Swift 6.4.2, iPhone 18 Pro runtime iOS 27.0; extracted target scope only |
| Full AI app/host, live MiniApps provider, authenticated OS bridge, two-app installation, physical iPad, visual parity, 278 feature behaviors | **NOT_RUN / unresolved** | No feature acceptance is inferred |

The five executed registered cases are
`canonicalBrokerRoundTripPreservesOriginAndConsumesReturn`,
`canonicalAuthorityDenialIsNotBypassedByAdapter`,
`absentTransportCannotAdvanceToDispatched`, and
`registeredMigrationIsPureAndPreservesIdentityBytes`, and
`unconfiguredDurableReceiverRejectsBeforePersistence`. They exercise real
canonical broker authorization, exact-origin return/duplicate consumption,
unavailable-transport non-dispatch, pure synthetic byte-preserving dry-run, and
rejection of an unconfigured durable receiver before persistence is attempted.
The final successful test output explicitly reports five Swift Testing cases in one
suite; XCTest's separate zero-case heading is not the executed-test denominator.
The earlier initial-product run executed four cases; after the leaf source graph
changed, the focused registered suite rebuilt the affected product and executed
all five cases successfully. Neither run redoes or relabels the producer's 55
portable cases.

Windows resolution evidence is retained locally under ignored
`build/integration-validation-evidence/windows-Package.resolved`. The actual
resolved graph includes swift-ai-sdk `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6`,
swift-argument-parser 1.8.2, SwiftyJSON 5.0.1 and ZIPFoundation 0.9.19. That
generated lock is evidence, not a manually invented app lock or a new committed
file outside the lease. The Windows transcript is the tool execution evidence;
no separate full raw Windows log file was retained.

### Native checkpoint

The full Xcode project references Runtime binary packages whose artifacts are
outside this tranche. The validation script therefore extracts the **same**
registered MiniApps target into a disposable project: identical target object,
compiler settings, package products and actual checkout source paths; unrelated
target/package references are pruned. No source/SDK/engine is copied or replaced.
The generated graph and source hashes are retained. Its result is extracted
target proof, never full-project or live-provider acceptance.

The runner requires actual stable Xcode 27, iOS Simulator SDK 27+, and an
available iOS 27 phone simulator before building. It retains exact SHA, SDK,
source hashes, resolved graphs, build/test logs, xcresults and actual test case
nodes. It does not lower deployment to reuse the SDK 26 Composer proof. The inherited
`Config.xcconfig` is generated in the disposable directory from the existing
full-app simulator workflow template, including its original compiler flags and
intentionally empty CI credential fields; it is hashed and retained. No private
configuration or runtime implementation is substituted. Missing
or duplicate/skipped/zero cases fail verification. Signing and release jobs stay
excluded. The simulator launch, when reached, launches the unavailable shell.

An initial dispatch at `e79082c1` was rejected before any job because adding a
26th workflow input exceeded GitHub's limit. The final route reuses the existing
input instead. Run [43660248871](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660248871)
at `e71c0dac` failed before native compilation because Actions' shallow checkout
did not contain the frozen graph baseline. The runner now fetches only that
exact baseline object, preserving the dispatched checkout. Corrected run
[43660351669](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660351669)
at `4cfe4c49` reached real Xcode 27.2 / SDK 27.2 and an eight-target dependency
graph without Runtime targets, then failed because the inherited ignored
`Config.xcconfig` was missing from the disposable graph directory. This was a
verification setup failure, not a compiler/test pass. The existing deterministic
CI template is now retained there. Run
[43660671583](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43660671583)
at full SHA `58fa4e45d72c3c767853ab0300f85ad4575eb951` includes the durable
Split delta and fifth registered case
`unconfiguredDurableReceiverRejectsBeforePersistence`: **SUCCESS**.

Artifact `product-split-integration-43660671583`, id `14139693176`, GitHub digest
`sha256:81355b1eef171eef1b42152cf209baab03e977c8fe8113a808d3dd8bb1431635`,
was downloaded and inspected locally. Build log reports an eight-target graph
and `BUILD SUCCEEDED`. The built app Info records minimum iOS 27.0 and the
expected simulator-only bundle identity. Successful install is followed by
`simctl launch` reporting PID 20060. This is process launch evidence, not hosted
UI/interaction acceptance. The exported xcresult test tree contains exactly the
five expected passing Swift Testing cases; its local result verifier also passed,
and the original job retained both build/test xcresults. Binary xcresult contents
were not independently decoded on Windows; the runner export and logs are the
reviewed evidence. `process-status.json` records exit 0.

Both real resolved graphs are retained in `resolution.json` with complete pins:
extracted-project lock SHA256
`ccb829ac517d970ef57434d0b71408e2e746d19bea0b43c24522aca6ec6db9c6`;
registered-package lock SHA256
`37e1bea92fa11a36225b4aa28e9039b6b3c107cbdc1b6bb60f20194779bcdeed`.
They resolve the same four root/transitive package revisions listed above.
Native evidence is under ignored
`build/integration-validation-evidence/native-43660671583`. Every retained input
SHA256 matched both the current committed Git blob and working-tree bytes at
review time. This verification of returned evidence is not an additional SDK run.

Composer's separate independently reviewed run
[43658910005](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43658910005)
executed five actual component cases at `3417dc6e` with Xcode 26.6 / SDK 26.5 /
iPhone 17 Pro runtime 26.4.1, targeting iOS 26. Source bytes match `d2126940`.
Artifact digest `sha256:58a836796b0b192a4e286752707e6062a767ecd8ef5dba606e03b0d0ecd92bd9`.
That evidence remains geometry/coordinator scope only, not ChatViewBottom/live
consumers, iOS 27 application, UI, physical device or visual parity acceptance.
It was carried unchanged and not rerun merely for this handoff.

## Open composition and security decisions

The existing concrete `HanlinMiniAppHost`, `HanlinScriptingPlatform` and
`ScriptingPackageCenterViews` are app-only; the Host has a private initializer
and the platform depends on app SwiftData/services. No exported shared provider
exists for `MiniAppsServices(discovery:launch:packageManagement:)`. The necessary
next contract is an existing-implementation provider exposing current canonical
discovery, package refresh/lifecycle, launch destinations for Swift / ScriptUI /
NativeScript / Expo, and existing package-management UI with explicit owned
storage/model context. Noam must agree on any actual Host ABI extraction;
copying these implementations or making the AI app a library is not an option.

URL ingress is not wired to execution. The assembled durable receiver requires
a trusted request source and atomic/integrity-protected persistence, and records
ambiguous interrupted execution as `outcomeUnknown`; production implementations
of those bindings are absent. Its fixture persistence is excluded. The producer
reports 30/30 durable checks (29 Swift cases plus real competing/restarted Windows
processes); those results are writer evidence, not repeated integrator execution
or authenticated OS transport proof. Subsequent independent QA requested two
fixture corrections: interrupted `restoreBefore` recovery must not leave an intent
that later finishes the after-state, and oversized JSON must be rejected before
replacing a readable slot. The Split owner is correcting these; fixture acceptance
and independent cache provenance remain open. These excluded fixture issues do
not establish a production-target compile failure. A URL cannot establish
authority, and the sender ledger is not cross-process exactly-once execution.
No ChatEmbeddedResultHost/schema/A2UI-02 migration or Composer-owned source was
edited by this integrator. A2UI remains the gated prototype with SDK/inline
acceptance unproven. Live migration, credentials, AppGroups/Keychain/CloudKit,
production App ID/signing, main merge and TestFlight remain separately gated.
All 278 historical behavior rows retain their producer NOT_RUN/BLOCKED status.
