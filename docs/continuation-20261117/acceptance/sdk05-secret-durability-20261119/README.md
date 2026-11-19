# SDK05 original-store durability correction — 2026-11-19

The original Runtime and MCP Keychain services now update existing values without deleting them first. Environment edits stage credentials, commit their references to the original registry, and remove old references only after a successful commit. Failed MCP primary replacement may leave the newer verified backup durable; cleanup therefore reads both generations and retains staged credentials whenever references cannot be read. Directory permission denial is not treated as a missing registry. Stale environment edits fail without replacing newer descriptor metadata.

The original SwiftData conversation adapter gains a real disk-backed reopen test preserving canonical bytes, cancelled history, Unicode, unsent legacy drafts, Canvas and presentation data. Unknown future formats must leave the durable original record unchanged. Nineteen stdout changes remove prompt, memory, query, provider URL and arbitrary error values while retaining metadata diagnostics; all non-print lines in those two files are unchanged.

## Validation and limits

Eight changed Swift files parse on the Windows toolchain. This is syntax validation, not an Apple typecheck or native acceptance. The CI plan selects 23 expanded native cases: the original session-owner suite (14), eight new Keychain/durability cases, and the original scoped-environment precedence control. Native results are pending. The tests use the actual original Keychain services, actual files, atomic backup commits and a real SwiftData store; no live credential values are included.

This correction does not establish account-switch fencing, complete credential erasure, signed cross-process App Groups, CloudKit migration or physical-device acceptance. Those SDK05 gates remain open.
