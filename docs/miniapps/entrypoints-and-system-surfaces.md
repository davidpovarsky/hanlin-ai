# Prepared MiniApp entrypoints and native system surfaces

Expo and NativeScript applications retain their original runtime and upstream libraries. These entrypoints are host adapters around the prepared application bundle. ScriptWidget remains the original widget renderer. The legacy Scripting engine is frozen; a custom home screen entrypoint is not part of this contract.

## Authoring and entrypoint identity

Import every action module from the application's normal entry module before building with its original bundler. Declare exposures in script.json:

~~~json
{
  "entry": "bundle.js",
  "hanlinRuntime": "hanlin-expo",
  "entrypoints": [
    {"id":"appIntents", "kind":"appIntent", "sourcePath":"bundle.js", "exportedSymbol":"search"},
    {"id":"intent", "kind":"appIntent", "sourcePath":"bundle.js", "exportedSymbol":"search"},
    {"id":"share", "kind":"share", "sourcePath":"bundle.js", "exportedSymbol":"search"},
    {"id":"translation", "kind":"translationUI", "sourcePath":"bundle.js", "exportedSymbol":"search"},
    {"id":"activity", "kind":"liveActivity", "sourcePath":"bundle.js"}
  ],
  "actions": [
    {"id":"search", "handler":"bundle.js", "capability":"inter-app.share", "title":"Search"}
  ]
}
~~~

For NativeScript, use the prepared canonical path nativescript/app/bundle.mjs and hanlin-nativescript. Declaration IDs remain distinct even when two exposures have the same kind or share a bundle. exportedSymbol selects the registered action name, not an independently loaded source module. Invalid declarations return a structured MINIAPP_ENTRYPOINT_DECLARATION_INVALID diagnostic. The installed store resolves a package-relative handler to its actual source/bundle.js path once.

Expo registers handlers through @hanlin/expo-ui:

~~~ts
import {hostServices} from '@hanlin/expo-ui';

void hostServices.actions.register({
  search: async ({parameters, caller, id}) => {
    const result = await performSearch(parameters);
    return {summary: result.summary, total: result.total};
  },
}).catch(showRuntimeError);
~~~

The registration promise lives for the native session's lifetime. Each invocation uses a unique request ID and receives the awaited handler result. Undefined, nonfinite values, cycles, thrown errors, cancellation, and native session closure do not become successful replies. Return JSON values.

## Actual native entrypoints

| Surface | Execution and result |
| --- | --- |
| Share | The MiniApps share extension stores an owned batch in its own product namespace. The app inbox chooses a declared action and forwards its text, URLs, and owned attachments. |
| Shortcuts / App Intents | A native action queues one durable invocation and returns its invocation ID. A prepared Expo action opens the real React Native view; a prepared NativeScript foreground action opens its real native view. |
| Snippet | A native SnippetIntent reads that invocation's receipt. It does not execute the package again. The host reloads the visible snippet on completion; a refresh button reads the same receipt. |
| Shortcut output | Add **Wait for MiniApp Result**, using the invocation ID from the run action, to obtain the actual text or JSON result. Failure/cancellation/expiry throws instead of returning invented output. A binary result is represented as base64. |
| Translation | The existing native translation provider displays selected text and an action button, then opens the prepared application with the exact selected text. This is a foreground continuation; arbitrary React Native/NativeScript views do not run inside the translation extension. |
| Widgets | Existing original Expo / ScriptWidget widget execution and rendering continue in the dedicated MiniApps widget extension. |
| Live Activities | Both active app runtimes call the same typed ActivityKit host API. Existing lock screen / Dynamic Island rendering and native action buttons use the installed package identity and generation. |

The standalone app embeds its own HanlinMiniAppsWidgets, HanlinMiniAppsShare, and HanlinMiniAppsTranslationProvider executables. Their bundle identifiers belong to com.itorah.hanlinminiapps. They share the original App Group entitlement but address HanlinMiniApps/v1 below it. The AI application's original extension namespace remains separate. Neither product looks up the other's receipt or Share inbox as a fallback.

## Typed ActivityKit host API

Expo exports hostServices.liveActivities. NativeScript exports createHostServices().liveActivities from @hanlin/host-services. Both use the single schema in Packages/HanlinExpoUI/src/system-surfaces.ts; the NativeScript build emits the corresponding portable declarations into its original shared runtime package.

~~~ts
const {activityID} = await host.liveActivities.start({
  title: 'Search',
  actionEntrypointID: 'appIntents',
  state: {count: 3},
  root: {
    kind: 'liveActivityUI',
    children: [
      {kind: 'liveActivityContent', children: [
        {kind: 'text', properties: {text: '3 results'}},
        {kind: 'button', properties: {
          intent: {__hanlinAppIntent: true, name: 'search', parameters: {query: 'שלום'}}
        }, children: [{kind: 'text', properties: {text: 'Open results'}}]}
      ]},
      {kind: 'liveActivityCompactLeading', children: [{kind:'text', properties:{text:'3'}}]},
      {kind: 'liveActivityCompactTrailing', children: [{kind:'text', properties:{text:'results'}}]},
      {kind: 'liveActivityMinimal', children: [{kind:'text', properties:{text:'3'}}]}
    ]
  }
});

await host.liveActivities.update(activityID, {state: {count: 4}});
await host.liveActivities.end(activityID, {dismissAfterSeconds: 0});
~~~

areEnabled() reads the system's current state. list() returns this installed package's actual activity IDs. Starting returns the system-issued ID; updating or ending returns whether that activity still exists. Native errors propagate to the caller. Omitted update/end layout and state preserve the latest system-held values.

This host API is separate from the upstream expo-widgets Live Activity module. The original Expo widget view renderer is embedded; this change does not claim that the complete upstream Expo LiveActivityController/module is embedded. Native compilation, system presentation, OS authorization, and device execution remain separate verification stages from JavaScript typechecking and transport tests.

## Focused verification

- HanlinMiniAppActionChannelTests: real asynchronous Swift request/reply identity, registration errors, cancellation and closure.
- HanlinMiniAppSurfaceRoutingTests: actual product-scoped receipts, first-share inbox routing, and literal nested translation input.
- HanlinScriptAnalyzerTests: explicit entrypoint identity and invalid declarations.
- HanlinScriptMiniAppRegistrationTests: exact installed bundle handler resolution.
- Scripts/CI/IntegrationValidation/test_project_graph.py: independently owned native targets, actual embedding and original SDK linkage.
- Scripts/NativeScript/build-host-services.mjs: strict original TypeScript compiler, valid and invalid API fixtures, and generated declaration drift.
- Scripts/NativeScript/Tests/live-activities.test.mjs: real facade routing against a controlled transport; this does not claim ActivityKit execution.
