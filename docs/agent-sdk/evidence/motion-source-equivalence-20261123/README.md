# Frozen original Motion B source equivalence to the integrated SDK

Status: selected-source/output equivalence qualified; no native acceptance is claimed by this review.

## Scope

The sole active original B run [45278413617](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45278413617) is frozen at `d8e4327f6d4097ac5a206f2acf2bf654a7ee9c13`. Its origin remains that commit. Central integration `4cfa52348e80cf635caf04c541fd84ee1ddb50bd` also contains host target/link ownership, compact ChatView padding and MiniApps language metadata repairs.

The existing portable `prepare_motion_ui.py` was run once on the central frozen worktree. It installs the actual selected `HanlinChatUI` SDK product through the existing pinned-source installer. No Xcode build, simulator or native test ran. Both complete profile receipts and the exact source comparison are preserved here.

## Exact unchanged selected inputs

All364 selected SDK source/resource records are byte-identical, including the retained-disclosure accessibility correction. Both generated files, `Package.swift` and `unified-package-manifest.json`, are byte-identical. The native fixture project specification, selected product, absence of runtime binary targets, selected `chat-motion-product` workflow job, and top-level workflow input prefix are also identical.

Nine of10 broadly recorded fixture files are byte-identical, including the original app, original A/B/C/D test bodies, runner, preparation, native recorder and actual macro helper. The tenth file and three broad graph files are different; those differences are retained explicitly rather than described as equal.

## Changed provenance inputs and actual dependency boundary

The only `.github/workflows/testflight.yml` change renames the unselected release signing target check from `AI_Hanlin` to `HanlinApp`. The original Motion macro helper reads that file solely to find and record existing lines containing its established headless package flags. The flags and every matching line (including line numbers) are identical; reversing the one signing-target replacement restores the entire prior file. This is a semantic consumer qualification, not a claim that the full file hashes match.

The original app project, project-graph helper and SDK generator record changes to the real app target identity and shared-image ownership. Their selected-product output is independently regenerated: the two actual Motion SDK manifests, all selected sources/resources and fixture project remain identical. No app host target or native runtime binary is selected by this component profile.

The original B native artifact must still supply its actual build, macro/dependency/source-verification and test result. A result from the frozen source can only be attributed to its original run and, after that result is known, qualified for these unchanged selected Motion inputs. Full app, companion, renderer/engine/scroll and physical-device acceptance remain separate obligations. A+C remain pending; this review dispatches nothing.
