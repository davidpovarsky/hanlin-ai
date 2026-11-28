# Original navigation transition integration — 2026-11-23

The unified SDK was missing the already implemented Host API 1.2 navigation capability. Maktabah's current original adapter already conforms to `HanlinHostNavigationTransitionSource`, and its chat owner calls `dispatcher.openWithContextTransition`. Its prior canonical lock `b66aa5e0e979f36d1a34b85e08899449b72d1dc2` therefore did not contain the declarations its actual source needs.

## Preserved source

Original implementation `d49801160dd7e84d84db3903a0c6f7dedfe9c017`, source freeze `e00498e33f106cc43be0476ffa2e09329c8ca300`, and native proof `4568a850c2a4728ed1a58e17eb3612fdb012b170` were replayed without conflict. Before integration, the dispatcher, proof driver and PUBLIC_API document blobs exactly matched the original implementation's parent. No navigation, permission, session, exact-JSON, credential or persistence implementation was rewritten.

The added receipt and protocol correlate the original request/session to an observed native destination and a host-issued successor session. They retain cancellation/revocation checks, uncertain-effect receipts and stale-origin rejection. The old `open` method and the `queued`/`presented` enum are unchanged; there is no new enum outcome requiring downstream exhaustive-switch changes. Lorvex's Host API 1.1 adapter remains valid. Maktabah already has the real 1.2 caller; it needs the corrected canonical dependency pin and actual native acceptance.

## Evidence mapping

[Original native run 44567189233](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44567189233) passed 58 selected cases: 28 navigation, 22 session, 6 context, one callback-convention and one original-byte schema case, plus the iOS Simulator package build. It ran at `e00498e3` on macOS27.0.1/Xcode27.2/Swift6.4.2; it did not run the real consumer UI.

All 199 retained archive members were rechecked against their recorded SHA-256 and sizes; CRCs passed. All 389 archived source inputs match both the retained source tar and original Git commit. The raw-proof ZIP is explicitly a lossless local repack of the original artifact, SHA-256 `9f1bbbd83bf2ec1f74321e3b618fba4725c51c60c5474db2fb1d5536d33a64cf`; it is not presented as the original GitHub-upload ZIP.

Of those 389 source inputs, 383 are byte-identical after integration. The six changed files are the existing HostSchemaValidation additions, three Platform descriptor/presentation/script contracts, their manifest schema resource and the canonical calendar implementation. Six new package files cover the original input-integrity, tool-approval/presentation and calendar changes. The full path/hash mapping is in the adjacent JSON receipt. The navigation dispatcher, receipt protocol and all 28 original test bodies are byte-identical to the native-proven source.

This retains historical behavioral evidence; it does not relabel the old run as a full current-package pass. No historical suite was rerun during integration. The current package and Maktabah host compile/native navigation must validate the updated dependency graph. Focused schema/input-integrity/calendar gates already assigned to the combined root validation cover their changed closures; a failed or changed host journey must be rerun at its actual corrected source.
