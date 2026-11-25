// Generated from the installed original ScriptWidget Codable manifest; do not edit.
// Semantic rules and source identities: widget-manifest.schema.json.

type WidgetPackageFamily = "systemSmall" | "systemMedium" | "systemLarge" | "systemExtraLarge" | "systemExtraLargePortrait" | "accessoryCircular" | "accessoryRectangular" | "accessoryInline";
type WidgetPackagePermission = "network" | "location" | "health" | "calendar" | "reminders" | "remindersWrite" | "photos" | "services" | "music" | "storage" | "icloud" | "notifications" | "calendarWrite" | "maps" | "weather" | "alarms" | "documents" | "contacts" | "home" | "files";
type WidgetPackageControlType = "button" | "toggle";

interface WidgetPackageAuthor {
  name: string;
  url?: string | null;
}

interface WidgetPackageAction {
  id: string;
  title: string;
  description?: string | null;
  systemImage: string;
  function: string;
}

interface WidgetPackagePushUpdates {
  registrationURL: string;
  channel: string;
}

interface WidgetPackageTimeline {
  dailyTimes: string[];
  timeZone?: string | null;
}

interface WidgetPackageManifest {
  formatVersion: 2;
  id: string;
  name: string;
  version: string;
  runtimeVersion: "1.0";
  minimumRuntimeVersion?: string | null;
  timeline?: WidgetPackageTimeline | null;
  entry: string;
  supportedFamilies: WidgetPackageFamily[];
  permissions: WidgetPackagePermission[];
  networkDomains: string[];
  plugins?: string[] | null;
  actions?: WidgetPackageAction[] | null;
  controls?: WidgetPackageControl[] | null;
  pushUpdates?: WidgetPackagePushUpdates | null;
  description?: string | null;
  category?: string | null;
  tags?: string[] | null;
  icon?: string | null;
  preview?: string | null;
  author?: WidgetPackageAuthor | null;
  license?: string | null;
}

type WidgetPackageControl = {
  id: string;
  title: string;
  subtitle?: string | null;
  systemImage: string;
} & ({actionID: string; action?: null} | {action: string; actionID?: null})
  & ({type: "button"; stateKey?: null} | {type: "toggle"; stateKey: string});
