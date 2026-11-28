# Studio Files provider query repair

The original source-folder import failed while the system Files picker visibly showed
On My iPad. The contemporaneous MiniApps-only accessibility tree contained the
underlying Studio screen but omitted the remote sidebar. The preserved screenshot
SHA256 is 410e63a3dbf6f593394bd2e301561fe2efd26fc361d43d4c249ddb5b4e8bae4b.
This is evidence from the failed original run, not evidence of a successful import.

The existing companion already has a com.apple.DocumentsApp query, and the
repository's original NativeScript import path searches both its host and that
Files application. This repair uses those same two query identities for the
already-presented picker. It selects an exact On My iPad cell or static text only
when it exists, is enabled and is hittable, records the query owner and observed
PID, then keeps all folder and confirmation queries on that owner.

Each control retains the original single 12-second deadline and the global
deadline bound. The test does not launch or activate Files, infer a private
service process, use coordinates, or modify product/input state. All 28 selectors,
their original assertions, source-import confirmation, and unrelated Files/export
routes are preserved. Removing the added helpers and reversing the import-helper
substitution recovers the entire previous source byte for byte.

Both the parent and the independent reviewer approved this source for the original
native retry. No native or portable behavioral test was run for this change.
Actual query ownership and successful folder import remain required native proof.
