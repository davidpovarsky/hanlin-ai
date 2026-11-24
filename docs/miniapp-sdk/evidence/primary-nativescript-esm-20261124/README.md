# NativeScript emitted module format correction

## Actual native failure

Attempt 7 installed the SDK-only Table Share package, but the original NativeScript runtime reported Cannot instantiate module followed by SyntaxError: Unexpected token {. The retained installed root bundle.mjs imports modules/index.js; that file starts with a named ESM import. The exact six installed application files are retained under proof/actual-installed-table-share.

The installed original runtime package is @nativescript/ios 9.1.1. Official upstream v9.1.1 commit 95b52affd694bb0d933b3b81820c14ddc5e47341 classifies .mjs as ESM in ModuleInternal.mm, and wraps other script files as CommonJS. The source URL, full source SHA-256, and relevant lines are retained in proof/receipt.json. package.json type:module does not change this original loader classification.

## Production change

The authoring compiler first plans module paths from its actual emitted syntax. It assigns .mjs to emitted ESM, while authored CommonJS .js and explicit .cjs retain their module mode. The final compiler emit uses that same mapping for the entry, local imports, re-exports, dynamic imports, source-map filename, and sourceMappingURL. Original editable sources and source-map sourcesContent remain intact. Existing canonical SDK module resolution and copied original npm package bytes are unchanged.

The preliminary blanket .js-to-.mjs proposal was revised before execution to preserve the supported CommonJS boundary. The emitted-syntax plan avoids relying on package type metadata or private compiler flags.

## Focused actual execution

The primary Mac ran the original NativeScript TypeScript 5.9.3 compiler (SHA-256 3ae902c92cc44dace175c0e69e13a4b0899f6983c6121d76b9ab8dd5795e7675) with Node 24.5.0. Execution used an isolated source copy; the app checkout stayed at fd81d602d3b25f09162a659e1e0cf0582e91a93a.

Baseline finished 2026-11-24 23:40:59.476 UTC in 1.954 seconds: one ESM graph failure and one authored CommonJS pass, zero skips. The raw assertion shows actual import ./modules/index.js versus expected ./modules/index.mjs.

Candidate finished 2026-11-24 23:41:11.621 UTC in 12.143 seconds: five passes, zero failures, zero skips:

- Native ESM entry and static/export/dynamic local graph, with original editable sources and correct source maps.
- Authored CommonJS JavaScript, its execution and source maps.
- The real CLI archive and retained-source revalidation.
- Original npm runtime package body preservation.
- Canonical SDK dependency identity, extra project dependencies, and noncanonical project aliases.

proof/state.json records exact source/test/compiler/CLI identities and both actual commands. The candidate module is fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9. proof/receipt.json binds all 12 transferred raw members. No original native library was patched or replaced.

## Acceptance still required

This proof covers authoring output and source retention, not native rendering. The normal embedded Host/SDK producer and both app builds must receive the correction, followed by the original SDK-only NativeScript runtime test and full unchanged 25 MiniApps plus 27 AI scope. Expo bootstrap, Modular Search import timing, and Xcode result finalization have separate evidence and owners.
