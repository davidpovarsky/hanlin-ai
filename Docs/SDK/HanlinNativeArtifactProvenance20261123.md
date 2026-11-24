# Native SDK consumer source provenance — 2026-11-23

## Reproduced boundary

A managed native installation could previously reuse a published catalog after the pinned SDK revision changed a declared preparation input. The normal installer `--check` inspected managed paths and catalog checksums but did not bind those assets to the current pinned source. A similar omission allowed an older `RuntimeHostResources.zip` after a committed Node Host module change.

The actual Git/sparse regression fixture reproduced seven unsafe admissions through the complete production install/check paths. The fixture artifacts are small protocol inputs, not release artifacts or native runtime acceptance evidence.

## Shared correction

`Scripts/SDK/native_artifacts.py` now requires the exact eleven declared preparation inputs and compares their SHA-256 values with the immutable pinned Git blobs. It reads those blobs with `ls-tree` and `cat-file --batch`, so a legitimate sparse checkout does not need to materialize every preparation file. Modified materialized files, staged changes, missing catalog inputs, non-regular Git entries, and a changed revision fail before artifact download or extraction.

The original source/archive validator remains the authority for selected Node Host support. The consumer temporarily materializes the original `Scripts/Runtime/runtime_host_archive.py` and the tracked Node Host subtree from the same pinned revision, then invokes its existing `validate` command. That preserves its package/lock, direct dependency versions, dependency patch/license hashes, and exact top-level module inventory and byte checks. It performs no npm operation, native build, or alternate archive-format validation.

The original Node Host check runs before a newly downloaded support archive replaces any installed path or records success. It also runs when managed support is reused and in the normal read-only native `--check` route. An invalid Node Host archive is rejected before its support replacement or receipt update. Earlier independent records retain the original per-record resumption behavior.

The only change in `Scripts/SDK/install.py` is the three-line call to this shared `verify-source` command inside the existing nonempty `managedNativeTargets` branch. Source-only profiles retain their complete prior execution path. No package manifest, product dependency, native builder, binary-target mode, artifact layout or host source is changed.

## Focused verification

| Obligation | Before | After |
| --- | --- | --- |
| Changed committed preparation input, with source absent from sparse checkout | Incorrectly accepted | Rejected before artifact IO |
| Modified materialized preparation input | Incorrectly accepted | Rejected before artifact IO |
| Incomplete declared input set | Incorrectly accepted | Rejected before artifact IO |
| Existing installer `--check` after preparation-source pin update | Incorrectly accepted | Rejected |
| Existing installer `--check` after Node Host module pin update | Incorrectly accepted | Rejected by original Host validator |
| Cached managed Host archive with changed pinned module | Incorrectly accepted | Rejected without modifying archive/receipt |
| Newly staged Host support with changed pinned module | Incorrectly accepted and installed | Rejected before replacement/receipt |
| Documentation-only descendant with sparse source | New valid control | Original assets reused; install/check pass |

Before execution ran three new methods/seven cases and recorded all seven failures in 0.432 seconds. After execution ran four new methods/eight cases and passed in 1.212 seconds. The one existing directly affected download-selection method was given the newly required pinned source/valid Host ZIP fixture and passed in 0.184 seconds. Its original assertions still require exactly NodeMobile plus its Host support, with no Python or Expo download.

No unaffected existing test, native runtime build, Apple test, UI gate or producer workflow was replayed. Raw logs and before/after traces are retained in `Docs/SDK/NativeArtifactProvenanceEvidence20261123`.

## Producer compatibility and remaining acceptance

Neither changed installer file is one of the eleven declared preparation inputs. The exact mode/path/blob inventory of those eleven files, the original Host validator, and all 131 tracked Host files is identical between the active producer source `2549bb1395045e1514ec6c273239fcdaf18af207` and this repair's source base `91949a1d7904744c97f951ad4ec63a91d487d058`: 143 records, SHA-256 `71c71c222423172c8e8ea0f47946f82e0c35491393a550a9cf118b5d66418c9e`. The Host files total 597,839 bytes; temporary source materialization does not duplicate the native runtime archives.

The original export, publication, catalog/ZIP validation, framework-slice checks, source-input collection and host-staging functions are byte-identical. Export still performs its existing Node Host source/archive validation. The eleven-file comparison is explicitly a declared preparation-input check; it is supplemented by the original Host source/archive policy, not presented as proof of every possible native source dependency.

Run 45177292887 remains owned by the root lane. This repair does not establish its outcome or authorize publication from a failed producer. Publication still requires the exact repository, genuinely successful producer, source-bound full 14-framework/four-support catalog, all original archive checks, immutable assets, and anonymous readback of all 18 assets. The eventual full-profile installation must use the final immutable SDK pin and this corrected consumer verifier.

The accompanying JSON receipt binds the exact changed source/test hashes, unchanged original functions, producer source comparison and raw focused evidence. It reports deterministic controller verification only; real public artifact installation remains a separate required step.

## Independent source review

The presentation lane reviewed the exact production hashes recorded in the JSON receipt and found no concrete blocker. Its bounded read-only review covered pinned Git reads, sparse inputs, selected support ownership, fresh/resumed Node Host validation, and the installer check ordering. It confirmed reuse of the original Host validator and preservation of source-only profiles and per-record resumption. That review executed no tests, downloads, build or CI action.
