import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";

const repositoryRoot = path.resolve(import.meta.dirname, "../../..");
const swift = fs.readFileSync(path.join(
  repositoryRoot,
  "Packages/HanlinPlatform/Sources/HanlinScriptingApplicationRuntime/HanlinScriptingApplicationSession.swift",
), "utf8");
const marker = `static let bootstrap = #${'"'.repeat(3)}`;
const start = swift.indexOf(marker) + marker.length;
const bootstrap = swift.slice(start, swift.indexOf(`${'"'.repeat(3)}#`, start));

function runtime(entrypointKind = "application", widgetFamily = "systemMedium") {
  const storage = new Map();
  const binaryStorage = new Map();
  const files = new Map();
  let rendered;
  const assistantRequests = [];
  const sqliteRequests = [];
  const locationRequests = [];
  const healthRequests = [];
  const notificationRequests = [];
  const reminderRequests = [];
  const systemUIRequests = [];
  const systemRequests = [];
  const cancelledRequests = new Set();
  const widgetPresentations = [];
  const appIntentRegistrations = [];
  const appIntentCompletions = [];
  const success = value => JSON.stringify({ ok: true, value });
  const failure = (code, message) => JSON.stringify({
    ok: false,
    error: { name: "Error", code, message },
  });
  const fileOperation = (operation, payload) => {
    switch (operation) {
      case "file.createDirectory": return null;
      case "file.writeData": files.set(payload.path, payload.base64); return null;
      case "file.appendData": {
        const previous = Buffer.from(files.get(payload.path) ?? "", "base64");
        const next = Buffer.from(payload.base64, "base64");
        files.set(payload.path, Buffer.concat([previous, next]).toString("base64"));
        return null;
      }
      case "file.readData": {
        if (!files.has(payload.path)) throw new Error("not found");
        return files.get(payload.path);
      }
      case "file.exists": return files.has(payload.path);
      case "file.isFile": return files.has(payload.path);
      case "file.isDirectory": return payload.path === "/documents";
      case "file.isLink": return false;
      case "file.readDirectory": return [...files.keys()].map(value => value.split("/").at(-1));
      case "file.stat": return { creationDate: 0, modificationDate: 0, type: "file", size: Buffer.from(files.get(payload.path), "base64").length };
      case "file.remove": files.delete(payload.path); return null;
      case "file.rename": files.set(payload.newPath, files.get(payload.path)); files.delete(payload.path); return null;
      case "file.copy": files.set(payload.newPath, files.get(payload.path)); return null;
      case "file.mimeType": return "text/plain";
      default: throw new Error(`unsupported ${operation}`);
    }
  };
  const context = vm.createContext({
    console,
    queueMicrotask,
    __hanlinNativeRender(json) { rendered = JSON.parse(json); },
    __hanlinNativeStorageGet(key, shared) {
      if (shared) return JSON.stringify({ allowed: false });
      return JSON.stringify(storage.has(key)
        ? { allowed: true, found: true, json: storage.get(key) }
        : { allowed: true, found: false });
    },
    __hanlinNativeStorageSet(key, json, shared) { if (shared) return false; storage.set(key, json); return true; },
    __hanlinNativeStorageClear() { storage.clear(); binaryStorage.clear(); return true; },
    __hanlinNativeStorageRemove(key, shared) { if (shared) return false; return storage.delete(key) || binaryStorage.delete(key); },
    __hanlinNativeStorageContains(key, shared) { return !shared && (storage.has(key) || binaryStorage.has(key)); },
    __hanlinNativeStorageKeys(shared) { return JSON.stringify(shared ? { allowed: false } : { allowed: true, keys: [...new Set([...storage.keys(), ...binaryStorage.keys()])] }); },
    __hanlinNativeStorageGetData(key, shared) { return JSON.stringify(shared || !binaryStorage.has(key) ? { allowed: !shared, found: false } : { allowed: true, found: true, base64: binaryStorage.get(key) }); },
    __hanlinNativeStorageSetData(key, base64, shared) { if (shared) return false; binaryStorage.set(key, base64); return true; },
    __hanlinNativeFileInfo() { return success({ documentsDirectory: "/documents", appGroupDocumentsDirectory: "/app-group", temporaryDirectory: "/temporary", scriptsDirectory: "/scripts", isiCloudEnabled: false, isWebDAVAvailable: false }); },
    __hanlinNativeFileSync(operation, json) {
      try { return success(fileOperation(operation, JSON.parse(json))); }
      catch (error) { return failure("file_failure", error.message); }
    },
    __hanlinNativeImageJPEG(base64, quality) {
      if (quality < 0 || quality > 1) return failure("invalid_image", "invalid quality");
      return success(base64);
    },
    __hanlinNativeAsync(id, operation, json) {
      queueMicrotask(() => {
        try {
          const payload = JSON.parse(json);
          if (operation.startsWith("sqlite.")) sqliteRequests.push({ operation, payload });
          if (operation.startsWith("location.")) locationRequests.push({ operation, payload });
          if (operation.startsWith("health.")) healthRequests.push({ operation, payload });
          if (operation.startsWith("notification.")) notificationRequests.push({ operation, payload });
          if (operation.startsWith("reminder.")) reminderRequests.push({ operation, payload });
          if (operation.startsWith("documentPicker.") || operation.startsWith("quickLook.") || operation.startsWith("photos.")) systemUIRequests.push({ operation, payload });
          if (operation.startsWith("pasteboard.") || operation.startsWith("safari.")) systemRequests.push({ operation, payload });
          const value = operation === "network.fetch"
            ? { url: payload.url, status: 200, headers: { "content-type": "application/json" }, bodyBase64: Buffer.from('{"ok":true}').toString("base64") }
            : operation === "liveActivity.start"
              ? { activityId: "activity-1" }
            : operation === "liveActivity.update" || operation === "liveActivity.end"
              ? true
            : operation === "liveActivity.areActivitiesEnabled"
              ? true
            : operation === "sqlite.execute"
              ? null
            : operation === "sqlite.fetchAll"
              ? [{ id: payload.arguments[0], title: "stored" }]
            : operation === "location.requestCurrent"
              ? { latitude: 31.7683, longitude: 35.2137, timestamp: 123456789 }
            : operation === "location.reverseGeocode"
              ? [{ location: { latitude: payload.latitude, longitude: payload.longitude, timestamp: 123456789 }, name: "Jerusalem", locality: "Jerusalem", country: "Israel" }]
            : operation === "location.geocodeAddress"
              ? [{ location: { latitude: 31.7683, longitude: 35.2137, timestamp: 123456789 }, name: payload.address, locality: "Jerusalem", country: "Israel" }]
            : operation === "location.setAccuracy"
              ? null
            : operation === "health.queryStatistics"
              ? { quantityType: payload.quantityType, unit: "count", startDate: payload.startDate, endDate: payload.endDate, sum: 8432, average: null }
            : operation === "health.queryActivitySummaries"
              ? [{
                  dateComponents: { year: 2025, month: 10, day: 1 }, activityMoveMode: 1,
                  activeEnergyBurned: 510, activeEnergyBurnedGoal: 600,
                  appleMoveTime: 0, appleMoveTimeGoal: 0,
                  appleExerciseTime: 34, appleExerciseTimeGoal: 30,
                  appleStandHours: 9, appleStandHoursGoal: 12,
                }]
            : operation === "health.queryWorkouts"
              ? [{
                  uuid: "workout-1", workoutActivityType: 37,
                  startDate: payload.startDate, endDate: payload.startDate + 1800000, duration: 1800,
                  allStatistics: {
                    activeEnergyBurned: {
                      quantityType: "activeEnergyBurned", unit: "kcal",
                      startDate: payload.startDate, endDate: payload.startDate + 1800000,
                      sum: 240, average: null,
                    },
                  },
                }]
            : operation === "notification.schedule" || operation === "notification.removeAllPendingsOfCurrentScript"
              ? true
            : operation === "reminder.save"
              ? "eventkit-reminder-id"
            : operation === "documentPicker.pickFiles"
              ? (files.set("/external/source.txt", Buffer.from("selected-content").toString("base64")), ["/external/source.txt"])
            : operation === "documentPicker.pickDirectory"
              ? "/external/folder"
            : operation === "documentPicker.stopAccessingSecurityScopedResources" || operation.startsWith("quickLook.")
              ? null
            : operation === "photos.pickPhotos"
              ? [Buffer.from("selected-photo").toString("base64")]
            : operation === "photos.takePhoto"
              ? Buffer.from("camera-photo").toString("base64")
            : operation === "pasteboard.setString"
              ? (storage.set("pasteboard-string", JSON.stringify(payload.value)), null)
            : operation === "pasteboard.getString"
              ? JSON.parse(storage.get("pasteboard-string") ?? "null")
            : operation === "safari.openURL"
              ? payload.url.startsWith("https://")
            : operation === "runtime.delay"
              ? null
            : fileOperation(operation, payload);
          context.__hanlinResolveNative(id, success(value));
        } catch (error) {
          context.__hanlinResolveNative(id, failure("async_failure", error.message));
        }
      });
    },
    __hanlinNativeAssistantAvailable() { return true; },
    __hanlinNativeAssistantStart(id, json) {
      const request = JSON.parse(json);
      assistantRequests.push(request);
      const chunks = request.kind === "structured_data"
        ? [{ type: "structured", content: { answer: "verified", count: request.images.length } }]
        : [
            { type: "text", content: "Hello " },
            { type: "reasoning", content: "checked" },
            { type: "text", content: "world" },
            { type: "usage", content: { totalCost: null, cacheReadTokens: null, cacheWriteTokens: null, inputTokens: 3, outputTokens: 2 } },
          ];
      const emit = () => {
        if (cancelledRequests.has(id)) return;
        const chunk = chunks.shift();
        context.__hanlinAssistantReceive(id, success(chunk ?? null));
        if (chunk) queueMicrotask(emit);
      };
      queueMicrotask(emit);
    },
    __hanlinCancelNative(id) { cancelledRequests.add(id); },
    __hanlinNativeDeviceSnapshot: {
      model: "iPad", localizedModel: "iPad", systemVersion: "26.5", systemName: "iPadOS",
      isiPad: true, isiPhone: false, screen: { width: 744, height: 1133, scale: 2 },
      batteryState: "charging", batteryLevel: 0.75, proximityState: false,
      orientation: "landscapeRight", isLandscape: true, isPortrait: false, isFlat: false,
      colorScheme: "dark", isiOSAppOnMac: false, systemLocale: "he_IL",
      preferredLanguages: ["he-IL", "en-US"], systemLocales: ["he-IL", "en-US"],
      systemLanguageTag: "he-IL", systemLanguageCode: "he", systemCountryCode: "IL",
      systemScriptCode: "Hebr",
    },
    __hanlinNativeHealthDataAvailable: true,
    __hanlinNativeEntrypointKind: entrypointKind,
    __hanlinNativeWidgetFamily: widgetFamily,
    __hanlinNativeWidgetParameter: "daily",
    __hanlinNativeWidgetPresent(json) { widgetPresentations.push(JSON.parse(json)); return true; },
    __hanlinNativeWidgetReloadAll() {},
    __hanlinNativeAppIntentRegister(json) { appIntentRegistrations.push(JSON.parse(json)); return true; },
    __hanlinNativeAppIntentComplete(id, succeeded, json) { appIntentCompletions.push({ id, succeeded, json }); },
  });
  vm.runInContext(bootstrap, context, { filename: "hanlin-scripting-ui-runtime.js" });
  return {
    context, rendered: () => rendered, assistantRequests, sqliteRequests, locationRequests,
    healthRequests, notificationRequests, reminderRequests, systemUIRequests, systemRequests, cancelledRequests, widgetPresentations,
    appIntentRegistrations, appIntentCompletions,
  };
}

