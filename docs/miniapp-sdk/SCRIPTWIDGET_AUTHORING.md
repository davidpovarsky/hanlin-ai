# ScriptWidget authoring in Hanlin

ScriptWidget is an active widget engine. Legacy Scripting/ScriptUI remains frozen.

## The installed API is the authority

The author SDK retains the original ScriptWidget editor catalogs, Apache-2.0 license, notice, source revision and file digests. The component generator produces 29 native JSX tag declarations from that catalog. The service generator reads the **actual Swift JSExport protocols and installBaseAPIs bindings** included in the host, checks the original catalog's argument count and synchronous/asynchronous contract, and emits the matching callable declarations.

The current source baseline has 24 installed native objects and 118 exported methods, including the two console aliases. Evaluated support utilities and Hanlin additions complete the authoring globals. The generated `scriptwidget/native-api.json` contains the exact names, method signatures, source paths and SHA-256 values for the host that was built. Counts are inventory facts, not feature limits.

| SDK resource | Purpose |
| --- | --- |
| `scriptwidget/components.d.ts` | Original catalog JSX tags and properties |
| `scriptwidget/original-api.d.ts` | Generated original native callable methods |
| `scriptwidget/service-types.d.ts` | Structured options, native result nullability and exact native awaitable |
| `scriptwidget/service-shapes.mjs` | Reviewed refinements of dictionary payloads whose native Swift boundary is `[String: Any]` |
| `scriptwidget/host-globals.d.ts` | Original evaluated utilities and Hanlin storage/environment/render additions |
| `scriptwidget/native-api.json` | Machine-readable callable inventory and original source identities |
| `scriptwidget/upstream/` | Original catalogs, revision, license and notices |

The original service objects include alarms, calendar, contacts, device, documents, health, home, HTTP, iCloud JSON, location, maps, music, notifications, photos, reminders, connected services, storage, system, weather and the original declarative data-source plugin API. Native source remains authoritative for supported platform operations and responses. Type validation does not claim that an OS operation executed successfully.

### Use the actual original awaitable

The original `ScriptWidgetRuntimePromise` exposes `then(resolve, reject) -> Void`. It is awaitable. It does not implement native `catch`, `finally`, or promise chaining. The declaration preserves that behavior instead of pretending that the native result is a full JavaScript Promise.

```tsx
const events = await $calendar.events({limit: 5});
const weather = await $weather.forecast({latitude: 31.8, longitude: 35.2});
const currentTitle: string | null = (await $music.current()).title;

$render(
  <vstack>
    <text>{events.items.length} events</text>
    <text>{weather.hours[0].temperatureC}°</text>
    <text>{currentTitle ?? "No current item"}</text>
  </vstack>
);
```

HTTP returns response text or base64, not a browser Response object:

```ts
const text: string = await $fetch("https://example.com/data");
const response = await $http.getResponse("https://example.com/data");
const status: number = response.status;
const header: string | undefined = response.headers["content-type"];
```

Storage `get/set` are Hanlin additions around original installed storage. All original `getString/setString/getJSON/setJSON/compareAndSet*/remove/keys/clear` methods still call their native implementation. Missing Hanlin `get` values are null; native JSON reads return JSON objects.

### Native option and result errors appear during authoring

Use the SDK's `scriptwidget/tsconfig.json`. It includes original component types and the service declarations without browser DOM globals. Whole-project validation is strict and checks declaration bodies.

Examples rejected by the real compiler include:

- `$weather.forecast({latitude: "north", longitude: 35})`: latitude must be numeric.
- `$notifications.schedule({key: "daily", title: "Title", body: "Body"})`: either a date or a daily schedule is required.
- `$home.setPower({id: "lamp", on: "yes"})`: on must be Boolean.
- `$health.dailyStatistics({metric: "cpu"})`: the original Health metrics are a finite native set.
- `$http.get(url).catch(...)`: catch is not a native exported method.
- Assigning a nullable music title or native Health reading directly to a non-null value is an error.

Original catalogs contain example payloads. The generator widens sample primitive values and uses verified native refinements for dynamic JSON, missing values, nullable fields, empty collections and strict option schemas. It never infers that a sample username, coordinate or document key is the only permitted value. A newly added native promise method without a reviewed result shape stops declaration generation with an actionable method name.

## Build and repair

Use `get_miniapp_sdk(engine: "scriptwidget")` to find the exact installed declaration and documentation paths, then `write_miniapp`, `validate_miniapp` and `build_miniapp`. The package retains original editable sources. An import with retained TypeScript reruns the real compiler and reports file/line/column diagnostics; an archived success report is not treated as a fresh typecheck.

The `.scripting` extension remains an accepted archive container for existing ScriptWidget widgets. It does not reactivate the frozen Scripting-JSC MiniApp engine.

The main app prepares widget source and resources. WidgetKit uses the installed native renderer and prepared package. A newly adopted native dependency is included by rebuilding the host and its extensions against the matching originals.

## Declaration regeneration and evidence

```bash
node Scripts/MiniApps/generate-scriptwidget-service-types.mjs
node Scripts/MiniApps/generate-scriptwidget-service-types.mjs --check
HANLIN_AUTHORING_TYPESCRIPT=/absolute/path/to/original/typescript/lib/typescript.js \
  node --test Scripts/MiniApps/Tests/scriptwidget-services.test.mjs
```

SDK staging invokes service generation against the actual host source before recording the output digest inventory. Source updates and generated declarations therefore share one build identity. The catalog generator remains separate and preserves the original component catalog.

The focused original TypeScript tests verify every generated native method reference, valid native option/result use and JSX, eleven independently expected consumer errors, and refusal to fabricate a result schema for a newly introduced native method. Portable compiler evidence is separate from the combined Apple runtime/UI acceptance.
