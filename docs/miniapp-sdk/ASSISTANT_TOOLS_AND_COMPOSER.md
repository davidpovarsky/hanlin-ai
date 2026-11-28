# Assistant tools and composer configuration

This extends the existing Hanlin Platform, Agent and Presentation SDKs. It does not add another tool runtime or chat composer.

## What selection means

Catalog availability and message selection are independent. A capability reference identifies a provider instance and one capability. Selecting from the picker, an @ mention or a / command adds a value snapshot to the draft. It does not open the MiniApp, load its app/index entrypoint, run a search or invoke a business action.

When the user sends the message, the host resolves the exact reference/revision, validates configuration and makes the explicitly chosen capability available for that request. The model still chooses a relevant action and supplies its ordinary arguments. An installed MiniApp's dedicated assistant program starts only when that action is called.

The public types are in HanlinPlatformContracts:

- HanlinCapabilityReference: kind, sourceID, capabilityID, revision.
- HanlinCapabilityAttachment: per-attachment UUID, reference, title, optional actionID, configuration, configurationVersion.
- HanlinComposerCapabilityDescriptor: display metadata, optional action menu and composer configuration.
- HanlinComposerConfiguration: schema version and panels. The shared HanlinChatUI configuration view presents these inside the existing composer bubble.
- HanlinAssistantToolDeclaration: the manifest's action table and optional configuration.

Display names are never dispatch identities. For installed MiniApps use the installed package ID, assistant entrypoint ID and generation. The same package installed in two hosts/providers is represented by separate provider identities. An attachment snapshots structured data; later draft edits cannot rewrite previous messages.

## Author a dedicated tool module

The normal foreground app stays in its ordinary entry. Add a separate module exporting action functions, then map the assistant entrypoint ID to that source in hanlin.authoring.json:

~~~json
{
  "schemaVersion": 1,
  "engine": "expo",
  "entry": "index.ts",
  "tsconfig": "tsconfig.json",
  "assistantTools": { "search-tool": "assistant-tool.ts" }
}
~~~

Declare the prepared output and callable actions in script.json:

~~~json
{
  "name": "Text search",
  "version": "1.0.0",
  "entry": "bundle.js",
  "hanlinRuntime": "hanlin-expo",
  "entrypoints": [{
    "id": "search-tool",
    "kind": "assistantTool",
    "sourcePath": "assistant/search/bundle.js",
    "assistantTool": {
      "title": "Search texts",
      "summary": "Search the collections selected by the user.",
      "actions": [{
        "id": "search",
        "title": "Search",
        "summary": "Find a query in the selected collections.",
        "inputSchema": {
          "type": "object",
          "properties": { "query": { "type": "string", "minLength": 1 } },
          "required": ["query"],
          "additionalProperties": false
        }
      }],
      "configuration": {
        "schemaVersion": 1,
        "panels": [{
          "id": "catalog",
          "title": "Collections",
          "fields": [{
            "key": "collections",
            "title": "Search in",
            "kind": "catalog",
            "defaultValue": [],
            "options": [
              { "id": "tanakh", "title": "Tanakh" },
              { "id": "talmud", "title": "Talmud" }
            ]
          }]
        }]
      }
    }
  }]
}
~~~

For NativeScript the prepared source path ends in bundle.mjs. Every assistant entrypoint has its own prepared folder and package.json whose main and hanlinRuntime match that program. The importer rejects missing metadata, shared app entries, invalid action schemas, stale/unknown renderer links and unprepared roots. A file named assistant_tool.ts alone does not register a modern assistant capability.

Import the type-only package exported with the actual host SDK:

~~~typescript
import type { HanlinAssistantToolHandler } from '@hanlin/assistant-tools';

interface Arguments { query: string }
interface Configuration { collections: string[] }

export const search: HanlinAssistantToolHandler<Arguments, Configuration> =
  async (arguments_, context) => {
    // Call the provider with arguments_.query and context.configuration.collections.
    // This illustrative result simply makes the two input sources visible.
    return {
      query: arguments_.query,
      collections: context.configuration.collections
    };
  };
~~~

Each handler receives:

1. Model arguments, validated against inputSchema.
2. A context containing the immutable user configuration, actionID and caller.