test("Smart-eating Widget and App Intent entrypoints preserve family, parameters, and execution", async () => {
  const widget = runtime("widget", "systemLarge");
  vm.runInContext(`
    const CompleteStationIntent = AppIntentManager.register({
      name: "CompleteStationIntent", protocol: AppIntentProtocol.AppIntent,
      perform: async params => params.stationId,
    });
    Widget.present(createElement(Button, { intent: CompleteStationIntent({ stationId: 7 }) },
      createElement(Text, null, Widget.family)), { policy: "after", date: new Date(1800000) });
  `, widget.context);
  assert.equal(widget.widgetPresentations[0].root.kind, "button");
  assert.equal(widget.widgetPresentations[0].root.properties.intent.name, "CompleteStationIntent");
  assert.deepEqual(widget.widgetPresentations[0].root.properties.intent.parameters, { stationId: 7 });
  assert.equal(widget.widgetPresentations[0].reloadDate, 1800000);

  const appIntent = runtime("appIntent");
  vm.runInContext(`
    AppIntentManager.register({
      name: "CompleteStationIntent", protocol: AppIntentProtocol.AppIntent,
      perform: async params => ({ completed: params.stationId }),
    });
    __hanlinInvokeAppIntent("request-1", "CompleteStationIntent", '{"stationId":7}');
  `, appIntent.context);
  await new Promise(resolve => queueMicrotask(resolve));
  await new Promise(resolve => queueMicrotask(resolve));
  assert.deepEqual(appIntent.appIntentRegistrations, [{ name: "CompleteStationIntent", protocol: "AppIntent" }]);
  assert.deepEqual(appIntent.appIntentCompletions, [{
    id: "request-1", succeeded: true, json: '{"completed":7}',
  }]);
});

