# Existing MiniApp SDK source authority

This is the SDK-01 / INT-01 audit of the existing NativeScript and Expo packages,
not another SDK or runtime. Status: **IN_PROGRESS**. Public syntax and source
wiring do not establish execution through every extension or a signed device.

- [SDK source inventory](source-inventory.json): public exports, Objective-C
  declarations, version/lock records, manifest families and exact source hashes.
- [Extension reachability](extension-reachability.md): four real extensions ×
  two engines × five canonical runtimes, plus foreground/Live Activity/Intent/
  Shortcuts paths. Its [JSON](extension-reachability.json) links exact file/line/
  hash references and reads SDK version authority from the source inventory.
- Existing authoring guides remain [Expo](../hanlin-expo-runtime.md),
  [NativeScript](../hanlin-nativescript-guide.md) and
  [HanlinExpoUI](../../Packages/HanlinExpoUI/README.md).

## Version boundaries observed in source

NativeScript Core/iOS are pinned to9.1.0, with the separately embedded SwiftUI
provider contract4.0.2. Expo tooling locks Expo58.0.0, ExpoUI58.0.3, React19.3.0,
RN0.88.0 and Worklets0.13.1. `@hanlin/expo-ui` package version1.0.0 differs from
its generated bridge version3.0.0. Its peer dependencies still reference preview
Expo/React/RN versions and require SDK-04 reconciliation, rather than an implicit
runtime upgrade. The optional native-api facade1.0.0 re-exports upstream9.1.2.
These are source/lock contracts; installed Host/Hermes/metadata and signed binary
observations remain separate obligations.

The `@typescript/typescript6` npm package pinned as6.0.2 reports compiler6.0.3
internally. The audit records both identities and the actual compiler module
hash. It does not rename the package or claim the source inventory is a strict
TypeScript/Metro/native SDK acceptance run.

The `script.json` decoder preserves unknown metadata; this does not make an
unknown entrypoint executable. Its contract differs from the canonical compiled
app's `HanlinAppManifest.schema.json`. NS/Expo prepared `package.json` versions,
plugins, analyzer rules and archive validation are additional contracts. SDK-02
still owns the complete authored schema/validator/examples, and SDK-03/04 own
per-public-API typing and native execution evidence.

## Drift checks

After the repository's normal Expo tooling installation:

```powershell
node Scripts/Audit/audit-miniapp-sdk.mjs --check
py -3 Scripts/Audit/audit_miniapp_reachability.py --check
```

An audit-only parser can be supplied without installing the entire Expo tree:

```powershell
npm install --prefix build/sdk-audit-tools --ignore-scripts --no-audit --no-fund 'typescript@npm:@typescript/typescript6@6.0.2'
node Scripts/Audit/audit-miniapp-sdk.mjs --check --typescript-module build/sdk-audit-tools/node_modules/typescript/lib/typescript.js
```

Use `--write` on the SDK audit only after reviewing changes; the Python audit
regenerates without `--check`. A base commit plus any uncommitted audit sources
is explicitly distinguished from the exact file hashes. Unrelated later commits
do not invalidate an unchanged inventory solely because HEAD advanced. Source
changes or a new Share inbox caller require re-audit. No new automatic workflow
triggers, native rebuild, package installation in a MiniApp, cloud upload or
runtime execution is performed by either check.

Current gaps include the unconsumed Share inbox/temporary attachment URLs,
Expo non-widget exposure/intent rejection, NS single-active-session arbitration,
missing generic NS TS/Shell/structured receipts, legacy Expo unknown-kind→JSC
fallback, differing generic Shell source semantics and unpublished SystemServicesBroker bindings. The recorded17 system
method declarations and permissive capability metadata are not iOS availability
or OS permission proof. INT-02…07 and SDK-02…08 remain open.
