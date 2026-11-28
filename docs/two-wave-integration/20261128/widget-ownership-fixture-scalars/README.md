# Scalar observations in the ownership test fixture

The native 5baa01fb attempt passed the two retained import regressions and five ownership controls. Three controls using the shared Widget script failed with "TypeError: Cannot convert primitive to NSDictionary".

The shared script passed a Boolean and a number to the original setJSON JSExport, which requires a dictionary. The shipping runtime already exposes typed set(String, Any), forwarding through the original session identity check to the existing transaction with JSON fragments and storage budgets. The original typed-storage regression uses that route for numbers and Booleans.

This correction changes only those two fixture call names from setJSON to set. It preserves the actual missing dynamic-import result, actual JSON-file count, exact false/9 assertions, all eight method bodies, the two retained archive oracles, renderer, native APIs, guards and SDK inputs. The full-file inverse replaces those two names and recovers the previous source byte-for-byte.

## Qualification

The original attempt remains **7 PASS / 3 FAIL**, with all ten starts and terminals retained. The failure packet is retained-import-5baa01fb-seven-pass-three-runtime-errors; hashes are recorded in qualification.json and the independent review.

The complete new fixture API audit is included. This seal is source-only: no Swift or native tests were rerun in this lane, and the corrected three controls still require actual native acceptance. The exact ten-method selection and existing limits are unchanged.

source.patch.gz is the exact Git patch compressed losslessly. The independent root review is retained unchanged.
