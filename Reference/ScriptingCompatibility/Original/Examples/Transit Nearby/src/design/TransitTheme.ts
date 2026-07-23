import type { Color } from "scripting"
import type { TransitRoute } from "../domain/models"

const ROUTE_PALETTE: Color[] = [
  "#E5252A",
  "#169B35",
  "#6930B8",
  "#F27A0A",
  "#1268D6",
]

export const TransitTheme = {
  accent: "#087AF1" as Color,
  realtime: "#159B2E" as Color,
  warning: "#F09A16" as Color,
  card: { light: "secondarySystemGroupedBackground", dark: "secondarySystemBackground" } as const,
  groupedBackground: { light: "systemGroupedBackground", dark: "systemBackground" } as const,
  activityPurple: "#7442C8" as Color,
}

export function routeColor(route: Pick<TransitRoute, "number" | "color"> | { number: string; color?: string | null }): Color {
  if (route.color?.startsWith("#")) return route.color as Color
  let hash = 0
  for (const character of route.number) hash = (hash * 31 + character.charCodeAt(0)) >>> 0
  return ROUTE_PALETTE[hash % ROUTE_PALETTE.length]
}

export function routeColorForNumber(number: string): Color {
  return routeColor({ number })
}
