# Consumer upgrade qualification — exact SDK ab46931b

This is a read-only qualification for a future coherent SDK repin to **ab46931b776f1701d554b230aa3dd7d8166dfa76**. It is not a new native result or an extension of the historical d49-to-668 identity proof. No consumer source or lock changed, and no build, test or workflow ran for this comparison.

## Actual selected profiles

The exact candidate canonical generator was evaluated once using its 18 actual child manifests. All 22 generator/parser/project/lock/manifest inputs were checked against immutable ab46931b. The old d49 and 0dae generator/install proofs were reused. Each candidate output is byte-identical to the corresponding actual installed Package.swift. Complete selected Git path/mode/blob records were compared, and every installed selected file's bytes and executable/symlink mode was independently checked against its locked object.

| Host | Observed host commit | Installed SDK | Existing → candidate entries | Exact selected changes |
| --- | --- | --- | ---: | --- |
| Maktabah | be28510e5cbb5dd241e79e9d60501bdacdcadea4 | d49a4fd4115b8335105d2991bf74ab4d7f6aad2d |544 →545| Provider factory modified; original draft added;543 entries unchanged |
| Lorvex | a51b048d33e8e377ea589692d9fe9f87489c7b83 |0dae98f7b44b3cb4ee4d8dacd1913f2ed317a965|535 →535| Provider factory modified;534 entries unchanged |
| Anytype | fa078feb6bd496689b812ccf00945dce60c03599 |d49a4fd4115b8335105d2991bf74ab4d7f6aad2d|546 →547| Provider factory modified; original draft added;545 entries unchanged |

All three selections retain the same target source paths, public product lists, declared external dependencies and generated manifests. They contain **zero binary targets** and introduce no SDK native-artifact inputs. Resources, modes and all other selected implementation files are unchanged. Actual installations remain Vendor/HanlinSDK in Maktabah/Lorvex and Dependencies/Hanlin in Anytype.

## Precise implementation deltas

All hosts select the correction in **Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKProviderFactory.swift**. Git blob changes from 08d6e5c8a5bcf4143e9ad5f29298a353034924dd to 61be72ea58eddc736b843cf5a84228f16c719ce7; mode remains 100644. SHA-256 changes from 37040bbbf933960cb47046fbedaeaad953b59371607b0ec3062cbbefb1ee1c1a to 48fb93718f2eb30a0b947aceabb37f2b2b4f0ffaa79bb75c77cafa400401fcc9. This is the original repeated endpoint-query key crash fix: last explicit decoded-name value wins, nil values remain ignored. Public descriptor and transport signatures are unchanged.

Maktabah and Anytype additionally select **Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Composer/HanlinComposerDraft.swift**, mode 100644, blob 23002e64c4491cd3278f4cb5e7ab630cdd4492f3, SHA-256 122318843d15df87f7b719750b1703f4f830044daa62a0ef9030c20b788276ca. It is the same original class already compiled and used successfully in Lorvex's accepted 0dae native run. Their existing adapters do not reference the new type; no adapter behavior changes are included in this source-only addition. Lorvex already has this exact file, so it has no selected Composer/UI/resource delta.

The four explicit Sendable declarations in NativeAppPresentation.swift and NativeAppRoute.swift belong to HanlinAgentActivityCore. Neither source path is in any of these three selected graphs. That full-application correction introduces **no consumer-selected delta** here and does not justify repeating these host gates.

## Exact manifest and source-record hashes

| Host | Candidate and installed Package.swift SHA-256 | Candidate selected path/mode/blob record SHA-256 |
| --- | --- | --- |
| Maktabah | `2d5cf939b5c8f43f30ee2be1e382e5f52e13a3f4cd9fc66709cb4ee96c2f23e4` | `1c21f980669603f3fea67e75e52e826c6085f482452989d316f8900231d3e340` |
| Lorvex | `29c126b9305e88bbcaed57512374e986f7225a0c87d332950f6ba3deda9bca26` | `162b5bf52c15afa65e1f4f582e791f5947a5ba1651228430bbecf7aad3991ab8` |
| Anytype | `518f91d40d3433a88ab6255c252bc2c81fa1e2199dad0322b4136bb7f2d6f20c` | `b3f3d02e799a1febdbd8d18fdc4cce5d51adaf3c865083ef74c9cdb01b392c6e` |

