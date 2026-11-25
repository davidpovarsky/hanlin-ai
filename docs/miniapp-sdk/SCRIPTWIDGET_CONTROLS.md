# Original ScriptWidget Control Widgets

Control Widgets use the installed original ScriptWidget Package 2.0 contract:
a root-level **widget.json** with **actions** and **controls**. This is the
original manifest parsed by ScriptWidgetPackage.readManifest and checked by
WidgetPackageManifestValidator. Hanlin's WidgetKit integration projects those
declarations into the installed original button/toggle Control Widgets.

## Discover the exact host contract

Call get_miniapp_sdk with engine **scriptwidget**. Its selected engine exposes:

| SDK resource | Purpose |
| --- | --- |
| packageManifestSchemaPath → scriptwidget/widget-manifest.schema.json | JSON field types, original constraints and source commit/hash identities |
| packageManifestValidatorPath → scriptwidget/manifest-validation.mjs | Authoring diagnostics for the original JSON contract |
| scriptwidget/widget-manifest.d.ts | Original WidgetPackageManifest, WidgetPackageAction and WidgetPackageControl types |
| scriptwidget/host-globals.d.ts | Original native services and the installed host environment |

The declaration file is referenced by the normal ScriptWidget SDK tsconfig.
Use WidgetPackageManifest / WidgetPackageControl in TypeScript or in JavaScript
JSDoc. An editor can associate the schema with widget.json through its JSON schema
settings. Do not add a $schema property to widget.json: the original reader
rejects unknown properties, including that editor annotation.

SDK staging generates field definitions, enum values and runtime version constants
from the original Swift files used in the host build. Their source hashes and
upstream commits travel with the generated schema. A change to the original
semantic validator requires updating its authoring translation before staging
can succeed; this prevents an old validator from silently accepting a newly
incompatible manifest. Native import still runs the actual original Swift
validator, including Foundation's platform checks.

## Complete original manifest example

The widget source and the authoring entry are both main.jsx:

<!-- miniapp-snippet: controls.manifest -->
~~~json
{
  "formatVersion": 2,
  "id": "example.focus-controls",
  "name": "Focus controls",
  "version": "1.0.0",
  "runtimeVersion": "1.0",
  "minimumRuntimeVersion": "1.6",
  "entry": "main.jsx",
  "supportedFamilies": ["systemSmall"],
  "permissions": ["storage"],
  "networkDomains": [],
  "actions": [
    {
      "id": "toggle-focus",
      "title": "Focus",
      "systemImage": "moon",
      "function": "toggleFocus"
    }
  ],
  "controls": [
    {
      "id": "focus",
      "type": "toggle",
      "title": "Focus",
      "systemImage": "moon",
      "actionID": "toggle-focus",
      "stateKey": "focus.enabled"
    }
  ]
}
~~~

Original Package 2.0 manifests use **.js or .jsx** entries. widget.json.entry must
equal hanlin.authoring.json.entry and the widget's declared source entry.
TypeScript/TSX authoring without this original manifest keeps its existing
compiler path; renaming TSX to JSX does not convert it.

Control actions are taken directly from the original actions array. Do not
repeat them in hanlinWidget.actions. Buttons use type **button** and omit
stateKey. Toggles use type **toggle**, supply stateKey, and declare the original
**storage** permission. A control references one declared action through actionID;
the original legacy action function field also works. Both fields together are
invalid. Identifiers/references follow the original case-insensitive comparison
rules. Multiple controls may share an action while using separate state keys.

The original runtime's own field formats and supported declaration counts are
preserved. The authoring layer adds no separate control-count limit or approval
step.

## Handler and state semantics

<!-- miniapp-snippet: controls.handler -->
~~~jsx
// @ts-check
function toggleFocus() {
  const enabled = $getenv("control-value");
  $storage.setString("focus.enabled", enabled);
}

$render(
  <vstack>
    <text>{$storage.getString("focus.enabled") ?? "false"}</text>
  </vstack>
);
~~~

A control-only source may declare its action functions without calling $render.
The native host executes those functions through the same original runtime session.

During a control invocation the installed runtime provides these keys through
$getenv and $widget:

| Environment key | Value |
| --- | --- |
| widget-size | "action" |
| widget-param | "" |
| action-id | Resolved original action ID |
| action-source | "control" |
| control-id | Original control ID |
| action-value / control-value for a toggle | String "true" or "false" |

A toggle persists its state under the declared stateKey as the **string**
"true" or "false", matching original $storage.getString behavior. It does not
change this stored value to a JSON Boolean. The host maintains a separate
prepared invocation for each control, so sharing one action does not merge
unrelated toggle state keys. These prepared IDs are implementation details and
are not additional manifest declarations.

## Validate, package and repair

1. Write script.json, hanlin.authoring.json, tsconfig.json, main.jsx and widget.json.
   Set the main engine to scriptwidget, the source format to jsx and the entry
   to main.jsx. Keep regular assets in hanlin.authoring.json.resources.
2. Call validate_miniapp. Genuine manifest JS/JSX entries are checked with the
   installed TypeScript compiler and checkJs enabled. Manifest diagnostics
   include the original rule code, widget.json, JSON path and one-based
   line/column; source type errors retain their TS codes and source locations.
3. Call build_miniapp. The exact original widget.json is retained at the archive
   root, as well as under source/. Original JSX, declared resources and an
   existing manifest preview file remain in the runnable package. The root
   manifest participates in the compiled hash receipt.
4. Import the successful archive. Native import recompiles/checks the package
   and runs the original Swift manifest validator. Repair diagnostics through
   the existing agent flow, then build a fresh archive so the receipt matches.

This original control manifest applies to a main ScriptWidget widget package.
Expo/NativeScript nativePresentations keep their own presentation declarations;
a root widget.json does not introduce mixed-engine controls or a separate
presentation manifest convention.
