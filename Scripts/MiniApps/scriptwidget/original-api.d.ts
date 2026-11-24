// Generated from installed original Swift JSExport signatures and original editor catalogs.
// Run Scripts/MiniApps/generate-scriptwidget-service-types.mjs; do not edit.
/// <reference path="./components.d.ts" />
/// <reference path="./service-types.d.ts" />

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeAlarms.swift */
declare const $alarms: {
  /** Original catalog: $alarms.status; runtime 1.6. */
  status(): ScriptWidgetNativePromise<{"authorization": string}>;
  /** Original catalog: $alarms.pending; runtime 1.6. */
  pending(): ScriptWidgetNativePromise<{key: string; state: string}[]>;
  /** Original catalog: $alarms.schedule; runtime 1.6. */
  schedule(options: ScriptWidgetAlarmOptions): ScriptWidgetNativePromise<{"key": string; "status": string; "replayed": boolean}>;
  /** Original catalog: $alarms.cancel; runtime 1.6. */
  cancel(key: string): ScriptWidgetNativePromise<{"key": string; "status": string}>;
  /** Original catalog: $alarms.stop; runtime 1.6. */
  stop(key: string): ScriptWidgetNativePromise<{"key": string; "status": string}>;
  /** Original catalog: $alarms.pause; runtime 1.6. */
  pause(key: string): ScriptWidgetNativePromise<{"key": string; "status": string}>;
  /** Original catalog: $alarms.resume; runtime 1.6. */
  resume(key: string): ScriptWidgetNativePromise<{"key": string; "status": string}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeCalendar.swift */
declare const $calendar: {
  /** Original catalog: $calendar.isAvailable; runtime 1.3. */
  isAvailable(): boolean;
  /** Original catalog: $calendar.authorizationStatus; runtime 1.3. */
  authorizationStatus(): string;
  /** Original catalog: $calendar.requestAuthorization; runtime 1.3. */
  requestAuthorization(): ScriptWidgetNativePromise<boolean>;
  /** Original catalog: $calendar.calendars; runtime 1.3. */
  calendars(): ScriptWidgetNativePromise<({"id": string; "title": string})[]>;
  /** Original catalog: $calendar.create; runtime 1.6. */
  create(options: ScriptWidgetCalendarMutation): ScriptWidgetNativePromise<{"id": string; "calendarID": string; "status": string; "replayed": boolean}>;
  /** Original catalog: $calendar.update; runtime 1.6. */
  update(options: ScriptWidgetCalendarUpdate): ScriptWidgetNativePromise<{"id": string; "calendarID": string; "status": string; "replayed": boolean}>;
  /** Original catalog: $calendar.events; runtime 1.3. */
  events(options?: ScriptWidgetCalendarQuery): ScriptWidgetNativePromise<ScriptWidgetNativeList<ScriptWidgetCalendarEvent> & {truncated: boolean}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeConsole.swift */
declare const $console: {
  log(string: string): void;
  error(string: string): void;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeContacts.swift */
declare const $contacts: {
  /** Original catalog: $contacts.selected; runtime 1.6. */
  selected(): ScriptWidgetNativePromise<({"id": string; "name": string; "organization": string; "phones": (string)[]; "emails": (string)[]})[]>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Plugin/ScriptWidgetDataSources.swift */
declare const $dataSource: {
  request(pluginID: string, operationID: string, parameters?: ScriptWidgetJSONObject): ScriptWidgetNativePromise<ScriptWidgetJSON>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeDevice.swift */
declare const $device: {
  /** Original catalog: $device.screen; runtime 1.0. */
  screen(): {"width": number; "height": number; "scale": number};
  /** Original catalog: $device.language; runtime 1.0. */
  language(): string;
  /** Original catalog: $device.model; runtime 1.0. */
  model(): string;
  /** Original catalog: $device.name; runtime 1.0. */
  name(): string;
  /** Original catalog: $device.battery; runtime 1.0. */
  battery(): {"level": number; "state": string};
  /** Original catalog: $device.systemVersion; runtime 1.0. */
  systemVersion(): string;
  /** Original catalog: $device.isdarkmode; runtime 1.0. */
  isdarkmode(): boolean;
  /** Original catalog: $device.totalDiskSpace; runtime 1.0. */
  totalDiskSpace(): number;
  /** Original catalog: $device.freeDiskSpace; runtime 1.0. */
  freeDiskSpace(): number;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeDocuments.swift */
declare const $documents: {
  /** Original catalog: $documents.list; runtime 1.6. */
  list(): ScriptWidgetNativePromise<({"id": string; "name": string; "type": string; "bytes": number})[]>;
  /** Original catalog: $documents.readJSON; runtime 1.6. */
  readJSON(id: string): ScriptWidgetNativePromise<ScriptWidgetJSONObject | ScriptWidgetJSON[]>;
  /** Original catalog: $documents.readCSV; runtime 1.6. */
  readCSV(id: string): ScriptWidgetNativePromise<{"headers": (string)[]; "rows": ((string)[])[]; "truncated": boolean}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/Component/ScriptWidgetRuntimeElement.swift */
declare const $element: {
  createElement(tag: string | ((props: Record<string, unknown>) => JSX.Element), props: Record<string, unknown> | null, children: JSX.Child[] | null): JSX.Element;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeFile.swift */
declare const $file: {
  exists(relativePath: string): boolean;
  read(relativePath: string): string;
  readJSON(relativePath: string): ScriptWidgetJSONObject;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeHealth.swift */
declare const $health: {
  /** Original catalog: $health.isAvailable; runtime 1.0. */
  isAvailable(): boolean;
  /** Original catalog: $health.authorizationStatus; runtime 1.3. */
  authorizationStatus(): string;
  /** Original catalog: $health.requestAuthorization; runtime 1.0. */
  requestAuthorization(): ScriptWidgetNativePromise<boolean>;
  /** Original catalog: $health.stepCountToday; runtime 1.0. */
  stepCountToday(): ScriptWidgetNativePromise<ScriptWidgetHealthMeasurement>;
  /** Original catalog: $health.activeEnergyToday; runtime 1.0. */
  activeEnergyToday(): ScriptWidgetNativePromise<ScriptWidgetHealthMeasurement>;
  /** Original catalog: $health.heartRateLatest; runtime 1.0. */
  heartRateLatest(): ScriptWidgetNativePromise<ScriptWidgetHealthMeasurement>;
  /** Original catalog: $health.sleepSummary; runtime 1.4. */
  sleepSummary(options?: ScriptWidgetHealthWindow): ScriptWidgetNativePromise<{"start": string; "end": string; "timeZone": string; "hasSamples": boolean; "totalSleepSeconds": number; "inBedSeconds": number; "awakeSeconds": number; "stages": {"unspecified": number; "core": number; "deep": number; "rem": number}; "sourceCount": number; "truncated": boolean; "conflictSeconds": number; "aggregation": string}>;
  /** Original catalog: $health.activitySummary; runtime 1.4. */
  activitySummary(options?: {date?: string}): ScriptWidgetNativePromise<ScriptWidgetHealthActivity>;
  /** Original catalog: $health.workouts; runtime 1.4. */
  workouts(options?: ScriptWidgetHealthWorkoutsQuery): ScriptWidgetNativePromise<ScriptWidgetHealthWorkouts>;
  /** Original catalog: $health.dailyStatistics; runtime 1.6. */
  dailyStatistics(options: ScriptWidgetHealthDailyQuery): ScriptWidgetNativePromise<ScriptWidgetHealthDailyStatistics>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeHome.swift */
declare const $home: {
  /** Original catalog: $home.items; runtime 1.6. */
  items(): ScriptWidgetNativePromise<{id: string; name: string; kind: string; value: ScriptWidgetJSON; isCached: boolean; metric: string; unit: string}[]>;
  /** Original catalog: $home.setPower; runtime 1.6. */
  setPower(options: {id: string; on: boolean}): ScriptWidgetNativePromise<{"id": string; "value": boolean; "status": string}>;
  /** Original catalog: $home.runScene; runtime 1.6. */
  runScene(options: {id: string; requestID: string}): ScriptWidgetNativePromise<{"id": string; "status": string; "replayed": boolean}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeFetch.swift */
declare const $http: {
  get(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
  getResponse(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<ScriptWidgetHTTPResponse>;
  post(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
  put(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
  patch(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
  delete(url: string, params?: ScriptWidgetHTTPOptions): ScriptWidgetNativePromise<string>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeCloudJSON.swift */
declare const $icloud: {
  readJSON(name: string): ScriptWidgetNativePromise<ScriptWidgetCloudJSONDocument>;
  writeJSON(name: string, value: ScriptWidgetJSONObject, expectedRevision: string): ScriptWidgetNativePromise<ScriptWidgetCloudJSONDocument>;
  resolveJSON(name: string, value: ScriptWidgetJSONObject, expectedRevision: string): ScriptWidgetNativePromise<ScriptWidgetCloudJSONDocument>;
  sync(): ScriptWidgetNativePromise<ScriptWidgetCloudJSONSync>;
  status(): ScriptWidgetNativePromise<ScriptWidgetCloudJSONStatus>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeLocation.swift */
declare const $location: {
  /** Original catalog: $location.isAvailable; runtime 1.0. */
  isAvailable(): boolean;
  /** Original catalog: $location.authorizationStatus; runtime 1.0. */
  authorizationStatus(): string;
  /** Original catalog: $location.isAuthorizedForWidgetUpdates; runtime 1.3. */
  isAuthorizedForWidgetUpdates(): boolean;
  /** Original catalog: $location.requestAuthorization; runtime 1.0. */
  requestAuthorization(options?: ScriptWidgetLocationOptions): ScriptWidgetNativePromise<boolean>;
  /** Original catalog: $location.current; runtime 1.0. */
  current(options?: ScriptWidgetLocationOptions): ScriptWidgetNativePromise<{"latitude": number; "longitude": number; "altitude": number; "accuracy": number; "verticalAccuracy": number; "speed": number; "course": number; "timestamp": string; "accuracyAuthorization": string; "age": number; "isStale": boolean}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeMaps.swift */
declare const $maps: {
  /** Original catalog: $maps.search; runtime 1.6. */
  search(options: ScriptWidgetMapSearch): ScriptWidgetNativePromise<({"name": string; "address": string; "latitude": number; "longitude": number})[]>;
  /** Original catalog: $maps.geocode; runtime 1.6. */
  geocode(address: string): ScriptWidgetNativePromise<({"name": string; "address": string; "latitude": number; "longitude": number})[]>;
  /** Original catalog: $maps.reverseGeocode; runtime 1.6. */
  reverseGeocode(options: ScriptWidgetMapRegion): ScriptWidgetNativePromise<({"name": string; "address": string; "latitude": number; "longitude": number})[]>;
  /** Original catalog: $maps.snapshot; runtime 1.6. */
  snapshot(options: ScriptWidgetMapSnapshot): ScriptWidgetNativePromise<{"image": string; "width": number; "height": number; "provider": string}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeMusic.swift */
declare const $music: {
  /** Original catalog: $music.isAvailable; runtime 1.4. */
  isAvailable(): boolean;
  /** Original catalog: $music.authorizationStatus; runtime 1.4. */
  authorizationStatus(): string;
  /** Original catalog: $music.current; runtime 1.4. */
  current(): ScriptWidgetNativePromise<ScriptWidgetMusicSnapshot>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeNotifications.swift */
declare const $notifications: {
  /** Original catalog: $notifications.status; runtime 1.6. */
  status(): ScriptWidgetNativePromise<{"authorization": string}>;
  /** Original catalog: $notifications.pending; runtime 1.6. */
  pending(): ScriptWidgetNativePromise<{key: string; title: string; body: string; repeats: boolean; date: string | null}[]>;
  /** Original catalog: $notifications.schedule; runtime 1.6. */
  schedule(options: ScriptWidgetNotificationOptions): ScriptWidgetNativePromise<{"key": string; "status": string}>;
  /** Original catalog: $notifications.cancel; runtime 1.6. */
  cancel(key: string): ScriptWidgetNativePromise<{"key": string; "status": string}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimePhotos.swift */
declare const $photos: {
  /** Original catalog: $photos.isAvailable; runtime 1.4. */
  isAvailable(): boolean;
  /** Original catalog: $photos.authorizationStatus; runtime 1.4. */
  authorizationStatus(): string;
  /** Original catalog: $photos.requestAuthorization; runtime 1.4. */
  requestAuthorization(): ScriptWidgetNativePromise<boolean>;
  /** Original catalog: $photos.items; runtime 1.4. */
  items(options?: ScriptWidgetPhotoQuery): ScriptWidgetNativePromise<ScriptWidgetNativeList<ScriptWidgetPhoto> & {unavailableCount: number}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeReminders.swift */
declare const $reminders: {
  /** Original catalog: $reminders.isAvailable; runtime 1.4. */
  isAvailable(): boolean;
  /** Original catalog: $reminders.authorizationStatus; runtime 1.4. */
  authorizationStatus(): string;
  /** Original catalog: $reminders.requestAuthorization; runtime 1.4. */
  requestAuthorization(): ScriptWidgetNativePromise<boolean>;
  /** Original catalog: $reminders.lists; runtime 1.4. */
  lists(): ScriptWidgetNativePromise<({"id": string; "title": string})[]>;
  /** Original catalog: $reminders.items; runtime 1.4. */
  items(options?: ScriptWidgetRemindersQuery): ScriptWidgetNativePromise<ScriptWidgetNativeList<ScriptWidgetReminder> & {truncated: boolean}>;
  /** Original catalog: $reminders.create; runtime 1.4. */
  create(options: ScriptWidgetReminderCreate): ScriptWidgetNativePromise<{"id": string; "listID": string; "status": string; "replayed": boolean}>;
  /** Original catalog: $reminders.update; runtime 1.4. */
  update(options: ScriptWidgetReminderUpdate): ScriptWidgetNativePromise<{"id": string; "listID": string; "status": string; "replayed": boolean}>;
  /** Original catalog: $reminders.setCompleted; runtime 1.4. */
  setCompleted(options: ScriptWidgetReminderCompleted): ScriptWidgetNativePromise<{"id": string; "listID": string; "status": string; "replayed": boolean}>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeServices.swift */
declare const $services: {
  /** Original catalog: $services.status; runtime 1.4. */
  status(service: "github"): ScriptWidgetNativePromise<string>;
  /** Original catalog: $services.profile; runtime 1.4. */
  profile(service: "github"): ScriptWidgetNativePromise<ScriptWidgetConnectedProfile>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeStorage.swift */
declare const $storage: {
  /** Read a package-scoped string. Missing keys return an empty string. */
  getString(key: string): string;
  /** Set a package-scoped string, limited to 256 KiB of UTF-8. Check the success result. */
  setString(key: string, value: string): boolean;
  /** Read a package-scoped JSON object. Missing or invalid values return an empty object. */
  getJSON(key: string): ScriptWidgetJSONObject;
  /** Store a valid JSON object, limited to 256 KiB encoded. Check the success result. */
  setJSON(key: string, value: ScriptWidgetJSONObject): boolean;
  /** Atomically replace a string only when it still matches expected. A missing key matches an empty string. Conflicts return false; reread and retry a bounded number of times. Requires the shared storage container. */
  compareAndSetString(key: string, expected: string, value: string): boolean;
  /** Atomically replace a JSON object if its current value equals expected, independent of property order. A missing key matches an empty object. Wrong types and conflicts return false. Requires the shared storage container. */
  compareAndSetJSON(key: string, expected: ScriptWidgetJSONObject, value: ScriptWidgetJSONObject): boolean;
  /** Remove a key from this package only. */
  remove(key: string): boolean;
  /** List keys in this package's namespace. */
  keys(): string[];
  /** Clear this package's storage. Other packages are unaffected. */
  clear(): boolean;
  /** Hanlin exact-value additions; missing values are null. */
  get(key: string): ScriptWidgetJSON;
  set(key: string, value: ScriptWidgetJSON): boolean;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeSystem.swift */
declare const $system: {
  /** Original catalog: $system.appInfo; runtime 1.0. */
  appInfo(): {"name": string; "bundleId": string; "version": string; "build": string};
  /** Original catalog: $system.locale; runtime 1.0. */
  locale(): string;
  /** Original catalog: $system.preferredLanguages; runtime 1.0. */
  preferredLanguages(): (string)[];
  /** Original catalog: $system.timeZone; runtime 1.0. */
  timeZone(): {"identifier": string; "abbreviation": string; "offsetSeconds": number};
  /** Original catalog: $system.is24HourClock; runtime 1.0. */
  is24HourClock(): boolean;
  /** Original catalog: $system.calendarInfo; runtime 1.0. */
  calendarInfo(): {"identifier": string; "firstWeekday": number; "minimumDaysInFirstWeek": number};
  /** Original catalog: $system.systemUptime; runtime 1.0. */
  systemUptime(): number;
  /** Original catalog: $system.memory; runtime 1.0. */
  memory(): {"physical": number};
  /** Original catalog: $system.thermalState; runtime 1.0. */
  thermalState(): string;
  /** Original catalog: $system.lowPowerMode; runtime 1.0. */
  lowPowerMode(): boolean;
  /** Original catalog: $system.brightness; runtime 1.0. */
  brightness(): number;
  /** Original catalog: $system.reduceMotionEnabled; runtime 1.0. */
  reduceMotionEnabled(): boolean;
  /** Original catalog: $system.platform; runtime 1.0. */
  platform(): string;
  /** Original catalog: $system.hostName; runtime 1.0. */
  hostName(): string;
  /** Original catalog: $system.processName; runtime 1.0. */
  processName(): string;
  /** Original catalog: $system.osVersionString; runtime 1.0. */
  osVersionString(): string;
  /** Original catalog: $system.processorCount; runtime 1.0. */
  processorCount(): number;
  /** Original catalog: $system.activeProcessorCount; runtime 1.0. */
  activeProcessorCount(): number;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeWeather.swift */
declare const $weather: {
  /** Original catalog: $weather.forecast; runtime 1.6. */
  forecast(options: ScriptWidgetWeatherOptions): ScriptWidgetNativePromise<ScriptWidgetWeatherForecast>;
};

/** Original native implementation: Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/Widget/API/ScriptWidgetRuntimeConsole.swift */
declare const console: {
  log(string: string): void;
  error(string: string): void;
};

/** Original registration diagnostic; function JSX components resolve their own builder. */
declare function $component<P>(name: string, builder: (props: P) => JSX.Element): void;

/** Captures the actual original native element for each supplied Dynamic Island region. */
declare function $dynamic_island(regions: ScriptWidgetDynamicIslandRegions): void;

declare const $presentation: {expandSheet(): void; finish(replacementText?: string | null): void};

declare namespace JSX { interface GlobalProperties { actionParameters?: ScriptWidgetJSON; } }