test("FileManager and nativ-ai use native Pasteboard and Safari primitives", async () => {
  const { context, systemRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      await Pasteboard.setString("/documents/report.txt");
      return [await Pasteboard.getString(), await Safari.openURL("https://example.com/settings")];
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), ["/documents/report.txt", true]);
  assert.deepEqual(systemRequests, [
    { operation: "pasteboard.setString", payload: { value: "/documents/report.txt" } },
    { operation: "pasteboard.getString", payload: {} },
    { operation: "safari.openURL", payload: { url: "https://example.com/settings" } },
  ]);
});

test("nativ-ai creates a Reminder with DateComponents and receives its identifier", async () => {
  const { context, reminderRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const reminder = new Reminder();
      reminder.title = "Take medicine";
      reminder.notes = "After dinner";
      reminder.dueDateComponents = new DateComponents({
        year: 2027, month: 2, day: 3, hour: 18, minute: 45
      });
      reminder.priority = 1;
      await reminder.save();
      return { ok: true, identifier: reminder.identifier };
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), {
    ok: true, identifier: "eventkit-reminder-id",
  });
  assert.deepEqual(reminderRequests, [{
    operation: "reminder.save",
    payload: {
      title: "Take medicine", notes: "After dinner", priority: 1,
      dueDateComponents: { year: 2027, month: 2, day: 3, hour: 18, minute: 45 },
    },
  }]);
});

