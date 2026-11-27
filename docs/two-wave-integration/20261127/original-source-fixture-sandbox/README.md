# Sandboxed original source-fixture outputs

Source commit: fd445cdb49ea23bf0a9e519bf8102f41842b262f
Base: fe0001ac868339d0825d1cc3d07f8383341d163d

## Observed failure

The original system-surfaces run 46033781797 and independent Widget-state run 46033434171 reached the AI_HLYTests fixture-copy phase on f57dfcc2. The original MiniApps build passed, but Xcode denied creation of OriginalSourceFixtures.bundle/AI_HLY. The canonical phase declared only the bundle root. No UI acceptance case ran after the failed AI build.

The failing producer, input list, project and generator bytes were identical on the correction's fe0001ac base. The phase is always run, and the original producer removes its own previous bundle before copying the current checkout bytes. Cached output therefore does not remove the requirement to create the nested paths.

## Change

The canonical project generator now uses the original producer's strict input parser to declare exactly the filesystem output it creates: the owned bundle and 15 nested directories, 23 original copied files, and manifest.json. There are 40 distinct output paths, all within the same test-only bundle.

The producer, 23 source inputs, immutable source-preservation contract, test bundle identity, target membership, script command, always-run setting, user-script sandbox settings, schemes, runtime code and native acceptance assertions are unchanged. Only the generated phase's outputPaths differ in the complete parsed project.

Exactly one existing portable metadata expectation necessarily changes from a single-element output array to checking its original literal root at outputPaths[0]. A new independent control compares the complete declared set with the actual filesystem produced by the unchanged copier. It also checks duplicates,24 regular files, the previously denied directory, manifest.json and inherited sandboxing in both configurations.

## Validation

The original focused unittest-discovery command passed all 10 methods on final R2: 9 existing methods and 1 additional physical-tree control, 0 failures, 0 skips, 0.382s runner time. The prior R1 attempt is retained separately. Its 5 set-comparison loops were removed during review; they are not claimed as meaningful negative acceptance evidence.

The generator's complete original bytes are recovered by removing the new helper/import and restoring the old output expression. The complete original project text is recovered by restoring only outputPaths. Eight original test method ASTs are unchanged; the ninth has the necessary metadata-expectation correction described above. Original native test bodies, selectors, assertions and deadlines are untouched.

The actual accepted SDK manifest has 396 source inputs. These 3 changed paths have zero direct intersection. Generated project-reference metadata still needs truthful qualification by its original auditor after the PBX change; this direct comparison is not a claim of a new producer or native run.

**Native sandbox acceptance on the corrected declarations has not run.** The original app build and native gates remain required.

## References

Apple documents declared inputs and outputs in [Running custom scripts during a build](https://developer.apple.com/documentation/xcode/running-custom-scripts-during-a-build) and the ENABLE_USER_SCRIPT_SANDBOXING guard in [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference). The retained actual Xcode failure is the direct basis for the specific missing-child correction.

Raw patch and log gzip files preserve the original bytes; manifest.json records both compressed and uncompressed hashes. Full original native failure logs remain in the authorized evidence handoff.

The accepted generated reachability record still points to the prior PBX SHA256 3563bca7…; the corrected project is 5b70df51…. Its original auditor must refresh that reference on the integration source. The source-inventory JSON contains no direct PBX path reference. The final SDK fingerprint must reflect any resulting generated-document update.
