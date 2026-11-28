# Native widget compatibility correction

Source: 16b4af4490d96c41cb76ed185a1e6d4e828899e7, based on the actual native candidate 6975e769e82a7803853180cd6aec6a26fe412f9f.

The original iOS package run completed with exactly 57 methods and 78 invocations: 76 passed, two failed, zero skipped. The four methods that enumeration incorrectly marked enabled did not execute and receive no credit. The raw reconciliation path and hashes are in receipt.json.

## Changes

The existing fixture producer now reads the already pinned Expo package versions. The native widget contract uses @expo/ui 58.0.29; the Expo SDK pin is separately 58.0.26. No pins or admission checks changed. Five Expo archives change only their package.json, identically in the three original fixture locations. The three ScriptWidget/legacy archives remain identical. The new Matrix sample is appended after the seven historical samples, restoring the original positional subjects used by the unchanged compiler/action tests.

The V1 shadow now projects the exact original snapshot, identity and collection fields. Its prior inclusion of nativePresentations made the frozen reader's decode/re-encode hash differ, even when that new field was empty. New intent/translation metadata had the same issue when populated. Current V2 data, atomic commit/revision logic and the original hash verifier are retained. The original failing test methods and frozen fixture files are byte-identical.

## Verification

Original widget JavaScript tests: eight original plus one added exact-pin regression passed. The new pin regression rejects the original 58.0.3 producer. The original interactive suite passed all ten tests against both checked-in bundles. Initial positional-fixture failures and one missing sparse-input attempt are retained as exact log envelopes.

One new original-package Swift test exercises populated new metadata through the real frozen reader, exact V2 readback and tamper rejection. Its addition makes the required package inventory 58 methods / 79 invocations. **Corrected Apple/native execution is pending.**

Independent built-in agent /root/wave1_chat_sdk approved the immutable source diff after checking the frozen field sets, all unchanged original test/validator files and all archive members. Its exact receipt is retained as independent-source-review.json. The reviewer did not run duplicate tests.

The store source is an input to the canonical SDK/Host fingerprint. Package-only native checks cannot establish refreshed Host provenance. The native owner will run the original affected route and qualify the final integrated source.

See fixture-byte-proof.json, preserved-original-contracts.json and receipt.json for byte hashes and exact limits.
