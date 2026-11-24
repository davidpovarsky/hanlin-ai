# Complete source examples in the installed SDK

The SDK includes complete editable projects for Expo and NativeScript. Read `examples/index.json` through `get_miniapp_sdk(resource: "examples/index.json")`, or use the selected engine's `examples` entries. Every listed path is relative to that installed SDK. The index contains only engines included in that SDK build.

| Engine | Start here | Complete application |
| --- | --- | --- |
| Expo | [Expo Hello World](../../examples/expo-hello-world/README.md): original Expo SwiftUI controls, React state and the `main` registration | [Departure Budget](../../examples/sdk-only-departure-budget/README.md): dates, forms, steppers, presets, checklist and calculation module |
| NativeScript | [NativeScript Hello World](../../examples/nativescript-hello-world/README.md): original Core page/button and the iOS metadata bridge | [Table Share](../../examples/sdk-only-table-share/README.md): editable amounts, exact integer-cent allocation, validation, switches and reset |

The linked directories are `examples/expo-hello-world/`, `examples/sdk-only-departure-budget/`, `examples/nativescript-hello-world/` and `examples/sdk-only-table-share/`. Each contains its source entry, `script.json`, `package.json`, `tsconfig.json`, `hanlin.authoring.json` and a README. Departure Budget also includes `App.tsx` and `model.ts`; Table Share includes `model.ts`. Repository maintainers edit these sources under `Scripts/MiniApps/Examples/`; SDK export retains their source bytes.

## Build a copy

Copy the entire chosen directory into a writable project, or provide its exact files to `write_miniapp`. Then follow [the shared authoring workflow](AUTHORING_WORKFLOW.md): read the installed engine/versions, validate the source, build the archive and import it. The public CLI uses that same implementation. The Expo root name is `main`; NativeScript authoring emits the canonical `nativescript/app/bundle.mjs` entry automatically.

The examples do not require another dependency installation. The original compiler, declarations and bundler come from the installed SDK. Their package declarations preserve the versions used when the source was authored; when adapting a copy for a different SDK, align dependency declarations with its `selectedEngine.packageVersions` and fix any current compiler diagnostics. The builder records the actual prepared host contract. An SDK update does not silently rewrite these source projects or their prior proof.

Only source/configuration/documentation/assets are exported. Installed `node_modules`, repository metadata, and the known `.hanlin-build`, `.hanlin-authoring` and `.metro-cache` output roots remain outside the example source inventory. Ordinary authored resources, including ZIP data and files under `build` or `dist`, are retained. The SDK manifest hashes every retained example file, and the same example inclusion policy contributes to `inputSHA256`.

## Evidence boundaries

Departure Budget and Table Share retain the exact independent SDK-only author's sources. Their portable validation and build evidence is preserved in the repository; native import/render/event acceptance is recorded separately. The Hello World projects have their own original-SDK validation/build receipt. None of these source/build results is presented as a physical-device or native UI pass.

ScriptWidget is documented separately through [original widget authoring](SCRIPTWIDGET_AUTHORING.md), [native presentations](SCRIPTWIDGET_AUTHORING.md#native-presentations-and-region-programs) and [original Controls](SCRIPTWIDGET_CONTROLS.md). These examples do not introduce a standalone ScriptWidget application engine or resume legacy Scripting development.
