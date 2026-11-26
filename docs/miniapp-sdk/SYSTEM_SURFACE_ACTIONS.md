# System surfaces and package actions

The installed SDK exports the declaration-only package `@hanlin/system-surfaces` alongside the original Expo, NativeScript and ScriptWidget declarations. Read `get_miniapp_sdk(engine)` and its `selectedEngine.systemSurfaces.typesPath` and `docsPath`. The staged file is copied from `Scripts/MiniApps/native-presentations.d.ts`; it contains Hanlin package metadata, not a replacement runtime implementation.

```ts
import type { WidgetAction, WidgetProgramDefinition } from '@hanlin/system-surfaces';

const run: WidgetAction = {
  id: 'run-all',
  kind: 'hostAction',
  hostAction: {
    entrypointID: 'surface-intent',
    actionName: 'surface.run',
    parameters: { surface: 'widget', challenge: 'authored-input' }
  }
};

const widget: WidgetProgramDefinition = {
  abiVersion: 1,
  sourceFormat: 'jsx',
  actions: [run],
  families: ['systemMedium']
};
```

These values belong in `script.json` as `hanlinWidget`. The rendered button names `run-all` using the original renderer's action-binding API. The same package must declare one `appIntent` entrypoint named `surface-intent` and one registered `actions[].id` named `surface.run`. The registered handler must resolve to that entrypoint's prepared source. An optional `exportedSymbol` must match the exact action name. Package registration, the authoring validator and the native compiler enforce this relationship; declaring a name alone does not install a JavaScript handler.

## Execution and results

A `hostAction` continues the declared action in the containing Expo or NativeScript foreground application. The button's App Intent requests foreground execution, validates the current installed widget/program and target action, durably enqueues one invocation, and wakes the application's existing invocation executor after enqueueing. The application checks the origin again before invoking the real registered JavaScript handler. This post-enqueue wake also covers application activation that occurred before the queue write.

The handler uses its original typed Host facade: `hostServices` from `@hanlin/expo-ui`, or `createHostServices()` from `@hanlin/host-services`. Its runtime API can invoke the available Node, TypeScript, Python, JavaScriptCore and Shell engines. Native package/session ownership and the runtime's actual availability still apply. The extension does not start a separate copy of those engines.

The queue retains the invocation ID, status, actual returned action value and error. Acceptance into the queue is not a successful runtime result. A handler that needs full runtime evidence should return or persist the actual `executeRuntime` result, including its output/error and execution identity. Per-surface native tests are required to establish that an OS tap reached that handler; source metadata and a direct unit invocation do not establish this.

## Original local actions remain available

| Declaration or surface | Execution |
| --- | --- |
| `function`, `setValue`, `reload` | Existing ScriptWidget/original renderer action path |
| `expoCallback` | Original Expo Widgets callback path |
| `hostAction` on a prepared widget | Declared same-package Expo/NativeScript action in the foreground Host |
| ScriptWidget-rendered Live Activity `hostAction` | Same validated foreground route, recorded as a Live Activity invocation |
| Native-node Live Activity action | Existing `hostServices.liveActivities.start({root, actionEntrypointID})` declaration, with a Live Activity intent and post-enqueue foreground continuation |
| Original Expo `createLiveActivity` callbacks | Original Expo Widgets ActivityKit implementation; these do not implicitly read `hanlinWidget.hostAction` metadata |
| Native snippet or translation presentation callbacks | Existing local presentation executor; `hostAction` is not a panel callback kind |

The package's foreground engine and widget renderer are separate choices. A NativeScript application can contain an original ScriptWidget widget and must retain its root `widget.jsx`, `widget.tsx`, `widget.ts`, `widget.js` or `widget.json` resource. The NativeScript authoring builder stages declared widget resources at the package root and in the module resource tree. An Expo application uses the Expo widget renderer; it does not select `widgetEngine: "scriptwidget"`. Standalone ScriptWidget packages retain their original local widget/runtime APIs and do not advertise an Expo/NativeScript foreground Host action.

## Parameters, identity and diagnostics

`hostAction.parameters` uses ordinary JSON: null, booleans, finite numbers, strings, arrays and objects. It is not the internal tagged `HanlinValue` encoding. Omission and explicit null remain distinct in the stored program. When the rendered command supplies event parameters, they override the authored defaults.

