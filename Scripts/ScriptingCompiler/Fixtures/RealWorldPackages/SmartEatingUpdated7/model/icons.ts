// model/icons.ts — Centralized icon definitions
// Change SF Symbol names here to update icons across the entire app.
// To switch back to emoji, change `type` to "emoji" and set `emoji` values.

export type IconType = "sfSymbol" | "emoji"

export const ICON_TYPE: IconType = "sfSymbol"

// ── Station Icons ──────────────────────────────────────────────
export const STATION_ICONS = {
  breakfast:    { sfSymbol: "sunrise.fill",          emoji: "🌅" },
  morningSnack: { sfSymbol: "leaf.fill",             emoji: "🍎" },
  lunch:        { sfSymbol: "fork.knife",            emoji: "🍽️" },
  afternoonSnack:{ sfSymbol: "cup.and.saucer.fill",  emoji: "🥤" },
  dinner:       { sfSymbol: "moon.stars.fill",       emoji: "🌙" },
} as const

// Map station id → icon key
export const STATION_ICON_MAP: Record<number, keyof typeof STATION_ICONS> = {
  1: "breakfast",
  2: "morningSnack",
  3: "lunch",
  4: "afternoonSnack",
  5: "dinner",
}

// ── Status Icons ───────────────────────────────────────────────
export const ICONS = {
  completed:       { sfSymbol: "checkmark.circle.fill",          emoji: "✅" },
  streak:          { sfSymbol: "flame.fill",                     emoji: "🔥" },
  appTitle:        { sfSymbol: "leaf.circle.fill",               emoji: "🥗" },
  timeNow:         { sfSymbol: "clock.badge.exclamationmark",    emoji: "⏰" },
  allDone:         { sfSymbol: "star.circle.fill",               emoji: "🌟" },
  trophy:          { sfSymbol: "trophy.fill",                    emoji: "🏆" },
  note:            { sfSymbol: "note.text",                      emoji: "📝" },
  history:         { sfSymbol: "chart.bar.fill",                 emoji: "📊" },
  ai:              { sfSymbol: "brain.head.profile",             emoji: "🤖" },
  settings:        { sfSymbol: "gearshape.fill",                 emoji: "⚙️" },
  suggestions:     { sfSymbol: "lightbulb.fill",                 emoji: "💡" },
  encourage:       { sfSymbol: "hand.thumbsup.fill",             emoji: "💪" },
  notification:    { sfSymbol: "bell.badge.fill",                emoji: "🔔" },
  refresh:         { sfSymbol: "arrow.clockwise",                emoji: "🔄" },
  trash:           { sfSymbol: "trash.fill",                     emoji: "🗑️" },
  info:            { sfSymbol: "info.circle",                    emoji: "ℹ️" },
  clock:           { sfSymbol: "clock.fill",                     emoji: "⏰" },
  points:          { sfSymbol: "star.fill",                      emoji: "⭐" },
  send:            { sfSymbol: "paperplane.fill",                emoji: "🔍" },
  analyze:         { sfSymbol: "chart.line.uptrend.xyaxis",      emoji: "📊" },
  goodMorning:     { sfSymbol: "sun.max.fill",                   emoji: "☀️" },
  markDone:        { sfSymbol: "checkmark",                      emoji: "✓" },
  food:            { sfSymbol: "fork.knife.circle",              emoji: "🍽️" },
  nextStation:     { sfSymbol: "arrow.right.circle.fill",        emoji: "➡️" },
  calendar:        { sfSymbol: "calendar",                       emoji: "📅" },
  average:         { sfSymbol: "equal.circle.fill",              emoji: "⭐" },
  language:        { sfSymbol: "globe",                          emoji: "🌐" },
  warning:         { sfSymbol: "exclamationmark.triangle.fill",  emoji: "⚠️" },
  edit:            { sfSymbol: "pencil.circle.fill",             emoji: "✏️" },
  aiSuggest:       { sfSymbol: "sparkles",                       emoji: "✨" },
  skipped:         { sfSymbol: "clock.badge.xmark",              emoji: "⏭️" },
  mealLog:         { sfSymbol: "list.clipboard.fill",            emoji: "📋" },
  chevronDown:     { sfSymbol: "chevron.down",                   emoji: "▼" },
} as const

// ── Icon Colors ────────────────────────────────────────────────
export const ICON_COLORS = {
  breakfast:       "systemOrange",
  morningSnack:    "systemGreen",
  lunch:           "systemBlue",
  afternoonSnack:  "systemPurple",
  dinner:          "systemIndigo",
  completed:       "systemGreen",
  streak:          "systemOrange",
  appTitle:        "systemGreen",
  timeNow:         "systemOrange",
  allDone:         "systemYellow",
  trophy:          "systemYellow",
  points:          "systemYellow",
  nextStation:     "systemBlue",
  warning:         "systemRed",
  edit:            "systemBlue",
  aiSuggest:       "systemPurple",
  skipped:         "systemRed",
} as const

// ── Helper: get icon value based on current ICON_TYPE ──────────
export function getStationIcon(stationId: number): string {
  const key = STATION_ICON_MAP[stationId]
  if (!key) return ICON_TYPE === "sfSymbol" ? "questionmark.circle" : "❓"
  return ICON_TYPE === "sfSymbol"
    ? STATION_ICONS[key].sfSymbol
    : STATION_ICONS[key].emoji
}

export function getIcon(name: keyof typeof ICONS): string {
  return ICON_TYPE === "sfSymbol" ? ICONS[name].sfSymbol : ICONS[name].emoji
}

export function getStationColor(stationId: number): string {
  const key = STATION_ICON_MAP[stationId]
  return key && ICON_COLORS[key] ? ICON_COLORS[key] : "label"
}