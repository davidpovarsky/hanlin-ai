# Original Yams app adoption

Task: [SKILL-YAMS-02](https://app.asana.com/0/0/1220546710401425).
Base: `89f2caaf2c2a7d24e247713fa3793b83afc0e321`, existing wave integration.
This focused adoption branch replaces the app's handwritten frontmatter parser
with `HanlinSkillFormat`, using original Yams 6.2.2 through SwiftPM.

## Source and graph

- All nine package files are byte-identical to native-tested
  `e44c57cf348b1037baa8416277a3414d7e93b805`, supplied in clean handoff
  `51095aa9f5b0427217c7d8fa5abacb5af22414bc`.
- App changes are the four Skills files and test deltas from `bedecb5a` and
  `727f67b6`. Three-way integration preserves existing Observation, store revision
  notifications and the manager's direct-Markdown passive-preview test verbatim.
- The app and unit target link the single local package/product. The PBX change
  adds four objects and five array entries; every previous object is preserved.
  SDK/Host/scene/renderer implementations and MiniApps membership are unchanged.
- The original dependency is exact Yams 6.2.2, revision
  `a27b21e0c81c5bf42049b897a62aaf387e80f279`, retaining original CYaml and license.
  No library implementation is copied into app source.

## Validation

Authenticated original package execution:
[43757913093](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43757913093)
passed 22 unique test identities / 27 parameter-expanded invocations on each
macOS, iOS 26.2 simulator and iOS 27.0 simulator. These executions occurred at the
supplier SHA; they were not rerun on the adoption branch. The manager independently
authenticated both API artifact digests, all ZIP CRCs, each of the nine Git/tar
source hashes, raw locks and each platform's 22 distinct Passed xcresult cases.
The full identity ledger is `evidence/skill-yams-native-43757913093.json`.

Fresh local checks: 15 existing project-graph tests and 34 existing CI/cache
regressions passed. Object comparison proved the additive graph change, and YAML
comparison proved all 20 previous jobs unchanged apart from exclusion of the new
manual resolution route. Event triggers and permissions are unchanged. All five
affected app/test Swift files parsed with the iOS simulator conditional target on
Windows; the compiler emitted Windows sysroot/SDK warnings. This is syntax evidence,
not Apple-framework compilation.

The manual `skill_format_app_resolve` route runs only actual Xcode app dependency
resolution, retains the original before/after lock and source archive, and records
measured phase cost. It runs no app build, app test, simulator boot, app signing or release.
Its actual result and lock must be reviewed before adopting the generated lock.
The zero build/test counters describe the app resolver phase. Canonical dependency
preparation separately compiles its metadata build tool when needed and builds the
ExpoModulesJSI bridge for device/simulator; those are prerequisite component builds,
not app compilation or app test acceptance.

First app-graph run43759980799 at4c82bbfe ended INFRA_ERROR/exit74,
zero builds/tests: the clean runner lacked11 local NativeScript/Expo XCFrameworks.
Original artifact14180290549 digest
`1a4337561f4bda2adbedf4da43516f9792a20868a6327d275532f051656ebfe2`
was independently authenticated (ZIP digest/CRCs). It retains the actual Xcode27.2/
Swift6.4.2/SDK27.2 preflight, source archive, command and resolver error log. Xcode's
temporary error-only xcresult was not retained by this initial script; no test or
app screenshots existed. The follow-up automatically copies such error bundles.

The follow-up invokes the existing canonical NativeScript metadata-tool cache and
NativeScript/Expo dependency staging before resolution. These original scripts
validate/stage their pinned native frameworks; the metadata compiler is a build
tool, and existing framework staging uses its ordinary ad-hoc signatures. No
runtime engine/app build, app signing, test, simulator boot or distribution is
requested. The canonical shared scheme is AI_HLY (target AI_Hanlin); the follow-up
also verifies that checked-in scheme/target association. Only this affected
resolution operation is repeated after repairing its missing prerequisites.

Follow-up43760670564 at7dea67f3 successfully staged both NativeScript binary
targets, then stopped before Expo/resolution because the broad NativeScript
preflight additionally requires a prepared SwiftUI demonstration fixture. That
fixture is not an input to app package resolution. This is INFRA_ERROR with zero
builds/tests/resolver execution, not a package test failure. Original artifact
14179769489 digest
`fc3df7621111a9a52955783c3c2354af08d38cfd14295dc13c88efdbb9d172e6`
was independently authenticated. The next scoped route retains the canonical
binary preparation and its validation, omits that unrelated fixture gate, then
uses Xcode itself as the actual binary-target consumer. The existing broader CI
preflight and its fixture requirements are unchanged.

Final app resolution43761037885 atc1a53977 is RESOLVED_ONLY_PASS. Original
artifact14180119013 digest
`d245f3e04099528f99286784a244f417b78fb47c5665a061dce49954997abb53`
was independently authenticated, including ZIP CRCs,129 Git source-input hashes,
the retained source tar and all nine package files against e44c57cf. The actual
app lock was adopted byte-for-byte, SHA256
`c71ab78897eb3c84f245f5efa96c5371b61172f712b8ff534bec7a9d19982fb6`.
Yams is6.2.2/a27b21e; existing SDK e7bf341 and Swift-JSON f2a0d12 pins match
their previously authenticated package locks. The source manifests and toolchain
constraints were unchanged after this execution; the checked-in app lock is its
actual output. No second resolution or package-test rerun is claimed.

The old app lock was stale for existing linked packages: actual resolution adds14
pins, including Yams and13 existing direct/transitive requirements. It also changes
swift-cmark0.6.0 to0.9.0 and drops the two previous docc pins. The pre-existing frozen
Markdown fork f59bd0d already requires swift-markdown exact0.7.3; that original
manifest requires swift-cmark from0.7.0, so the old0.6.0 pin cannot satisfy it.
MarkdownUI's existing constraint also permits the actual selected version. These
facts were checked in the original manifests at the exact resolved Git commits.
The pin change and documentation-pin pruning remain explicit draft review items;
affected Markdown consumer validation is NOT_RUN until prior evidence is audited
or the affected cases execute. No earlier Markdown pass is silently reused.

The job took5m54s. Reported measured phases were native staging155s, NativeScript
installation4s, final preflight5s and resolution148s; those phase totals exclude
other job/setup overhead. Native staging includes the actual ExpoModulesJSI bridge
build, separately from zero app builds/tests. The standard report's estimated
savings are not measured speedups. Full result and pin diff:
`evidence/skill-yams-app-resolution-43761037885.json`.

NOT_RUN: affected actual app `SkillStoreAndImportTests`, catalog/exposure consumers,
Skills UI/XCUITest, physical iPad and complete app compilation. The canonical
Runtime metadata correction is still required for the app build. Original package
passes do not cover these obligations. Task remains open; this branch is a draft
integration candidate, not final app acceptance or a main/release merge.
