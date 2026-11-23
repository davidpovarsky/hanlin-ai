# Persisted scripting registry identity boundary — 23 November 2026

The original shared store accepted a decoded catalog whose dictionary key differed from the entry's installed package identity. Two distinct, valid map keys could therefore produce two original snapshots with the same installed ID. The repair rejects that selected registry through the existing corruptRegistry error before snapshots are exposed.

## Reproduction and scope

The Oracle reproduction compiles the complete original HanlinPlatformContracts and HanlinScriptContracts modules, the exact original store initialization, registry decoding, snapshot creation and supporting Foundation declarations, and the exact original application dictionary expression. It reads actual catalog.json/catalog.backup.json fixture files. No alternate store, permission engine or hashing implementation is provided.

Before the repair, duplicating a record under a second valid key produced two fixture-install snapshots. Evaluating the unchanged fallback expression then terminated the Swift child with SIGTRAP, exit -5. An undecodable primary selecting a similarly corrupt backup reproduced the same failure. A single mismatched entry was also incorrectly admitted.

The application expression runs only when refreshExtensionSnapshot has a prior snapshot and a nonempty failedWidgetPackageIDs set. This is the previous-widget preservation branch, not the later publishWidgetTemplates write catch. The reproduction does not execute WidgetKit or prove that a normal package/tool/import can create corrupt stored data. No connection to the reported calendar crash is inferred.

## Minimal shared repair

RegistryEntry now owns one private key/identity predicate. loadRegistry applies it after the existing schema check and throws corruptRegistry on mismatch. verifyTransferRegistry reuses the same predicate after its existing typed key validation. Its complete body is byte-identical after reversing that predicate substitution, preserving its error types, inventory ordering and artifact validation.

The change preserves selection semantics: a decodable primary remains selected; semantic identity failure does not silently discard it for an older backup. An unreadable/undecodable primary can still select a valid backup. Unsupported schema errors remain unchanged. No registry is rewritten, deleted, migrated or automatically repaired.

## Actual validation

Six before cases and six after cases ran on Oracle with Swift6.4.3, aarch64 Linux. The repaired duplicate primary, mismatched primary and corrupt selected backup all throw the existing corruptRegistry error. Valid primary precedence, valid backup fallback and unsupported schema behavior remain intact. Every preserved fixture's primary and backup SHA256 matches across the before/after executions; unchanged-byte checks passed.

This is a production boundary proof, not complete Apple store compilation. CryptoKit artifact hashing, OSLog, product transfer execution, the live application and WidgetKit are outside this portable slice. Their implementations were not stubbed.

Three focused native Swift Testing methods (four parameterized cases) were added to the existing original store suite. They cover cold initialization, restoration after on-disk corruption while retaining the last valid in-memory snapshot, backup validation, and valid selection/unchanged bytes. Syntax parse passed; native execution remains NOT_RUN because compatible Apple runner admission is unavailable. No existing test suite was replayed and no CI was dispatched.

Machine-readable hashes, exact scope and the original crash logs are in HanlinScriptRegistryBoundary20261123.json and registry-identity-20261123/. The reproducible command is Scripts/SDK/check_registry_identity_boundary.py --output <directory> --expect fixed. The same command with the original source and --expect vulnerable preserves the pre-fix failure.

## Ownership

Only the canonical store, its original test file, the scoped reproduction script and these receipts changed. ScriptUI reconciliation and permission-authority fixes remain with their respective owners. This private persistence change introduces no second implementation and reaches all applications that select the shared HanlinScriptStore product.
