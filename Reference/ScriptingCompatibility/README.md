# Authorized Scripting compatibility baseline

This directory is the portable, versioned compatibility source authorized by
the user for direct use in Hanlin.

- `Original/` contains byte-for-byte copies selected from the authorized
  workspace. These files are immutable within a baseline.
- `Generated/` contains deterministic indexes and compatibility obligations.
- `Overlays/` is reserved for separately owned Hanlin additions. It never
  mutates the originals.
- `BASELINE.json` identifies the source snapshot and compiler provenance.
- `SHA256SUMS.json` records every imported file and the aggregate identity.
- `IMPORT_REPORT.md` records selection, duplicates, exclusions, and drift.

Run the source-independent verification from the repository root:

```powershell
node .\Scripts\ScriptingReference\verify-scripting-reference.mjs
node .\Scripts\ScriptingReference\build-scripting-inventory.mjs --check
```

The absolute Windows source path in `BASELINE.json` is provenance metadata
only. Production code must use repository-relative or packaged resource paths.
The imported declarations describe compile-time compatibility; they do not
claim that Hanlin implements the corresponding runtime behavior.

## Git byte-preservation policy

The repository-level `.gitattributes` marks only
`Reference/ScriptingCompatibility/**` as `-text -whitespace`. Git therefore
stores and checks out every baseline byte without CRLF/LF normalization on
Windows and macOS, while `git diff --check` accepts whitespace already present
in the immutable authorized source. Do not replace this with a repository-wide
policy. After staging or a clean checkout, run the verifier above against the
Git-materialized files before accepting a baseline.