A widget action has one unique ID. A Host action must not also declare a local `handler` or `stateKey`. Runtime admission binds the origin to the actual installation, generation, widget variant, renderer, immutable program digest, family and action declaration. A supplied nonce identifies one event; exact retries return the retained durable result without replaying a completed handler, including after removal. Changed event parameters conflict with that event identity. New admissions and queued execution still validate the current installed origin; disabled, removed, replaced or mismatched origins produce a real error instead of silently running another action.

`validate_miniapp` and `build_miniapp` report invalid declarations as `MINIAPP_WIDGET_HOST_ACTION_INVALID`, with the file and offending metadata path. The original TypeScript compiler checks typed source imports against `@hanlin/system-surfaces`; for example, a function is not a JSON parameter and a Host action is not a native-panel action. Imported source-bearing packages run the same validation before installation. The application's diagnostic sheet and Send to agent action use the existing [repair workflow](IMPORT_REPAIR.md).

The SDK and native application must be built from matching source inputs. Updating a declaration file in the repository without staging a new SDK does not update the agent's environment. `stage-sdk.mjs` includes the exact contract, compiler, queue and intent source identities in the SDK input fingerprint, and the original Host preparation workflow runs the authoring tests and produces the archive. See [original upstream build](ORIGINAL_UPSTREAM_BUILD.md) for upstream version resolution and maintained source reconciliation.

## Keyboard, notification content, Spotlight and capture

The foreground package keeps its original Expo or NativeScript entrypoint and runtime. Its declared system entrypoints refer to that prepared foreground bundle: normally `bundle.js` for Expo or `nativescript/app/bundle.mjs` for NativeScript. A native presentation has its own original-renderer source in `nativePresentations`; that source is separate from the foreground bundle.

| `entrypoints[].kind` | Installed system integration | Additional package declaration |
| --- | --- | --- |
| `keyboard` | The owning app's real iOS custom keyboard extension, with installed package selection | A matching `nativePresentations[entrypointID]` |
| `notificationUI` | The owning app's notification-content extension and existing notification category | A matching native presentation and typed notification `userInfo` |
| `spotlight` | Searchable entity for each installed declared package entrypoint | Optional `exportedSymbol`; when present it identifies exactly one registered prepared action |
| `capture` | Camera Control / locked camera extension, with foreground camera continuation and file handoff | Required `exportedSymbol` identifying exactly one registered prepared action |

These are additional exposure declarations for an installed package. They do not introduce a custom home entrypoint. The legacy Scripting/ScriptUI feature expansion remains frozen.

For example, merge the following metadata into a NativeScript package's existing `script.json`; keep the rest of its original package manifest and source files:

```json
{
  "entrypoints": [
    {"id": "keys", "kind": "keyboard", "sourcePath": "nativescript/app/bundle.mjs"},
    {"id": "notice", "kind": "notificationUI", "sourcePath": "nativescript/app/bundle.mjs"},
    {"id": "search", "kind": "spotlight", "sourcePath": "nativescript/app/bundle.mjs"},
    {"id": "photo", "kind": "capture", "sourcePath": "nativescript/app/bundle.mjs", "exportedSymbol": "capture.receive"}
  ],
  "actions": [
    {"id": "capture.receive", "handler": "nativescript/app/bundle.mjs"}
  ],
  "nativePresentations": {
    "keys": {"engine": "scriptwidget", "sourcePath": "keyboard.tsx", "sourceFormat": "tsx"},
    "notice": {"engine": "scriptwidget", "sourcePath": "notification.tsx", "sourceFormat": "tsx"}
  }
}
```

The two presentation files must exist and use their declared original renderer. Add their declared local callbacks to each presentation's `actions` array. An original Expo presentation uses `engine: "expo"` with its actual Expo layout/program; the public `NativePresentationDefinition` declares the supported formats. Metadata does not supply a missing renderer or JavaScript handler.

### Keyboard context and editing

An original ScriptWidget presentation reads the current document context through `$getenv("presentation")`. `keyboard.documentContextBeforeInput`, `documentContextAfterInput` and `selectedText` are optional because iOS may not supply them. `keyboard.hasFullAccess` is the current system setting. The typed bridge exposes:

```ts
$presentation.keyboard.insertText("שלום");
$presentation.keyboard.deleteBackward();
$presentation.keyboard.adjustTextPosition(-1);
$presentation.keyboard.nextInputMode();
```

Call these inside a declared local presentation action. Edits execute in order against the current `UITextDocumentProxy`. An Expo presentation callback can return `NativePresentationPropsEffect`, with `__hanlinPresentationEffect.keyboardEdits` containing the same typed operations. The surface supplies ordinary Space, Return, Delete and next-keyboard controls as well as the package's original-renderer interface.

