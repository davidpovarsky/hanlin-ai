# User-provided Scripting acceptance projects

This directory records the five real Scripting projects supplied on 2026-08-25.
They are primary compatibility applications, not editable Hanlin fixtures.

`OriginalArchives/` contains byte-for-byte copies of the attachments. The
ASCII storage names avoid archive-name encoding ambiguity on Windows; the
original attachment names and SHA-256 digests are retained in `inventory.json`.
Run `node Scripts/ScriptingReference/verify-user-provided-projects.mjs` to prove
that the stored bytes are unchanged.

Testing must extract archives into a temporary or ignored build directory.
Never edit these archives or extracted originals. If a corrected runtime fixture
is ever required, place it under a separate `Derived/` directory, record the
parent digest, and list every source change. No derived fixtures currently
exist.

`compatibility-results.json` deliberately separates source-project diagnostics
from Hanlin compatibility failures. A declaration-only API does not count as
runtime support, and an unexercised native service is not marked as passed.

