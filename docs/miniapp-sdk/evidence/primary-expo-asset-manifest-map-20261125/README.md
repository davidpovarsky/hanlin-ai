# Expo Asset manifest source-map correction

The original attempt8 native preparation stopped at the existing manifest audit after the original Expo Asset native product had been built. The analyzer now recognizes the actual embedded expo-asset plugin, but the audit's explicit plugin documentation map still enumerated five names. The strict equality check correctly rejected that mismatch.

This change adds exactly the missing expo-asset documentation row with its existing exact installed-version contract. The assertKeys implementation and the source-reader comparison call are byte-identical. Unknown or removed names still cause the same mismatch error; no validator, runtime, package pin, source artifact, test assertion or timeout changes.

The existing Scripts/Audit/audit-miniapp-sdk.mjs --write remains the producer of docs/miniapp-sdk/source-inventory.json and docs/miniapp-sdk/MANIFEST_REFERENCE.md. The native owner will regenerate these companions against the preserved actual prepared inputs, including the newly resolved original @types/react 19.3.1 package/lock. Generating an old-pin inventory on this sparse Oracle checkout would not describe that prepared source. The subsequent original --check and existing manifest-contract regression are owned by the native execution lane.

This commit is a source correction and read-only source comparison. No audit execution, compiler, native build, SDK packaging, fixture edit or test execution occurred in this lane. The actual failed attempt8 remains failed; the original producer's next observed result will be retained separately.
