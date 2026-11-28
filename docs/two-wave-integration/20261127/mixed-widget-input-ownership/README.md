# Mixed application and Widget input ownership

## Problem and actual reproduction

Two unchanged retained-archive regressions ran against source `34dc92c16b37c7e14453e86f25f14d8e5063556a` and failed: two methods, two suites, three issues, native exit 1 with no resource or deadline stop. The complete original log has SHA-256 `aa269ad8fb90852490100d717a75012ecb8573f282a5838231bbd69204c1f926`.

The original NativeScript analyzer accepted the archive's prepared structure and runtime/Core versions, then Widget preparation attempted to parse the retained foreground TypeScript input. The original ScriptWidget import adapter rejected the inline `type JSONValue` declaration. The Expo regression produced an actual 8,997,211-byte Widget program, including the 6,740,756-byte foreground `bundle.js.map`; the unchanged artifact writer rejected it with `invalidCompilerOutput("invalid_widget_program")`.

The NativeScript archive is SHA-256 `3441747a86120c936135f6a472be1a8e029f1b3480ea020a484585d25225d4b3`. The Expo archive is `dae2e23187170548f197f532a991aa26fc3fca1f394613499d2e24696f7199ed`. The Expo regression exercises original Widget preparation and artifact writing only: its historical native package versions differ from the current host, so it does not claim a complete current-host import.

## Change

Source commit: `4aff8526c3037d1b18a2af831911771e342d7742`, parent `34dc92c16b37c7e14453e86f25f14d8e5063556a`.

One private projection is added to the existing public `HanlinWidgetCompiler.prepare(manifest:entryPath:files:)` entry. It activates only for the recognized source-bearing mixed Expo/Widget or NativeScript/ScriptWidget format. Bundle-only, pure Widget, and unrecognized authoring formats continue through the original path.

The projection verifies complete visible source and compiled inventories and their actual byte digests, then uses the existing canonical producer's entry/package/source relationships to identify editor and foreground inputs. Hash membership alone is insufficient. It retains original published resources, byte-exact presentation/source copies, and the real NativeScript `modules/` resource aliases before subtracting foreground inputs. Unknown published helpers remain available to the original dynamic `$import` implementation.

For NativeScript, emitted module/map pairs require the canonical output path, a single retained source, and exact embedded source bytes. The original app wrapper must target the admitted entry output. Unknown native outputs and dependencies remain in the original compiler input rather than being removed by directory name. For Expo, the projection subtracts only the actual foreground bundle and its corresponding map, plus equivalently admitted dedicated assistant pairs; it retains assets and other published files. Explicit sharing takes precedence, so an oversized declared shared resource still reaches the original artifact limit.

All original package bytes still reach the source-inclusive artifact writer. No archive member, authoring source or foreground map is deleted. The private compiler body, presentation preparation, original Babel adapter, runtime, pins, and 3 MiB artifact limit remain unchanged. Removing the new private helper and reversing the one call-site substitution recovers the entire original compiler byte for byte.

## Review correction

R1 incorrectly required an empty emitted source-map `sourceRoot`. R2 treats it as debugger-location metadata while retaining the output-path/source-byte binding. The actual installed TypeScript 5.9.3 emitter and [official TypeScript documentation](https://www.typescriptlang.org/tsconfig/sourceRoot.html) confirm that this setting may contain a path or URL. The projection neither resolves nor fetches it.

R2 also follows the producer's original packaged-project merge: an optional retained authoring descriptor can inherit its entry/configuration from the outer envelope. An absent authored package does not acquire invented name/version defaults. The focused compatibility source includes both the configured debugger location and the optional inherited-authoring case. R1 and its review remain retained separately.

## Focused qualification

The two retained regressions and both archive inputs are byte-identical. Eight new non-parameterized methods invoke the real public Widget compiler, original ScriptWidget runtime, or original artifact writer:

| New method | Behavior checked |
| --- | --- |
| `mixedNativeWidgetKeepsDynamicImportsAndResourceAliases` | Computed import names, missing-import false result, real file/storage values, binary/map resources, and optional inherited authoring. |
| `compiledInventoryDoesNotHideUnrecognizedPublishedHelpers` | A published helper remains usable even when listed among compiled outputs. |
| `configuredDebuggerSourceRootDoesNotChangeOwnership` | A configured debugger URL does not reject the canonical source/output pair. |
| `declaredSharedModuleAndMapOverrideForegroundPairClassification` | A real shared emitted alias and legitimate map remain readable/importable. |
| `incompleteOrChangedVisibleInventoriesFailClosed` | Six missing, added, changed or overlapping inventory cases are rejected. |
| `escapingChangedAndAmbiguousResourceCopiesFailClosed` | Five escaping, changed-copy or ambiguous-resource cases are rejected. |
| `explicitlySharedLargeResourceStillHitsOriginalArtifactLimit` | A real shared resource remains subject to the unchanged writer limit. |
| `bundleOnlyAndUnrecognizedAuthoringKeepOriginalInputs` | Three original-format/fallback cases retain actual import behavior. |

At the source seal, these new native outcomes and repaired retained-archive outcomes are **NOT_RUN**. Completed checks are source hashes, the exact original compiler inverse, unchanged original paths, retained RED-packet integrity, and the current actual SDK source-membership intersection. They are not substitute runtime tests.

The proposed original Swift command selects exactly ten methods: the two retained oracles and the new eight-method class. The Mac owner executes it only after root integrates the reviewed source. Original controller limits and evidence retention remain in force.

## Impact and limits

The production compiler is one member of the current actual 396-input SDK inventory; the new test is outside that inventory. A fresh SDK collector/producer qualification is required at the integrated source boundary. The existing Widget upstream provenance manifest does not own this compiler file and remains unchanged.

Inventory validation establishes package consistency and ownership relations, not publisher authentication. Hidden rows are outside the existing visible-file enumeration and are not claimed rehashed. The change does not establish successful application installation, hosted OS acceptance, or resolution of the separate catalog startup observations. Those outcomes require their original native gates.