test("FileManager imports DocumentPicker files and opens its package copy in QuickLook", async () => {
  const { context, systemUIRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const selected = await DocumentPicker.pickFiles({
        allowsMultipleSelection: true, shouldShowFileExtensions: true, types: ["public.text"]
      });
      const destination = Path.join(FileManager.documentsDirectory, "imported.txt");
      await FileManager.copyFile(selected[0], destination);
      const directory = await DocumentPicker.pickDirectory();
      await QuickLook.previewURLs([encodeURI(destination)]);
      const imagePath = Path.join(FileManager.documentsDirectory, "preview.jpg");
      FileManager.writeAsDataSync(imagePath, Data.fromIntArray([255, 216, 1, 255, 217]));
      await QuickLook.previewImage(UIImage.fromFile(imagePath));
      await QuickLook.previewText("selected-content");
      DocumentPicker.stopAcessingSecurityScopedResources();
      return [await FileManager.readAsString(destination), directory];
    })()
  `, context);
  await new Promise(resolve => queueMicrotask(resolve));
  assert.deepEqual(JSON.parse(JSON.stringify(result)), ["selected-content", "/external/folder"]);
  assert.deepEqual(systemUIRequests, [
    { operation: "documentPicker.pickFiles", payload: {
      allowsMultipleSelection: true, shouldShowFileExtensions: true, types: ["public.text"],
    } },
    { operation: "documentPicker.pickDirectory", payload: { initialDirectory: null } },
    { operation: "quickLook.previewURLs", payload: { urls: ["/documents/imported.txt"], fullscreen: false } },
    { operation: "quickLook.previewImage", payload: { base64: "/9gB/9k=", fullscreen: false } },
    { operation: "quickLook.previewText", payload: { text: "selected-content", fullscreen: false } },
    { operation: "documentPicker.stopAccessingSecurityScopedResources", payload: {} },
  ]);
});

test("nativ-ai photo picker and camera values encode through UIImage and Data.fromJPEG", async () => {
  const { context, systemUIRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const photos = await Photos.pickPhotos(8);
      const selected = Data.fromJPEG(photos[0], 0.82);
      const camera = await Photos.takePhoto();
      const captured = Data.fromJPEG(camera, 0.88);
      return [photos.length, selected.toRawString("ascii"), captured.toRawString("ascii")];
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), [1, "selected-photo", "camera-photo"]);
  assert.deepEqual(systemUIRequests, [
    { operation: "photos.pickPhotos", payload: { count: 8 } },
    { operation: "photos.takePhoto", payload: {} },
  ]);
});

test("Device exposes the immutable native launch snapshot", () => {
  const { context } = runtime();
  const result = vm.runInContext(`JSON.stringify([
    Device.model, Device.systemName, Device.screen.width, Device.batteryState,
    Device.orientation, Device.colorScheme, Device.systemLanguageCode,
    Device.systemCountryCode, Device.isLandscape, Device.isPortrait,
    Object.isFrozen(Device), Object.isFrozen(Device.screen),
    Object.isFrozen(Device.preferredLanguages)
  ])`, context);
  assert.equal(result, '["iPad","iPadOS",744,"charging","landscapeRight","dark","he","IL",true,false,true,true,true]');
});

test("Path, binary Data, Storage, and synchronous FileManager preserve values", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    Storage.clear();
    Storage.set("record", { count: 3 });
    Storage.setData("bytes", Data.fromIntArray([0, 127, 255]));
    const file = Path.join(FileManager.documentsDirectory, "nested", "note.txt");
    FileManager.writeAsStringSync(file, "שלום");
    FileManager.appendTextSync(file, "!");
    const valid = Path.basename(file) === "note.txt"
      && Path.dirname(file) === "/documents/nested"
      && FileManager.existsSync(file)
      && FileManager.readAsStringSync(file) === "שלום!"
      && Storage.get("record").count === 3
      && Storage.getData("bytes").toHexString() === "007fff"
      && Storage.contains("record")
      && Storage.keys().includes("bytes");
    Navigation.present({ element: createElement(Text, null, String(valid)) });
  `, context);
  assert.equal(rendered().properties.text, "true");
});

