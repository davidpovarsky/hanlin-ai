# Per-generation rollback metadata — 2026-11-24

## Result

The original store selected a historical artifact generation during rollback but retained the newest catalog manifest and entrypoints. A V1 Expo artifact could therefore be published with V2 NativeScript paths/runtime metadata. The original lifecycle fixture kept identical descriptors and nil manifests across versions, hiding this defect.

Before any production edit, the strengthened existing lifecycle method failed with four exact mismatches: wrong manifest and descriptors both immediately after rollback and after cold restore. After the fix, that one method passed, including reinstall and old-format recovery branches. The raw red/green logs, exact projected-source diffs, original input hashes and original Apple dependency revisions are retained.

This is PORTABLE_PROJECTED_SOURCE_PASS, not an unmodified Apple-module or application PASS. The exact native filter remains HanlinAtomicScriptStoreTests/lifecycle. No other test method was executed.

## Production change and compatibility

Each new generation now stores its full entrypoint array and optional manifest alongside the existing identity/digests. Rollback restores those values together. Optional fields preserve decoding of the old four-field generation format; a present entrypoint array distinguishes a complete snapshot with an intentionally nil manifest.

Before update or rollback leaves an old active generation, its exact matching current registry entry is saved into that generation. An inactive old generation may recover from the retained registry backup only when its generation, package, version, source and artifact identities all match. Grants and enabled state remain properties of the current installation.

If no authoritative descriptor history survives, generationMetadataUnavailable is returned before registry or target-metadata mutation. Artifact files and source/script.json remain intact. The author manifest alone does not contain the analyzer's complete installed descriptors; silently mixing it with current descriptors would recreate the bug. Retained-source reimport through the existing host/analyzer layer is the recovery route. No store-to-compiler dependency or permission gate was added.

## Focused proof

The existing lifecycle method now checks distinct modern V1/V2 contract metadata, rollback artifact bytes and metadata, disabled cold restoration, uninstall/reinstall, old active-format backfill after registry-backup replacement, old inactive-format recovery from an exact backup, redo of the departing generation, and unchanged primary/backup/catalog/metadata bytes when history is missing.

The test uses the existing synthetic, hash-verified store artifacts. It does not claim original Expo/NativeScript compilation, engine rendering, or application UI execution. The full atomic-store test file compiles in the projection; only its lifecycle method runs.

The Linux projection uses actual original source files and Apple's real cached SwiftCrypto revision 3280a5f72874d2f73bf25551bbb64f524c76d834, with SwiftASN1 revision 97fd57437fc94cfa6b62f2b8f84c50f433534e17. The only platform adaptations are CryptoKit imports bound to Crypto and conditional OSLog statements. Store decisions, hashing, file operations and test assertions are preserved. No dependency was fetched or installed.

## Reproduction

    python3 docs/miniapp-sdk/evidence/rollback-metadata-20261124/run_portable_lifecycle.py --output <evidence-output> --build-root <isolated-build-root> --expect green

The recorded run uses Swift 6.4.3 on aarch64 Linux. The red test-only patch applies to the recorded base; the final production/test delta is production-and-test.diff. receipt.json records exact scopes and hashes.

## SDK07 boundary

The discovered prior native registry receipt ran three registry-identity methods, not lifecycle. It was not reused as a lifecycle PASS. Legacy grant persistence/revocation tests do not prove iOS authorization changes: existing host tests explicitly keep network authorization allowed after a legacy metadata grant is removed. Actual application lifecycle and OS permission-revocation evidence remain separate requirements; no blanket SDK07 completion is claimed here.