The machine receipt records each baseline record digest, full selected source-path list, products, exact changed objects and all 22 candidate generator inputs: [the machine-readable qualification](../../docs/agent-sdk/evidence/consumer-upgrade-20261123/qualification.json). Historical [199/668 observations](HanlinSelectedProfileIdentity20261123.md) remain unchanged.

## Minimum remaining qualification

1. **Reuse the exact existing provider-fix evidence.** Both Foundation-only production-declaration cases passed in the 046c253d receipt. This comparison matched all three production input hashes against ab46931b, so those cases need no repeat. They demonstrate the corrected query policy; they do not claim Apple/transport/live-provider execution. The original package Swift Testing regression remains NOT_RUN in that historical receipt.
2. **The next coherent candidate Apple compile remains pending.** The ab469 root gate failed in retained application projection code before all 26 test selectors. The subsequent original helper correction is outside these three selected profiles, as qualified below. A successful next root gate can supply the remaining common-module native compile observation. No new host UI, Agent, renderer or device replay is required by the selected deltas alone; no native success is inferred from the failed ab469 gate.
3. **At a later authorized repin, run only canonical installation/profile checks and preserve actual inputs.** Install from the final locked revision, use canonical --check, and bind the generated graph, selected deltas, host source/test/configuration, dependency resolution and runtime identity. A later SDK change must be compared separately. None of the three locks is changed here.

Lorvex's 1/1 original UI result and four reviewed screenshots remain attributed to 2e6a5e20/0dae; its older 6 Agent / 5 presentation/device evidence retains its own source identities. Maktabah's 48 component + 1 UI acceptance remains unchanged. Neither result is relabeled as a new ab469 execution.

Anytype's currently owned fa078/d49 outcome remains partial: app build and original native preparation passed; original UI failed at Home/background admission, and later authority/logout did not execute. The owner is correcting two harness files, outside this SDK comparison. A future SDK repin does not erase that existing host gate or its pending repair. No Anytype overall PASS is claimed here.

Physical-device installation, signed distribution, live-provider execution and OAuth pairing remain separate observed-evidence boundaries. A source-equivalence report creates none of those outcomes.

## Appended exact-input extension — candidate 2ff3d6bc

The initial ab469 generator/profile observation above remains intact. Candidate **2ff3d6bcc724b424e22078fc537e17ff4a914bd2** was qualified by exact relevant-input and selected-source comparisons only. Neither generator nor any earlier test proof was rerun.

All **22** generator/parser/project/lock/child-manifest Git objects remain identical. All three complete selected path/mode/blob byte streams remain identical to ab469, with the same generated manifest hashes and zero binary targets. The full intervening changed-path list is retained in the machine receipt.

The original helper correction changes:

- AI_HLY/Downstream/ChatPresentation/ClassicChatAgentProjection.swift
- Packages/HanlinPresentationSDK/Sources/HanlinAgentActivityCore/Projection/AgentActivityToolProjection.swift

Both paths are outside every selected source closure. The C-only workflow and Motion capture changes are also outside those installed product inputs. They introduce no additional consumer implementation, manifest, resource, dependency or native-artifact delta. The exact provider-factory modification and optional original draft addition remain the complete host-selected changes described above.

The next Apple compile is pending. This extension does not claim the failed ab469 run passed any of its 26 test selectors, and it does not relabel prior host acceptance as a new 2ff execution. The three host locks remain unchanged.

## Appended coherent source qualification — 37c03e9d and native candidate 32da9e31