test("FileManager promises and fetch resolve through the native callback channel", async () => {
  const { context, rendered } = runtime();
  await vm.runInContext(`
    (async () => {
      const file = Path.join(FileManager.documentsDirectory, "async.txt");
      await FileManager.writeAsString(file, "bridge");
      const text = await FileManager.readAsString(file);
      const response = await fetch("https://example.test/value");
      const body = await response.json();
      Navigation.present({ element: createElement(Text, null, text + ":" + response.status + ":" + body.ok) });
    })()
  `, context);
  assert.equal(rendered().properties.text, "bridge:200:true");
});

test("AbortController rejects before dispatch and disposal cancels pending native requests", async () => {
  const { context } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const controller = new AbortController();
      controller.abort();
      try { await fetch("https://example.test", { signal: controller.signal }); }
      catch (error) { return error.name; }
      return "unexpected";
    })()
  `, context);
  assert.equal(result, "AbortError");
  const timeoutName = await vm.runInContext(`
    (async () => {
      const signal = AbortSignal.timeout(0);
      await new Promise(resolve => signal.addEventListener("abort", resolve));
      return signal.reason.name;
    })()
  `, context);
  assert.equal(timeoutName, "TimeoutError");
  assert.doesNotThrow(() => context.__hanlinDispose());
});

test("Assistant streams ordered text, reasoning, and usage chunks through the native channel", async () => {
  const { context, assistantRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const stream = await Assistant.requestStreaming({
        systemPrompt: "Be concise",
        messages: [{ role: "user", content: "Greet me" }],
        provider: { custom: "https://assistant.example/v1" },
        modelId: "test-model",
      });
      const chunks = [];
      for await (const chunk of stream) chunks.push(chunk);
      return JSON.stringify(chunks);
    })()
  `, context);
  const chunks = JSON.parse(result);
  assert.deepEqual(chunks.map(chunk => chunk.type), ["text", "reasoning", "text", "usage"]);
  assert.equal(chunks.filter(chunk => chunk.type === "text").map(chunk => chunk.content).join(""), "Hello world");
  assert.equal(chunks.at(-1).content.outputTokens, 2);
  assert.deepEqual(assistantRequests[0].provider, { custom: "https://assistant.example/v1" });
  assert.equal(assistantRequests[0].modelId, "test-model");
});

test("Assistant structured requests preserve schemas and image overloads", async () => {
  const { context, assistantRequests } = runtime();
  const result = await vm.runInContext(`
    Assistant.requestStructuredData(
      "Inspect",
      ["data:image/png;base64,AA=="],
      {
        type: "object",
        description: "Result",
        properties: {
          answer: { type: "string", description: "Answer" },
          count: { type: "number", description: "Image count" },
        },
      },
      { provider: "openai" },
    )
  `, context);
  assert.equal(JSON.stringify(result), JSON.stringify({ answer: "verified", count: 1 }));
  assert.equal(assistantRequests[0].kind, "structured_data");
  assert.equal(assistantRequests[0].provider, "openai");
  assert.equal(assistantRequests[0].schema.properties.answer.type, "string");
});

test("Breaking Assistant iteration cancels native work and malformed input never dispatches", async () => {
  const { context, assistantRequests, cancelledRequests } = runtime();
  const requestID = await vm.runInContext(`
    (async () => {
      const stream = await Assistant.requestStreaming({ messages: { role: "user", content: "Stop" } });
      const id = stream.id;
      for await (const chunk of stream) { if (chunk.type === "text") break; }
      return id;
    })()
  `, context);
  assert.equal(cancelledRequests.has(requestID), true);
  await assert.rejects(
    vm.runInContext(`Assistant.requestStreaming({ messages: { role: "system", content: "bad" } })`, context),
    /message role/,
  );
  assert.equal(assistantRequests.length, 1);
  assert.doesNotThrow(() => context.__hanlinDispose());
});

