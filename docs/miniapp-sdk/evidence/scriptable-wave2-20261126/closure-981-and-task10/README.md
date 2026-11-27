# Bounded source qualification and SCRIPTABLE10 reconciliation

## Accepted evidence and current source

This read-only comparison uses product9819697c1792119a6a93b492d12abad7b3330c93 and routing3f7c4a6f3cafa3919301750086cd1abf5c459955. All checked production/graph/test inputs are identical between those two revisions. No native test was launched.

The unmodified canonical generator was executed on Oracle with every canonical package manifest and required project/lock/generator input. Both selected Package.swift outputs are byte-identical to the retained native manifests: Motion has five local targets (SHA61b583342dc4c35519a7b7614c3269140edbd10590f7faf5269467b997e2bdc4); shared Chat has six (SHA83823bf6d107dc14f3b9f03e6ab6e4289c62728279cd34ca1da39dbba07c1e6a). All eight retained external dependency revisions equal the current canonical lock. Generation is not an Apple build.

| Scope | Exact comparison | Decision |
| --- | --- | --- |
| Motion native acceptance953 | 416/418 selected source/resource files unchanged; all10 fixture/orchestration inputs and all7 focused Motion/fixture files unchanged | Retain original B/A/C and visual outcomes at953. Focused behavior sources and assertions are unchanged. |
| Motion changed module inputs | HanlinDescriptors adds capture entry-point/exposure mapping; manifest schema adds capture and hanlin-expo | Whole compiled-module closure is not byte-identical; current contract/module compilation remains VERIFY_REGRESSION. |
| Shared Chat native acceptance730 | All four actual XcodeGen/host/test-source inputs and both interaction implementation files unchanged | Retain the five original action/metrics outcomes at730, including its recorded iOS27.0 runtime. No new current execution is claimed. |
| Shared Chat module delta | 419→421 files: the same descriptor/schema changes, the already accepted953 Motion correction, and added ShortcutProgress/ValueCodec | Current compilation and original contract/codec tests remain required; this is not a blanket reuse of the entire module. |
| Selected graph and pins | Actual regenerated five-/six-target manifests and eight external revisions unchanged | REUSE_ACCEPTED for these exact graph/pin requirements, despite changed unselected global project/extension inputs. |

The exact changed files, hashes, source inventory and fixture/pin comparisons are in closure-qualification.json and current-source-resource-manifest.json. A direct-reference review found no descriptor/schema/new-Shortcut references in the focused Motion fixture/implementation or the two interaction implementation files. This supports the semantic boundary; it is explicitly not a compiler call graph or a replacement native run.

The remaining bounded module obligation is current original HanlinPlatformContracts/codec/schema coverage and current HanlinChatUI compilation. A concrete changed caller or diagnostic can require a focused rerun. Nothing here asserts full-app, signed-device, current-runtime or release acceptance, and no passed evidence is erased.

## Actual SCRIPTABLE10 scope

The original [Task10 note](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1220917894278244) was read, including its original acceptance paragraph and retained milestones. Files tags, iCloud if supported, conflict/no-data-loss behavior, drawing and device/layout adaptation are explicit. A standalone What's New screen is not named. The note's identity, modification time and digest are in scriptable10-scope.json.

**Files tags:** The installed iPhoneSimulator27.0 SDK explicitly marks NSURLTagNamesKey unavailable on iOS. The native Files/document-browser workflow and metadata preservation need a real original OS probe. Use supported system document UI and the existing coordinated, versioned workspace flow for a demonstrated workflow gap. An explicit project export/import may be needed if its runtime workspace URL is private. Expose only the selected authored project, preserve the current editor and lineage, and do not introduce a fabricated generic tag API or a new File Provider extension.

**Cloud placeholders/conflict:** Source configuration includes the existing container and CloudDocuments/CloudKit services, but signed container availability remains a separate gate. Approved74bd corrects the concrete blocking root lookup and async lifecycle problem with8 portable passes (original4 plus new4); native Studio inventory becomes14 including existing project6. Placeholder/remote-conflict behavior remains awaiting the original OS/File Provider probe. Public NSMetadataQuery/download-status APIs provide a viable conditional route once actual container access is established and the probe identifies a gap. Keep current dirty editor state and unresolved copies intact.

**Device/layout adaptation:** Run actual original Studio flows at applicable compact/expanded/windowed sizes, rotations, large text and RTL; repair observed failures in the existing views. A generic simulator is not an exact Duo device result. The requirement does not create a speculative new device-specific product UI.

**What's New:** Keep the release comparison visible as comparison-only. It is not an automatic Task10 implementation requirement and does not justify adding a new standalone screen.

## Authorities

- [Apple FileManager ubiquity contract](https://developer.apple.com/documentation/foundation/filemanager/url(forubiquitycontaineridentifier:)): supported container lookup must run off main; nil has a real unavailable meaning.
- [Apple iCloud service entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.icloud-services): source configuration and actual signed/runtime availability are distinct evidence.
- [Apple File Provider](https://developer.apple.com/documentation/fileprovider): Files document sharing and system-managed metadata are scoped public routes.
- The exact installed-header identities and source configuration are retained in the approved Studio proof at studio-cloud-root-20261126/configuration-and-api-boundary.json.

The original Scripting-JSC/ScriptUI development boundary remains frozen. These findings apply to the existing active engines and native standalone authoring workflow.
