// Semantic payloads verified against the original native JSExport implementations.
// Callable names and argument arity are generated separately from installed Swift.
type ScriptWidgetJSON = null | boolean | number | string | ScriptWidgetJSON[] | ScriptWidgetJSONObject;
interface ScriptWidgetJSONObject { [key: string]: ScriptWidgetJSON; }
/** Original native awaitable. Await it; its native then returns void and has no catch/finally. */
interface ScriptWidgetNativePromise<T> {
  then(resolve: (value: T) => unknown, reject: (reason: unknown) => unknown): void;
}
interface ScriptWidgetHTTPOptions {
  headers?: Record<string, string>;
  body?: string | ScriptWidgetJSONObject;
  timeoutInterval?: number;
  responseType?: "base64" | "text";
}
interface ScriptWidgetHTTPResponse { body: string; status: number; headers: Record<string, string>; }
interface ScriptWidgetQueryWindow { start?: string; end?: string; limit?: number; maxAgeSeconds?: number; }
interface ScriptWidgetCalendarQuery extends ScriptWidgetQueryWindow { calendarIDs?: string[]; }
interface ScriptWidgetRemindersQuery extends ScriptWidgetQueryWindow { listIDs?: string[]; completed?: boolean; }
interface ScriptWidgetCalendarMutation {
  requestID: string; calendarID: string; title: string; start: string; end: string; allDay?: boolean;
}
interface ScriptWidgetCalendarUpdate extends ScriptWidgetCalendarMutation { id: string; }
interface ScriptWidgetReminderCreate { requestID: string; listID: string; title: string; due?: string | null; priority?: number; }
type ScriptWidgetReminderUpdate = {requestID: string; listID: string; id: string; title?: string; due?: string | null; priority?: number} &
  ({title: string} | {due: string | null} | {priority: number});
interface ScriptWidgetReminderCompleted { requestID: string; listID: string; id: string; completed: boolean; }
type ScriptWidgetNotificationOptions = {key: string; title: string; body: string} &
  ({date: string; daily?: never} | {date?: never; daily: {hour: number; minute: number}});
type ScriptWidgetAlarmOptions = {requestID: string; key: string; title: string} &
  ({date: string; seconds?: never} | {date?: never; seconds: number});
interface ScriptWidgetLocationOptions {
  timeoutMs?: number; timeout?: number; maxAgeMs?: number; maxAge?: number;
  accuracy?: "full" | "reduced"; purposeKey?: string;
}
interface ScriptWidgetMapRegion { latitude: number; longitude: number; radiusMeters?: number; }
interface ScriptWidgetMapSearch extends ScriptWidgetMapRegion { query: string; }
interface ScriptWidgetMapSnapshot extends ScriptWidgetMapRegion { size?: number; }
interface ScriptWidgetWeatherOptions { latitude: number; longitude: number; hours?: number; }
interface ScriptWidgetHealthWindow { start?: string; end?: string; }
interface ScriptWidgetHealthWorkoutsQuery extends ScriptWidgetHealthWindow { limit?: number; }
interface ScriptWidgetHealthDailyQuery {
  metric: "steps" | "activeEnergy" | "walkingDistance" | "water" | "bodyMass" | "heartRate"; days?: number;
}
interface ScriptWidgetPhotoQuery { limit?: number; offset?: number; maxAgeSeconds?: number; }
interface ScriptWidgetNativeList<T> { status: string; items: T[]; fetchedAt: string; source: string; stale: boolean; }
interface ScriptWidgetCalendarEvent { id: string; calendarID: string; title: string; start: string; end: string; allDay: boolean; }
interface ScriptWidgetReminder {
  id: string; listID: string; title: string; due: string | null; hasTime: boolean;
  completed: boolean; completedAt: string | null; priority: number;
}
interface ScriptWidgetPhoto { id: string; image: string; width: number; height: number; }
interface ScriptWidgetHealthMeasurement { value: number; unit: string; hasSamples: boolean; start: string; end: string; }
interface ScriptWidgetHealthActivity {
  date: string; timeZone: string; hasSamples: boolean; moveMode: string;
  move: {value: number; goal: number | null; unit: string};
  exercise: {value: number; goal: number | null; unit: string};
  stand: {value: number; goal: number | null; unit: string};
}
interface ScriptWidgetHealthWorkout {
  id: string; activity: string; start: string; end: string; duration: number;
  energyKcal: number | null; distanceMeters: number | null;
}
interface ScriptWidgetHealthWorkouts {
  start: string; end: string; timeZone: string; hasSamples: boolean; truncated: boolean; items: ScriptWidgetHealthWorkout[];
}
interface ScriptWidgetHealthDailyStatistics {
  metric: string; unit: string; aggregation: string; timeZone: string;
  items: {date: string; value: number | null; hasSamples: boolean}[];
}
interface ScriptWidgetMusicSnapshot {
  provider: string; state: string; hasItem: boolean; title: string | null; artist: string | null; album: string | null;
  duration: number | null; position: number | null; capturedAt: string;
}
interface ScriptWidgetConnectedProfile {
  service: string; subject: string; username: string | null; displayName: string | null;
  publicRepositories: number | null; privateRepositories: number | null; followers: number | null; following: number | null;
}
interface ScriptWidgetCloudJSONDocument {
  value: ScriptWidgetJSONObject | null; revision: string; state: string;
  conflicts: {id: string; value: ScriptWidgetJSONObject}[];
}
interface ScriptWidgetCloudJSONStatus {
  state: string; store: string; uploaded: null; uploadState: string; conflictPolicy: string;
}
interface ScriptWidgetCloudJSONSync { state: string; materializedRevisions: number; downloadedRevisions: number; uploaded: null; }
interface ScriptWidgetXMLNode { name: string; attributes: Record<string, string>; text: string; children: ScriptWidgetXMLNode[]; }

/** UIKit omits text context it cannot provide (for example, an unavailable selection). */
type ScriptWidgetKeyboardContext = {
  documentContextBeforeInput?: string;
  documentContextAfterInput?: string;
  selectedText?: string;
  hasFullAccess: boolean;
};
type ScriptWidgetPresentationContext = {
  kind: "snippet" | "translationUI" | "keyboard" | "notificationUI";
  sessionID: string; inputText: string;
  parameters: ScriptWidgetJSON; allowsReplacement: boolean;
  keyboard?: ScriptWidgetKeyboardContext;
};
interface ScriptWidgetActionEvent<Parameters = ScriptWidgetJSON> { parameters: Parameters; value?: boolean; }
interface ScriptWidgetDynamicIslandRegions {
  expanded?: {leading?: JSX.Element | null; trailing?: JSX.Element | null; center?: JSX.Element | null; bottom?: JSX.Element | null};
  compactLeading?: JSX.Element | null; compactTrailing?: JSX.Element | null; minimal?: JSX.Element | null;
}

interface ScriptWidgetWeatherForecast {
  provider: string; attribution: {text: string; url: string}; latitude: number; longitude: number; fetchedAt: string; isStale: boolean;
  hours: {time: string; temperatureC: number; windMetersPerSecond: number; precipitationMM: number | null; condition: string | null}[];
}
