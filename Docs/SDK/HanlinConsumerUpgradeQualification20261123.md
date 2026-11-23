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