Configuration is separate from arguments. A model argument named configuration cannot replace the user's selection. The action implementation must read context.configuration when selecting collections, coordinates, radius or other explicit settings. The input schema describes model arguments, not this separate context.

The action ID is registered on the existing Host Services transport. exportedSymbol, when supplied, names a different export in the dedicated source module. It never selects the foreground app. Actions return finite, acyclic JSON or a promise of JSON; return null when there is no result. Runtime failures remain errors.

## Build and validate through the existing authoring tools

Use the host's get_miniapp_sdk / validate_miniapp / build_miniapp / import_miniapp flow or the existing Scripts/MiniApps/miniapp.mjs CLI. Source validation checks each declared export is callable. The existing original TypeScript compiler emits NativeScript modules; the existing original Metro configuration bundles Expo.

The builder creates a dedicated wrapper without importing the app entry:

- NativeScript registers the declared action IDs on the captured native session bridge, under assistant-tool.
- Expo registers the action table through hostServices.actions.register and an empty HanlinAssistantTool root through React Native AppRegistry.
- Both wrappers call the named export with the same arguments/context contract.
- Source files and source maps remain in the source-preserving package.

The SDK exports @hanlin/assistant-tools declarations, assistant-tools.schema.json, this guide, and the independent assistant-examples catalog. These are host contracts; original engine libraries remain the runtime authority.

## Configuration controls

| kind | Stored JSON | Meaning |
| --- | --- | --- |
| text | string | Text or a catalog query |
| toggle | boolean | An explicit on/off choice |
| number | number | Finite number, with optional minimum/maximum |
| choice | string | One option ID |
| multiChoice | string[] | Unique selected option IDs |
| catalog | string[] | Unique IDs from a nested option tree |
| location | object | latitude, longitude, radiusMeters |

A configuration may have several panels. The existing bubble provides the menu between them. Keys must be unique across panels so the resulting object is unambiguous. Required values, option membership, numeric bounds and map coordinates are validated. Latitude must be within -90...90, longitude within -180...180, and radius positive. For location fields, minimum and maximum apply to radiusMeters.

Defaults belong to a new attachment snapshot. Removing an attachment removes its settings from that draft. A later message or another conversation has its own snapshot.

~~~json
{
  "id": "location",
  "title": "Search area",
  "fields": [{
    "key": "area",
    "title": "Pin and radius",
    "kind": "location",
    "required": true,
    "defaultValue": {
      "latitude": 31.77835,
      "longitude": 35.23388,
      "radiusMeters": 1500
    },
    "minimum": 100,
    "maximum": 50000
  }]
}
~~~

A native embedding host can register a custom panel view using customViewID and the shared view's configuration binding. Such a view edits JSON only. Providers own validation of additional fields edited by that custom view; the shared validator validates its declared fields. The action inputSchema is not a substitute for custom configuration validation.

## Rich results

An action may name embeddedResultID, referring to an exact sibling entrypoint whose kind is embeddedResult. The importer verifies that reference. The existing Hanlin embedded result pipeline receives the returned JSON and the declared renderer identity. There is no fallback to the first renderer or an arbitrary handler from model arguments.

A rich result entrypoint is separate from the selection/configuration surface. Do not put a business action in a view initialization merely to obtain its configuration.

## Executable examples

- Scripts/Expo/miniapps/modular-text-search/assistant-tool.ts: real Sefaria search through the existing native transport/client. The manifest supplies collection filters, matching field and page size. These values are forwarded into the client's actual request payload.
- Scripts/MiniApps/AssistantExamples/map-places: complete NativeScript app with a dedicated assistant source. It filters explicitly fictional local fixture places by pin, radius, category and query. It does not claim to query a real restaurant/places service. Its output preserves the selected area and identifies its local-fixtures provider.
- The compiler/contract tests cover metadata-only selection, separate preparation, absent exports, foreground fallback rejection, immutable defaults, stale revisions, invalid coordinates/options and exact rich result references.

Use native engine integration results and UI acceptance on the final source SHA to determine verified behavior. Declaration validation or JavaScript wrapper tests alone do not prove native engine or device execution.