The earlier observations remain historical records. This extension compares the completed scripting fixes at **37c03e9d798c88c7621aef8dc1eca9d6d3e6fca4**, then independently checks native candidate **32da9e314e22bbf22391fcf8902302acfbb281e2**. It reuses the original generator outputs: all **22** immutable generator/parser/project/lock/child-manifest objects and their SHA-256 values are unchanged. No generator, resolver, installer, test or CI was executed by this qualification, and no host lock changed.

The actual installed locks, installation receipts, manifests and selected-source-scoped Git status were read again. All remain at their earlier SDK revisions without a selected source edit. The complete original installed-byte proof is reused at those unchanged revisions; the new comparison uses complete immutable Git path/mode/blob streams.

| Host and observed source | Installed SDK | Installed → candidate entries | Exact selected changes through 32da |
| --- | --- | ---: | --- |
| Maktabah, `be28510e5cbb5dd241e79e9d60501bdacdcadea4` | d49 | 544 → 545 | Provider factory and ScriptUI reconciler modified; original draft added; 542 original entries unchanged |
| Lorvex, `a51b048d33e8e377ea589692d9fe9f87489c7b83` | 0dae | 535 → 535 | Provider factory modified; 534 entries unchanged |
| Anytype, `aefb9740c0ac8d52aa2dbd89d389930851396104` | d49 | 546 → 547 | Provider factory and ScriptUI reconciler modified; original draft added; 544 original entries unchanged |

The only additional selected implementation change since 2ff is **Packages/HanlinPlatform/Sources/HanlinScriptUI/HanlinScriptUIReconciler.swift**, selected by Maktabah and Anytype. Its blob changes from `8b5315e1c73811c27edc3818c52529935d9b4e78` to `ccff0e4069a47c599045ee23fbd890b2124b54f7`, mode 100644 unchanged. Final SHA-256 is `e4def17533c90877b481dba6da9ab09dbf55a54f4a6979376637cc39cda1fbc6`. The original keyed reorder now rejects missing or duplicate keys before dictionary construction; the shared private uniqueness validator reports the actual repeated key at all four original diff/reorder boundaries. Valid output construction, the public error type and transaction behavior are preserved.

The legacy **HanlinScriptPermissionAuthority.swift** and **HanlinAtomicScriptStore.swift** are outside all three actual selected source graphs. Their fixes and the store's new native methods introduce no selected consumer change. Lorvex does not select HanlinScriptUI, so the reconciler fix is also outside its graph. There are no added resource paths, changed file modes, external dependency declarations or native artifact inputs. Each generated manifest remains byte-identical to its actual installed manifest listed above; all selections still have zero binary targets.

| Host | Selected path/mode/blob SHA-256 at both 37c and 32da |
| --- | --- |
| Maktabah | `513cf2331375e9270716c091d6fc6868a9935026b7a82ddeb8514ed8a40f2316` |
| Lorvex | `162b5bf52c15afa65e1f4f582e791f5947a5ba1651228430bbecf7aad3991ab8` |
| Anytype | `8db523e721b3183513a51e005f528912b4535d8097c724f6746baa833273b90b` |

The 37c→32da changes are only the original AtomicScriptStore test fixture and two associated evidence files. All 22 inputs and all three complete selected byte streams are identical across that extension. Candidate 32da is the proposed coherent repin source; this observation does not claim that its Apple gate has passed.

### Existing focused evidence and remaining gate

The final reconciler's [five-case diagnostics receipt](../../docs/agent-sdk/evidence/script-ui-reorder-diagnostics-20261123/receipt.json) is reused after matching **all 26 compiled input hashes** to both immutable candidates. Four cases check the non-first duplicate at the four boundaries; one checks preserved valid reorder/property/empty behavior. All five passed on Swift 6.4.3 arm64 Linux. This compiled complete canonical PlatformContracts and whole Foundation-only ScriptUI contract/reconciler files; it did not execute SwiftUI or an Apple UI. The original six-case receipt and SIGTRAP remain attributed to their original source, without a fictitious final-source replay.