test("NavigationStack materializes dynamic destinations and sends native back to its observable path", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    const navigationPath = useObservable(["/documents/folder"]);
    const destination = createElement(
      NavigationDestination,
      null,
      page => createElement(Text, null, "Destination:" + page),
    );
    Navigation.present({ element: createElement(
      NavigationStack,
      { path: navigationPath },
      createElement(VStack, { navigationDestination: destination }, createElement(Text, null, "Root")),
    ) });
  `, context);

  const root = rendered();
  const stack = root.kind === "navigationStack"
    ? root
    : root.children.find(node => node.kind === "navigationStack");
  const route = root.children.find(node => node.kind === "navigationDestination");
  assert.deepEqual(stack.properties.path, ["/documents/folder"]);
  assert.equal(route.properties.route, "/documents/folder");
  assert.equal(route.children[0].properties.text, "Destination:/documents/folder");

  context.__hanlinDispatch(stack.properties.onPathChange, "[]");
  const updatedRoot = rendered();
  const updatedStack = updatedRoot.kind === "navigationStack"
    ? updatedRoot
    : updatedRoot.children.find(node => node.kind === "navigationStack");
  assert.deepEqual(updatedStack.properties.path, []);
});

test("Form, Label, Markdown, ControlGroup, ScrollView, Group, and Picker retain interactive semantics", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    const selection = useObservable("he");
    Navigation.present({ element: createElement(Form, { navigationTitle: "Preferences" },
      createElement(Group, null,
        createElement(Label, { title: "Language", systemImage: "globe" }),
        createElement(Picker, { title: "Language", value: selection },
          createElement(Text, { tag: "en" }, "English"),
          createElement(Text, { tag: "he" }, "Hebrew"),
        ),
        createElement(ControlGroup, null, createElement(Button, { title: "Done" })),
        createElement(ScrollView, null, createElement(Markdown, { content: "**Ready**" })),
        createElement(SVG, { code: '<svg xmlns="http://www.w3.org/2000/svg"><circle r="4"/></svg>' }),
      ),
    ) });
  `, context);

  const form = rendered();
  assert.equal(form.kind, "form");
  const group = form.children[0];
  assert.deepEqual(group.children.map(node => node.kind), [
    "label", "picker", "controlGroup", "scrollView", "svg",
  ]);
  const picker = group.children[1];
  assert.equal(picker.properties.value, "he");
  context.__hanlinDispatch(picker.properties.onChange, '\"en\"');
  assert.equal(rendered().children[0].children[1].properties.value, "en");
  assert.equal(group.children[3].children[0].properties.content, "**Ready**");
  assert.match(group.children[4].properties.code, /^<svg/);
});

test("ContentUnavailableView, DisclosureGroup, Slider, and LazyVGrid preserve native semantics", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    const expanded = useObservable(false);
    const amount = useObservable(18);
    Navigation.present({ element: createElement(VStack, null,
      createElement(ContentUnavailableView, {
        label: createElement(Label, { title: "No results", systemImage: "magnifyingglass" }),
        description: createElement(Text, null, "Try another query"),
        actions: [createElement(Button, { title: "Retry" })],
      }),
      createElement(DisclosureGroup, { title: "Details", isExpanded: expanded },
        createElement(Text, null, "Expanded content"),
      ),
      createElement(Slider, { value: amount, min: 12, max: 36, step: 1 }),
      createElement(LazyVGrid, {
        columns: [{ size: { type: "flexible" } }, { size: { type: "fixed", value: 80 } }],
        spacing: 8,
      }, createElement(Text, null, "Cell")),
    ) });
  `, context);

  let root = rendered();
  assert.deepEqual(root.children.map(node => node.kind), [
    "contentUnavailableView", "disclosureGroup", "slider", "lazyVGrid",
  ]);
  const unavailable = root.children[0];
  assert.deepEqual(
    [unavailable.properties.labelCount, unavailable.properties.descriptionCount, unavailable.properties.actionCount],
    [1, 1, 1],
  );
  assert.deepEqual(unavailable.children.map(node => node.kind), ["label", "text", "button"]);
  assert.equal(root.children[1].properties.isExpanded, false);
  context.__hanlinDispatch(root.children[1].properties.onChange, "true");
  root = rendered();
  assert.equal(root.children[1].properties.isExpanded, true);
  assert.equal(root.children[2].properties.value, 18);
  context.__hanlinDispatch(root.children[2].properties.onChange, "24");
  root = rendered();
  assert.equal(root.children[2].properties.value, 24);
  assert.equal(root.children[3].properties.columns.length, 2);
});

test("NavigationSplitView bindings and ScrollViewReader proxy round-trip through native properties", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    const visibility = useObservable("all");
    const compactColumn = useObservable("detail");
    const reader = useRef(null);
    Navigation.present({ element: createElement(NavigationSplitView, {
      columnVisibility: visibility,
      preferredCompactColumn: compactColumn,
      sidebar: createElement(Text, null, "Sidebar"),
      content: createElement(Text, null, "Content"),
    }, createElement(ScrollViewReader, null, proxy => {
      reader.current = proxy;
      return createElement(ScrollView, null, createElement(Text, { id: "segment-7" }, "Detail"));
    })) });
    reader.current.scrollTo("segment-7", "center");
  `, context);

  let root = rendered();
  assert.equal(root.kind, "navigationSplitView");
  assert.equal(root.properties.sidebarCount, 1);
  assert.equal(root.properties.contentCount, 1);
  assert.equal(root.properties.columnVisibility, "all");
  const reader = root.children[2];
  assert.equal(reader.kind, "scrollViewReader");
  assert.equal(reader.properties.scrollTarget, "segment-7");
  assert.equal(reader.properties.scrollAnchor, "center");
  assert.equal(reader.children[0].children[0].properties.id, "segment-7");

  context.__hanlinDispatch(root.properties.onColumnVisibilityChange, '"detailOnly"');
  context.__hanlinDispatch(root.properties.onPreferredCompactColumnChange, '"sidebar"');
  root = rendered();
  assert.equal(root.properties.columnVisibility, "detailOnly");
  assert.equal(root.properties.preferredCompactColumn, "sidebar");
});

