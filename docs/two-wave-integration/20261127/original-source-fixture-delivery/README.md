# Build-bound original source fixtures

The original parity tests and FINAL12 source audit read compiler-host paths through #filePath. The failed original app-hosted run could not read the tracked preservation contract and tool inventory at those paths. Both files exist at the executed Git source; the evidence does not establish a repository deletion.

The canonical project generator now adds one build phase to AI_HLYTests, after its resource phase. It declares the exact 23 source inputs and copies their current raw bytes into OriginalSourceFixtures.bundle inside that unit-test product on every build. The immutable preservation contract and reference are copied unchanged; expected hashes are never regenerated from the sources under test. A test-only Foundation helper resolves that actual bundle. Only the two parity root initializers change; all original assertions remain. FINAL12 receives a separate tiny root-binding patch applied by its existing integration owner.

The project comparison has exactly one added phase and one unit-target phase-list insertion. Every other parsed graph value is identical. The old generator is recovered exactly by removing the new helper, constant and call. The complete parity source is recovered by restoring its two root initializers; all 364 original assertion/requirement lines in the file remain identical. No application, extension, entitlement or runtime API changes. The accepted 392-input SDK source set has no changed-path intersection.

Nine portable controls are qualified: eight passed in the retained first run; the sole failing new assertion expected decoded PBX newlines, while the existing parser retains their quoted escape. Only that assertion was corrected, and that one method passed on retry. The other eight method/helper ASTs are unchanged; no fresh full-nine run is claimed. The actual producer then copied all 23 files (574,715 bytes), each equal to current checkout and Git HEAD bytes. The produced manifest is retained.

Native Xcode build, sandboxed build-phase execution and runtime loading from the installed XCTest bundle remain NOT_RUN. The original parity and FINAL12 native gates are still required.
