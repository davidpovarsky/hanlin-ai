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

## Original ScriptWidget native services

`HanlinScriptWidgetOriginal` compiles the upstream native API/core source at
`4da256d58247bbafb9a5cd443a285250b97b3c4b`, in its own Swift 5 module. The source
manifest records each original path, Git blob, local hash and host adaptation.
The original support scripts (`core.js`, `util.js`, `moment.min.js`) use that
same commit. Native providers are real framework implementations: EventKit,
Contacts, HealthKit, CoreLocation, HomeKit, Photos, MediaPlayer, AlarmKit,
UserNotifications, MapKit, URLSession, Security, and the original file/cloud
storage and service-account code.

The prepared Hanlin widget executes with the original `ScriptWidgetRunningState`,
`ScriptWidgetExecutionSession`, JSExport registrations and Promise delivery.
Native async operations now settle on the upstream callback queue before the
surrounding Hanlin state transaction commits. The previous immediate
“unsupported asynchronous operation” rejection and separate synchronous HTTP
implementation were removed. The existing immutable Hanlin renderer remains the
UI boundary; this does not claim every upstream system-surface presentation has
been embedded.

Original `$storage` reads, JSON operations and compare-and-set use an execution
transaction adapter. Its current instance values are committed by the existing
Hanlin widget store; original native metadata, grants and mutation receipts use
the original durable backend. The native installation identity is the canonical
Hanlin widget identity plus exact artifact hash. AI and MiniApps use separate
product roots. Native account credentials use separate product service Keychain
groups, shared only with the matching widget extension.

Packages that supply original `widget.json` retain its original API permissions
and data-source declarations. Existing Hanlin widgets without that manifest
receive a host manifest enabling the supported original APIs, without another
Hanlin approval prompt. Apple system authorization and the original providers'
API contracts still apply. Native settings are reachable through
`platform.scriptWidgetServicesView(for: instance.entityID)`: original Calendar,
Reminders, Photos, Music, Contacts/Home/document selection, cloud connection and
service-account UI, plus native Health/Location setup using the original types.
Successful selection changes reload the actual widget timelines.

The apps and matching widget targets declare the original APIs' actual privacy
usage descriptions, HealthKit/HomeKit capabilities, iCloud container and service
Keychain group. Updated device profiles must contain those native capabilities;
a source-level declaration alone is not evidence that a signed device build has
those entitlements.

Four new Apple-host tests exercise real provider registration/device values,
the actual async `$documents.list()` path, original Promise failure delivery,
and one shared transaction for original storage and compatibility aliases.
Linux Swift syntax parsing and SwiftPM manifest evaluation passed. Execution
of these native tests, Apple typechecking, signed entitlements and device data
access require the Apple CI/device gate; no pass is inferred from syntax parsing.

## Interactive native snippets and translation panels

`script.json.nativePresentations` binds an explicit `appIntent` or
`translationUI` exposure to a separate, editable native presentation program.
It accepts the original `expo` widget renderer or `scriptwidget` compiler,
native APIs and renderer. These are not WidgetKit instances, and do not appear
as artificial entries in the widget picker. The foreground app may still use
Expo or NativeScript independently.

```json
{
  "nativePresentations": {
    "appIntents": {
      "engine": "scriptwidget",
      "sourcePath": "native/search.tsx",
      "sourceFormat": "tsx",
      "actions": [
        {"id":"loadMore","kind":"function","handler":"loadMore"}
      ]
    },
    "translation": {
      "engine": "scriptwidget",
      "sourcePath": "native/search.tsx",
      "sourceFormat": "tsx",
      "actions": [
        {"id":"loadMore","kind":"function","handler":"loadMore"}
      ],
      "input": {
        "title":"Search text",
        "placeholder":"Enter a word or sentence",
        "submitTitle":"Search again"
      }
    }
  }
}
```

The source directory is a self-contained module/resource tree. ScriptWidget
modules export a default render function, and named action handlers. The
original Babel/JSX compiler resolves local imports at install time; foreign
foreground-framework imports are errors, rather than an implicit legacy
Scripting execution path. The import preview reports errors at the native
source path. The installer writes each verified compiled program below
`presentations/<entrypoint-id-sha256>.json` before publishing the exposure.

**Shortcuts:** choose **Show MiniApp Snippet**, select an installed native
presentation, and supply text/JSON parameters. Its SnippetIntent renders the
actual program in the system result UI. Buttons execute declared original
engine actions and return an updated snippet. It does not require a queued
foreground action to manufacture a snippet. Existing **Run Script Action** and
durable receipt snippets remain available for foreground actions.

