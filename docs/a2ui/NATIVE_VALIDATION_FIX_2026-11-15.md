# Native fixture-load failure: v1 Unicode component identifiers

The actual [run43662884686](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43662884686)
compiled source `c40e617b` against the exact official SDK with both gates enabled.
All25 real cases executed:8 portable passed and17 SDK cases failed during
nominal fixture loading. This replaces the previous NOT_RUN status **for that
tested revision**, not the corrected candidate. New-source execution is pending.
Read [native-run-43662884686.json](evidence/native-run-43662884686.json) for the
actual per-case log outcomes and advertised artifact identity. The111MB ZIP was
not duplicated locally; its digest is the GitHub API value, not a local rehash.

## Cause and correction

Our nominal fixtures used component ID/reference `submit-label`. The pinned
`PayloadValidator.extractAndValidateComponentEnvelope` enforces UAX #31 on v1
component IDs and reports `invalid_identifier` for this spelling. The public
`UnicodeIdentifierValidator` rejects the hyphen while accepting `submitLabel`.
This semantic check is stronger than merely observing that ComponentId's JSON
schema declares a string. It applies independently of the streaming graph flags.

The exact source is at
[PayloadValidator.swift](https://github.com/a2ui-project/a2ui/blob/3ed9601862ecc78027e20ac80ad8b1b98a5d9079/swift/core/Sources/A2UICore/Validation/PayloadValidator.swift)
and [UnicodeIdentifierValidator.swift](https://github.com/a2ui-project/a2ui/blob/3ed9601862ecc78027e20ac80ad8b1b98a5d9079/swift/core/Sources/A2UICore/Validation/UnicodeIdentifierValidator.swift).
The actual failing run retained only our generic rejection, so its *underlying*
SDK code/path was not observed there. The identified fixture violation is
established by the pinned validator source and its portable execution; the
corrected full-SDK25-case run must still confirm the entire behavior.

Positive form/RTL/update fixtures and their Button child references now use
`submitLabel`, including the stable-ID assertion. Negative Button/function
fixtures reference this valid child so they fail for the intended bad type or
unauthorized function. The original `submit-label` is deliberately retained as
a fourth negative component case; its SDK rejection must include
`invalid_identifier`. All original expectations/cases remain; no validation,
unknown-element, ownership, RPC, lifecycle or gate policy was loosened. There
is no automatic renaming of incoming IDs or persisted-envelope change.

## Diagnostics and evidence

Rejection now retains the SDK error type and up to8 structured code/path pairs
(96/256-character field caps). SDK messages and payload values are not copied.
These are diagnostic metadata only: failure routing still depends exclusively
on the validated Frame and current SDK-owned surface. Raw ingress failures have
no SDK diagnostics. A future fixture/schema failure can identify its original
code/path instead of stopping at a generic sdkValidation label.

`validate_fixture_identifiers.swift` compiles with the **unchanged** pinned
upstream validator snapshot in `evidence/UnicodeIdentifierValidator.pinned.swift`
(SHA256 `33eb878b41c8d6d5fd5c36fac1766fe17701935483f659e0eaadbf18a4a2af7d`).
This Foundation-only source lookup/probe is not another engine or a substitute
for SDK tests. Before correction,5 of23 positive-fixture ID/reference entries
failed; after correction all23 pass. Both outputs are retained as
`fixture-identifiers-before.json` and `fixture-identifiers-after.json`.

Native proof remains the same25 actual Swift Testing cases with the exact
root/transitive graph, real source bytes and official renderer/generator.
Tomer owns the existing verifier and its next run. The corrected candidate is
not SDK_PASS, integrated, device-verified or ready for task completion merely
because portable checks pass.