test("Observable subscribers receive changes and can unsubscribe without affecting rendering", () => {
  const { context } = runtime();
  const values = vm.runInContext(`
    (() => {
      const received = [];
      let observable;
      function App() {
        observable = useObservable(1);
        return createElement(Text, null, String(observable.value));
      }
      Navigation.present({ element: createElement(App) });
      const subscriber = value => received.push(value);
      observable.subscribe(subscriber);
      observable.setValue(2);
      observable.unsubscribe(subscriber);
      observable.setValue(3);
      return received;
    })()
  `, context);
  assert.deepEqual([...values], [2]);
});

test("useReducer keeps state and Link retains its native URL destination", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    let dispatch;
    function App() {
      const [count, send] = useReducer((state, action) => state + action, 2, value => value * 2);
      dispatch = send;
      return createElement(Link, { url: "https://example.test/item" }, "Count:" + count);
    }
    Navigation.present({ element: createElement(App) });
  `, context);
  assert.equal(rendered().kind, "link");
  assert.equal(rendered().properties.url, "https://example.test/item");
  assert.equal(rendered().children[0].properties.text, "Count:4");
  vm.runInContext("dispatch(3)", context);
  assert.equal(rendered().children[0].properties.text, "Count:7");
});

test("GroupBox keeps its label separate and Capsule remains a native shape", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    Navigation.present({ element: createElement(GroupBox, {
      label: createElement(Label, { title: "Summary", systemImage: "info.circle" }),
    }, createElement(Capsule, { fill: "systemBlue", frame: { width: 80, height: 24 } })) });
  `, context);
  const root = rendered();
  assert.equal(root.kind, "groupBox");
  assert.equal(root.properties.labelCount, 1);
  assert.deepEqual(root.children.map(node => node.kind), ["label", "capsule"]);
});

test("LiveActivityUI preserves lock-screen and every Dynamic Island region", () => {
  const { context, rendered } = runtime();
  vm.runInContext(`
    Navigation.present({ element: createElement(LiveActivityUI, {
      content: createElement(Text, null, "lock"),
      compactLeading: createElement(Text, null, "compact-leading"),
      compactTrailing: createElement(Text, null, "compact-trailing"),
      minimal: createElement(Image, { systemName: "sparkles" }),
    },
      createElement(LiveActivityUIExpandedLeading, null, createElement(Text, null, "expanded-leading")),
      createElement(LiveActivityUIExpandedTrailing, null, createElement(Text, null, "expanded-trailing")),
      createElement(LiveActivityUIExpandedCenter, null, createElement(Text, null, "expanded-center")),
      createElement(LiveActivityUIExpandedBottom, null, createElement(Text, null, "expanded-bottom")),
    ) });
  `, context);
  const root = rendered();
  assert.equal(root.kind, "liveActivityUI");
  assert.deepEqual(root.children.map(node => node.kind), [
    "liveActivityContent", "liveActivityCompactLeading", "liveActivityCompactTrailing",
    "liveActivityMinimal", "liveActivityExpandedLeading", "liveActivityExpandedTrailing",
    "liveActivityExpandedCenter", "liveActivityExpandedBottom",
  ]);
  assert.equal(root.children[0].children[0].properties.text, "lock");
  assert.equal(root.children[3].children[0].properties.systemName, "sparkles");
  assert.equal(root.children[7].children[0].properties.text, "expanded-bottom");
});

test("LiveActivity register, start, update, listeners, and end use the native lifecycle", async () => {
  const { context } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const makeActivity = LiveActivity.register("demo", state => createElement(LiveActivityUI, {
        content: createElement(Text, null, state.title),
        compactLeading: createElement(Text, null, "L"),
        compactTrailing: createElement(Text, null, "T"),
        minimal: createElement(Text, null, "M"),
      }, createElement(LiveActivityUIExpandedCenter, null, createElement(Text, null, "C"))));
      const activity = makeActivity();
      const states = [];
      activity.addUpdateListener(state => states.push(state));
      const started = await activity.start({ title: "one" }, { staleDate: 1000, relevanceScore: 1 });
      const updated = await activity.update({ title: "two" });
      const ended = await activity.end({ title: "done" }, { dismissTimeInterval: 0 });
      return { started, updated, ended, id: activity.activityId, active: activity.started, states };
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), {
    started: true, updated: true, ended: true, id: "activity-1", active: false,
    states: ["active", "active", "ended"],
  });
});