The keyboard reads the containing app's published installed catalog; renderer state, copied resources and mutable ScriptWidget service files live in the keyboard's own container. The read-only catalog path does not create a shared lock or write shared diagnostics. Apple's current [open-access documentation](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) permits reading the containing app's shared containers without Full Access; network access and shared-container writes depend on the actual iOS setting. The Host does not add an extra opt-in for ordinary local keyboard editing.

### Notification selection and foreground continuation

Use `NotificationPresentationUserInfoV1` from `@hanlin/system-surfaces` for the notification's ordinary JSON `userInfo`:

```ts
import type { NotificationPresentationUserInfoV1 } from "@hanlin/system-surfaces";

const userInfo: NotificationPresentationUserInfoV1 = {
  "hanlin-miniapp-presentation": {
    schemaVersion: 1,
    identity: {
      installedPackageID: "the-actual-installation-id",
      packageID: "the-actual-package-id",
      generation: 1,
      entrypointID: "notice"
    },
    parameters: {message: "Ready"}
  }
};
```

Replace the example identity with the current installed identity and use the owning app's existing notification category (`CHAVRUSA_REMINDER` in its current configuration). The presentation key selects the rich interface. A notification without this key retains the ordinary notification content.

The original ScriptWidget callbacks are `$presentation.notification.openApp()` and `.dismiss()`. Expo callbacks use the equivalent `notificationAction` effect. To continue a real package action, also include the existing `hanlin-miniapp-event` envelope from the notification API. Its action entrypoint may differ from the presentation entrypoint, but its installation, package and generation must match. The extension persists the exact event through the existing durable queue before requesting the system's default notification action. The resulting queue receipt means queued; the foreground executor records actual completion or failure.

### Spotlight lifecycle

The searchable catalog follows installed packages and their explicit `spotlight` declarations. It is independent of widget configuration and does not require a widget instance. Index reconciliation includes installation, replacement, disablement and removal. Opening a result resolves the current installed identity.

A Spotlight entrypoint without `exportedSymbol` opens its package's foreground application. With an exported symbol, it continues that registered action through the existing foreground invocation path with the typed input `{source: "spotlight"}`. The action must be unique in `actions[]`, and its prepared handler must match the entrypoint's source.

### Camera and saved-file input

A `capture` entrypoint always declares an action to receive its photos. Choose the capture package in its package details, then use its foreground camera or the owning app's camera control. Locked capture uses Apple's `LockedCameraCapture` session content and the capture App Intent context; it does not access the app's package store or App Group from the locked process.

On handoff, the containing app verifies and copies the captured bytes into the selected package's Documents area before admitting the existing foreground action. The action receives `NativeCaptureInput` from `@hanlin/system-surfaces`:

```ts
import type { NativeCaptureInput, NativeCaptureFile } from "@hanlin/system-surfaces";
```

The input carries `source` (`lockedCamera` or `applicationCamera`), `sessionID`, `installedPackageID`, `packageID`, `generation`, `entrypointID`, and `files`. Each `NativeCaptureFile` has its identifier, `area: "documents"`, a relative `captures/<session>/<photo>.jpg` path, JPEG content and MIME types, byte count, SHA-256, width and height. Read the relative path through the package's existing typed Host file service. It is already in that package's Documents area.

The handoff retains its invocation identity for retries, and its durable receipt records the actual Host result. A stored capture or accepted queue message alone does not establish that its handler completed. Disabled, removed or replaced package generations cannot silently receive a capture intended for an older installation.

### Validation, types and native build

`PreparedMiniAppEntrypoint` makes `exportedSymbol` mandatory for `kind: "capture"`. The authoring validator and native analyzer also validate the actual manifest relationship. Missing or conflicting capture/Spotlight actions produce `MINIAPP_SYSTEM_ACTION_INVALID`; missing keyboard/notification native presentations produce `MINIAPP_SYSTEM_PRESENTATION_REQUIRED`. Both identify `script.json` and actionable remediation before packaging. The same diagnostics use the existing import Sheet and agent repair workflow.

The original compiler checks source against the staged declarations. Validation and build require the prepared SDK and Host from the same source inputs; these six new extension targets also require a fresh native Host build. A portable TypeScript or manifest check does not establish that iOS launched a keyboard, displayed rich notification content, opened a Spotlight result or captured a photo. Those are separate native and device acceptance results.
