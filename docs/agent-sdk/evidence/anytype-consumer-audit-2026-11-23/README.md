# Anytype SDK06 canonical dependency audit

This is a read-only source and current-task audit. No Anytype source, existing worktree, native controller, workflow dispatch, original test result or acceptance state was changed.

## Current ownership and evidence

The verified published shared branch is codex/chatgpt-wave15-shared-20261121 at fd6f3357cd03da840c00b54a6248dd1a3553ba07. Exact other-owner branch heads and inspected source blobs are in receipt.json. Their SDK enumeration, quiescence and Hanlin observer work is active and remains theirs.

The SDK06 parent task's latest notes were older than its continuation child. The continuation is https://app.asana.com/0/0/1220769818981326; parent https://app.asana.com/0/0/1220542414733348 and HQ https://app.asana.com/0/0/1220541349302681 remain the coordination roots.

The current task reports two actual native/UI methods and the original 22 checks passing in 45096079315, while the overall live-runtime gate failed. It separately reports SDK23 methods/32 cases and acknowledgement7 still unexecuted because selector admission is unresolved. Run45107006017 stopped before enumeration during owned process quiescence and later cleanup/final-integrity checks. These outcomes are preserved, not replaced by the older pre-XCTest450432 outcome. This audit did not redownload or replay their original artifacts.

## Minimal canonical installation change

Current Tools/Hanlin/prepare_sdk.py extracts three original canonical Hanlin package trees at116cc6be. The real host consumes the original HanlinChatUI and HanlinPresentationKit; there is no basis for replacing the host UI.

Keep Dependencies/Hanlin and the existing host Swift sources. Add a canonical lock with the eight current product identities listed in receipt.json. Adapt the existing --source, --check and verify() preparation interface to the shared sparse installer with that explicit destination. Unify the three Xcode references and both affected module manifests (PinkhaAnyHanlin and PinkhaAnyNative) to the selected root package. The nine live workflow files with literal Hanlin pins should read the authoritative pin; historical executed-source copies remain immutable evidence.

The selected closure does not need Node, Python, Expo or NativeScript preparation. The actual installer receipt must establish that assertion for the final coherent pin before native integration, without creating a full runtime checkout.

## Preserve source guards

The old hashes() implementation includes every file recursively. A real Git checkout needs a source inventory that explicitly excludes Git internals and generated receipt metadata, while checking every selected original source against immutable Git blobs and the full selected directory closure. Canonical installer --check and generator --check must verify the two expected generated files; edited sources, deleted selected files and forged marker hashes must fail.

Keep a new receipt under the already managed .hanlin-sdk metadata directory. A strict source-record helper can select the new receipt only for a host that declares the new canonical lock; legacy frozen checkouts without that lock retain their original .pinkha-source.json contract. A malformed new installation must never fall back to the legacy proof.

The provider fixture verifier currently requires a materialized Tests file, which a selected source profile excludes. Its original fixture is byte-identical at116cc6be andb66aa5e0 (exact SHA and size in receipt.json). Verify that immutable Git object at the new pin and retain the fixture checksum, rather than copying all test trees or rerunning unchanged provider tests.

The unchanged source-retention gate protects both module manifests and Tools/Hanlin/source.json. After actual diff review, update only their exact replacement blobs/reasons in SOURCE_REFACTOR_MAP.json. Do not weaken the gate or rewrite prior evidence.

Original Products must keep their original source/tree/package-lock/Hanlin-snapshot identities. In particular,45087685319 Products cannot be relabeled as a build of the new Hanlin dependency. Native artifacts with a demonstrably unchanged closure can still be reused under their existing strict guard.

## Integration order

Wait for the coherent canonical Hanlin producer, including the already required HostAPI1.2 and activity extraction. Create a separate sparse consumer branch, coordinate the dependency/profile file lease with the existing Anytype owner, and publish a source-bound handoff in the current SDK06 continuation task. Keep selector, quiescence, mapping and native dispatch ownership with that owner.

No duplicate native1/UI1 replay is requested by this audit. Changed-SDK acceptance must be selected by impact after the actual new source closure is known. Native and visual acceptance of the proposed upgrade remain NOT_RUN.
