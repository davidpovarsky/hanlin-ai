# Widget and Live Activity actions

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