test("SQLite preserves package paths, configurations, bound arguments, and row objects", async () => {
  const { context, sqliteRequests } = runtime();
  const rows = await vm.runInContext(`
    (async () => {
      const database = SQLite.open(Path.join(FileManager.appGroupDocumentsDirectory, "history.sqlite"), {
        foreignKeysEnabled: true, journalMode: "wal", busyMode: 5, maximumReaderCount: 4,
      });
      await database.execute("CREATE TABLE items (id TEXT, title TEXT)");
      await database.execute("INSERT INTO items VALUES (?, ?)", ["item-1", "stored"]);
      return database.fetchAll("SELECT * FROM items WHERE id = ?", ["item-1"]);
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(rows)), [{ id: "item-1", title: "stored" }]);
  assert.equal(sqliteRequests.length, 3);
  assert.equal(sqliteRequests[0].payload.path, "/app-group/history.sqlite");
  assert.equal(sqliteRequests[0].payload.configuration.foreignKeysEnabled, true);
  assert.equal(sqliteRequests[0].payload.configuration.journalMode, "wal");
  assert.deepEqual(sqliteRequests[2].payload.arguments, ["item-1"]);
});

test("Location current position, accuracy, and modern geocoding use the native async channel", async () => {
  const { context, locationRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      await Location.setAccuracy("hundredMeters");
      const current = await Location.requestCurrent({ forceRequest: true });
      const reverse = await Location.reverseGeocode({
        latitude: current.latitude,
        longitude: current.longitude,
        locale: "he_IL",
      });
      const forward = await Location.geocodeAddress({ address: "Jerusalem", locale: "en_US" });
      return { accuracy: Location.accuracy, current, reverse, forward };
    })()
  `, context);
  const value = JSON.parse(JSON.stringify(result));
  assert.equal(value.accuracy, "hundredMeters");
  assert.deepEqual(value.current, { latitude: 31.7683, longitude: 35.2137, timestamp: 123456789 });
  assert.equal(value.reverse[0].locality, "Jerusalem");
  assert.equal(value.forward[0].name, "Jerusalem");
  assert.deepEqual(locationRequests.map(request => request.operation), [
    "location.setAccuracy", "location.requestCurrent", "location.reverseGeocode", "location.geocodeAddress",
  ]);
  assert.equal(locationRequests[1].payload.forceRequest, true);
  assert.equal(locationRequests[2].payload.locale, "he_IL");
});

test("Smart-eating Health statistics and recurring notifications preserve Scripting payloads", async () => {
  const { context, healthRequests, notificationRequests } = runtime();
  const result = await vm.runInContext(`
    (async () => {
      const statistics = await Health.queryStatistics("stepCount", {
        startDate: new Date("2025-10-01T00:00:00Z"),
        endDate: new Date("2025-10-01T23:59:59Z"),
        statisticsOptions: ["cumulativeSum"],
      });
      const components = new DateComponents({ hour: 8, minute: 15 });
      const scheduled = await Notification.schedule({
        title: "Breakfast",
        interruptionLevel: "timeSensitive",
        trigger: new CalendarNotificationTrigger({ dateMatching: components, repeats: true }),
      });
      const activity = await Health.queryActivitySummaries({
        start: DateComponents.fromDate(new Date("2025-10-01T12:00:00Z")),
        end: DateComponents.fromDate(new Date("2025-10-01T12:00:00Z")),
      });
      const workouts = await Health.queryWorkouts({
        startDate: new Date("2025-10-01T00:00:00Z"),
        endDate: new Date("2025-10-01T23:59:59Z"),
        sortDescriptors: [{ key: "startDate", order: "reverse" }],
      });
      await Notification.removeAllPendingsOfCurrentScript();
      return {
        available: Health.isHealthDataAvailable,
        steps: statistics.sumQuantity(HealthUnit.count()),
        exercise: activity[0].appleExerciseTime(HealthUnit.minute()),
        workoutDuration: workouts[0].duration,
        calories: workouts[0].allStatistics.activeEnergyBurned.sumQuantity(HealthUnit.kilocalorie()),
        scheduled,
      };
    })()
  `, context);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), {
    available: true, steps: 8432, exercise: 34, workoutDuration: 1800, calories: 240, scheduled: true,
  });
  assert.equal(healthRequests[0].operation, "health.queryStatistics");
  assert.deepEqual(healthRequests[0].payload.statisticsOptions, ["cumulativeSum"]);
  assert.equal(healthRequests[1].operation, "health.queryActivitySummaries");
  assert.equal(healthRequests[2].operation, "health.queryWorkouts");
  assert.equal(healthRequests[2].payload.sortDescriptors[0].order, "reverse");
  assert.equal(notificationRequests[0].operation, "notification.schedule");
  assert.deepEqual(notificationRequests[0].payload.trigger, {
    type: "calendar", dateMatching: { hour: 8, minute: 15 }, repeats: true,
  });
  assert.equal(notificationRequests[1].operation, "notification.removeAllPendingsOfCurrentScript");
});