**Translation:** the same program renders inside the native
TranslationUIProvider extension. The optional input descriptor presents a
native editable text field and submit button. New queries get a new presentation
session. The host calls Apple's real `expandSheet()` and
`finish(translation:)` APIs; replacement availability is the source
application's `allowsReplacement` value.

ScriptWidget receives `$getenv("presentation")` / `$widget.presentation`:

```ts
{
  kind: "snippet" | "translationUI",
  sessionID: string,
  inputText: string,
  parameters: JSONValue,
  allowsReplacement: boolean
}
```

Its translation host binding exposes `$presentation.expandSheet()` and
`$presentation.finish(replacementText?)`. The original renderer's buttons may
supply `actionParameters`; named handlers receive
`{ parameters, value? }`. Expo layouts receive the same presentation context in
the renderer environment and may return
`__hanlinPresentationEffect: { expandsSheet, finishRequested, replacementText? }`
from their original callback. This host transport does not replace the original
engine APIs.

State is scoped to product store, installation, active generation, entrypoint,
program digest, input and session UUID. Actions validate the current immutable
program and declared handler, and explicit action nonces prevent retrying one
tap twice. Two simultaneous snippets never share view state. Removing or
changing the exposure invalidates earlier requests.

### Modular text search parity and evidence

The Expo sample is version **1.4.0**. Its native subtree preserves eleven engine,
normalization, grouping, localization and snippet-model modules from the exact
user attachment, SHA-256
`3f81e380acefbafade23effea989e969cce6a404a3754cfbdb33609408802b15`.
`native/original-source-proof.json` records each original module and local
adaptations. Only transport/storage integration is changed in those modules:
the native panel uses the original ScriptWidget `$http` and storage APIs.

Native presentations support grouped search results, preferred and alternative
versions, full text and version details, pagination, source links, input changes,
errors and retry, plus actual selected-text replacement. Pagination uses an
explicit native **Load more results** button in the system snippet; the source
Scripting snippet used an on-appear scroll sentinel. The interactive native
surface is a port of the behavior, not execution of the frozen Scripting UI.

`node --test Scripts/MiniApps/test-native-presentations.mjs` executes the actual
original compiler and ported module graph: typed local imports/actions,
foreign-import rejection, original top-level async compatibility, and the
sample's grouped search/version/full-text/pagination/replacement flow. HTTP
responses in that deterministic JavaScript test are fixtures, not a claim of a
device network test. Four Apple cases in
`AI_HLYTests/HanlinNativePresentationTests.swift` cover original async providers,
state isolation, all seven native Dynamic Island regions, and stale-generation
or other-product rejection. Apple test results must come from the native gate.

The host also captures original `$dynamic_island` seven-region values as
`HanlinScriptWidgetDynamicIsland`. Function JSX components resolve before native
rendering. `$component` retains upstream's registration diagnostic behavior; it
does not invent a separate component registry.

### Live public source verification

On 2026-11-23 the retained native Sefaria client made a real public search for
בראשית and fetched the selected Genesis 1:1 source and translation versions.
Both original endpoints returned HTTP 200. Search returned two requested results
and a reported total of 10,000; the full-text response normalized non-empty Hebrew
and English versions. Evidence (timestamps, response sizes and SHA-256 only) is
in `verification/sefaria-original-client-live-20261123.json`. Reproduce with
`node Scripts/MiniApps/verify-sefaria-live.mjs`. This check used Node HTTPS as
the adapter for the original ScriptWidget HTTP contract; it is distinct from
native JavaScriptCore/provider and device UI acceptance evidence.

## Original Expo Widgets configuration

The **Expo MiniApp** WidgetKit configuration selects registrations produced by the
original `expo-widgets` `createWidget` API. Its entity identifier includes the
containing product and installed package identity; the picker shows the package
identifier with the original widget name. Active registrations are suggested.
An existing disabled configuration retains its exact identity and shows an
unavailable state until that installation publishes an active generation.

The host delegates stored timelines to the original `parseTimeline` path and
passes its entries directly to original `WidgetsEntryView`. It preserves the
original timeline policy and all seven supported WidgetKit families. Each app
and its own widget extension declares the same existing Expo App Group and its
actual containing product identifier. There is no fallback to the other app
or a similarly named package.

`AI_HLYTests/HanlinOriginalExpoWidgetTests.swift` adds one Apple case using the
actual original `AppContext`, `WidgetObject`, records, timeline parser, public
provider and picker. It checks the embedded original runtime resource,
product/installation identity and native timeline values. Syntax validation
does not execute this case; acceptance requires its Apple test result.