The provider-factory bytes still match the two exact original focused cases qualified above. The original draft addition is exactly the class compiled and accepted in Lorvex at 0dae. Neither proof needs repetition.

Parent reports native run **45163990486** at **32da9e31** started at 11:18:25 UTC with the original 26 application selectors plus three AtomicScriptStore methods/four cases in the focused package route. Outcomes are **not inferred or consumed by this qualification**. A successful common candidate Apple compile can supply the remaining shared-module compile observation. This audit establishes no new host binary, live provider call, signed distribution or physical-device behavior.

### Minimum owner-coordinated repin plans

These are read-only plans at this observation point. Canonical install/check and new source binding are separate actions to perform once each owner can safely update its exact inputs.

| Host | Required source and policy updates | Verification and retained acceptance |
| --- | --- | --- |
| Maktabah | Change `HanlinSDK.lock.json` and the tracked mode-160000 `Vendor/HanlinSDK` Gitlink together to 32da. Before a future focused/live invocation, bind `hq-stage2-focused-apple.inputs.json` application source, Vendor tree and `hanlin_gitlink` to the concrete reviewed candidate commit; update the corresponding `SOURCE` / `REVIEWED_SOURCE` in the two focused/live drivers. Preserve all four tree comparisons and binary/resource/fixture/secret/cleanup guards. | Run its existing `prepare-hanlin-sdk.py --sha …` and `--verify-only` with the new canonical installer. Keep the previous 48 component + 1 UI result at its actual source. The selected changes alone do not justify repeating those cases or the device build. |
| Lorvex | Change the lock and append an exact upgrade qualification. `Vendor/HanlinSDK` is an ignored checkout, not a Gitlink. Preserve the accepted draft-repair receipt and its original UI-only guard; that historical path intentionally accepts 0dae and must not be relabeled as 32da. | Run `apps/apple/script/install_hanlin_sdk.py` then `--check`. No workflow change or UI rerun is needed for a lock/install/check-only upgrade: selected Composer/editor/UI/resource inputs are unchanged. The 1/1 UI/four frames remain 2e6a/0dae; Agent, presentation and device evidence retains its own older identities. |
| Anytype | Change the lock and its exact blob in `SOURCE_REFACTOR_MAP.json`'s existing `Tools/Hanlin/source.json` shared-source mapping. Its bootstrap reads the revision dynamically; no copied installer or static source revision needs editing. Append current source-retention/qualification evidence, preserving the baseline and admission checks. | Run `Tools/Hanlin/prepare_sdk.py --source …` then `--check`; this regenerates `.pinkha-source.json` from the actual checkout. Its 29 retained Python-controller inputs exclude SDK code and the lock, so the 68 retained + 1 requalified control proof needs no replay for this lock-only update. This is not native product acceptance. Coordinate with its owner before changing held or running source. |

Maktabah's normal build already derives the revision from the lock in its three preparation blocks. All three actual bootstraps load **Scripts/SDK/install.py from the requested immutable revision**, then check original sources/profile. An SDK upgrade requires no new per-host copy of that implementation. Actual canonical installation/check remains future verification, not an action claimed by this read-only audit.

Anytype's published aef/f206 source still uses d49 and includes its separately reviewed background/observer harness repair. The earlier fa078 app build/native preparation passed while its UI failed; later authority/logout did not run. Its owner's corrected native/UI qualification remains separate. Neither this source comparison nor retained Python controls erase that failure or create an overall Anytype PASS.

Exact current host policy file blobs/SHA-256 values, complete selected deltas, all 22 generator inputs, all 26 reused reconciler proof inputs and the final 32da identity extension are appended to the [machine receipt](../../docs/agent-sdk/evidence/consumer-upgrade-20261123/qualification.json). Historical receipts are unchanged.
