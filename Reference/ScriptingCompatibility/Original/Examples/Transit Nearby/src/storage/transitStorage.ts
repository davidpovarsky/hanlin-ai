import type { FavoriteRoute, RecentSearch, RouteDetails, StopBoard, TransitRoute, TransitStop } from "../domain/models"

const FAVORITES_KEY = "transit-nearby.favorites.v1"
const RECENT_STOPS_KEY = "transit-nearby.recent-stops.v1"
const BOARD_CACHE_PREFIX = "transit-nearby.board."
const WIDGET_INDEX_PREFIX = "transit-nearby.widget-index."
const ACTIVE_ACTIVITY_KEY = "transit-nearby.active-activity-id"
const ROUTE_CACHE_PREFIX = "transit-nearby.route."
const ROUTE_DETAILS_CACHE_PREFIX = "transit-nearby.route-details."
const FAVORITE_ROUTES_KEY = "transit-nearby.favorite-routes.v1"
const RECENT_SEARCHES_KEY = "transit-nearby.recent-searches.v1"
const CACHE_INDEX_KEY = "transit-nearby.cache-index.v2"
const SETTINGS_KEY = "transit-nearby.settings.v2"
const SHARED = { shared: true } as const

type CacheEnvelope<T> = {
  version: 2
  value: T
  storedAt: number
  expiresAt: number
}

export type CacheState<T> = {
  value: T
  storedAt: number
  stale: boolean
}

export type TransitPreferences = {
  refreshIntervalSeconds: number
  nearbyRadiusMeters: number
  maximumNearbyStops: number
  wheelchairDefault: boolean
}

export const DEFAULT_PREFERENCES: TransitPreferences = {
  refreshIntervalSeconds: 30,
  nearbyRadiusMeters: 1_000,
  maximumNearbyStops: 20,
  wheelchairDefault: false,
}

function readEnvelope<T>(key: string): CacheState<T> | null {
  const envelope = Storage.get<CacheEnvelope<T>>(key, SHARED)
  if (!envelope || envelope.version !== 2 || envelope.value == null) return null
  return { value: envelope.value, storedAt: envelope.storedAt, stale: envelope.expiresAt <= Date.now() }
}

function writeEnvelope<T>(key: string, value: T, ttlMilliseconds: number): void {
  const now = Date.now()
  Storage.set<CacheEnvelope<T>>(key, { version: 2, value, storedAt: now, expiresAt: now + ttlMilliseconds }, SHARED)
  const index = Storage.get<string[]>(CACHE_INDEX_KEY, SHARED) ?? []
  if (!index.includes(key)) Storage.set(CACHE_INDEX_KEY, [...index, key], SHARED)
}

export function getFavorites(): TransitStop[] {
  return Storage.get<TransitStop[]>(FAVORITES_KEY, SHARED) ?? []
}

export function setFavorites(stops: TransitStop[]): void {
  Storage.set(FAVORITES_KEY, stops, SHARED)
}

export function isFavorite(stopCode: string): boolean {
  return getFavorites().some(stop => stop.code === stopCode)
}

export function toggleFavorite(stop: TransitStop): boolean {
  const favorites = getFavorites()
  const exists = favorites.some(item => item.code === stop.code)
  setFavorites(exists ? favorites.filter(item => item.code !== stop.code) : [...favorites, stop])
  return !exists
}

export function getFavoriteRoutes(): TransitRoute[] {
  return (Storage.get<FavoriteRoute[]>(FAVORITE_ROUTES_KEY, SHARED) ?? []).map(item => item.route)
}

export function isFavoriteRoute(routeId: string): boolean {
  return getFavoriteRoutes().some(route => route.id === routeId)
}

export function toggleFavoriteRoute(route: TransitRoute): boolean {
  const routes = getFavoriteRoutes()
  const exists = routes.some(item => item.id === route.id)
  const next = exists ? routes.filter(item => item.id !== route.id) : [...routes, route]
  Storage.set<FavoriteRoute[]>(FAVORITE_ROUTES_KEY, next.map(item => ({ type: "route", route: item })), SHARED)
  return !exists
}

export function getRecentStops(): TransitStop[] {
  return Storage.get<TransitStop[]>(RECENT_STOPS_KEY, SHARED) ?? []
}

export function setRecentStops(stops: TransitStop[]): void {
  Storage.set(RECENT_STOPS_KEY, stops.slice(0, 12), SHARED)
}

export function getRecentSearches(): RecentSearch[] {
  return Storage.get<RecentSearch[]>(RECENT_SEARCHES_KEY, SHARED) ?? []
}

export function addRecentSearch(search: Omit<RecentSearch, "savedAt">): void {
  const next: RecentSearch = { ...search, savedAt: Date.now() }
  const current = getRecentSearches().filter(item => item.id !== search.id || item.kind !== search.kind)
  Storage.set(RECENT_SEARCHES_KEY, [next, ...current].slice(0, 12), SHARED)
}

export function clearRecentSearches(): void {
  Storage.remove(RECENT_SEARCHES_KEY, SHARED)
}

export function getCachedBoard(stopCode: string): StopBoard | null {
  return getCachedBoardState(stopCode)?.value ?? null
}

export function getCachedBoardState(stopCode: string): CacheState<StopBoard> | null {
  return readEnvelope<StopBoard>(`${BOARD_CACHE_PREFIX}${stopCode}`)
}

export function setCachedBoard(board: StopBoard): void {
  writeEnvelope(`${BOARD_CACHE_PREFIX}${board.stop.code}`, board, 60_000)
}

export function getCachedRoute(routeId: string): TransitRoute | null {
  return readEnvelope<TransitRoute>(`${ROUTE_CACHE_PREFIX}${routeId}`)?.value ?? null
}

export function setCachedRoute(route: TransitRoute): void {
  writeEnvelope(`${ROUTE_CACHE_PREFIX}${route.id}`, route, 24 * 60 * 60_000)
}

export function getCachedRouteDetails(routeId: string): CacheState<RouteDetails> | null {
  return readEnvelope<RouteDetails>(`${ROUTE_DETAILS_CACHE_PREFIX}${routeId}`)
}

export function setCachedRouteDetails(details: RouteDetails): void {
  writeEnvelope(`${ROUTE_DETAILS_CACHE_PREFIX}${details.route.id}`, details, 24 * 60 * 60_000)
}

export function getPreferences(): TransitPreferences {
  return { ...DEFAULT_PREFERENCES, ...(Storage.get<Partial<TransitPreferences>>(SETTINGS_KEY, SHARED) ?? {}) }
}

export function setPreferences(value: TransitPreferences): void {
  Storage.set(SETTINGS_KEY, value, SHARED)
}

export function clearTransitCache(): void {
  const keys = Storage.get<string[]>(CACHE_INDEX_KEY, SHARED) ?? []
  keys.forEach(key => Storage.remove(key, SHARED))
  Storage.remove(CACHE_INDEX_KEY, SHARED)
}

export function resetFavorites(): void {
  Storage.remove(FAVORITES_KEY, SHARED)
  Storage.remove(FAVORITE_ROUTES_KEY, SHARED)
}

export function getWidgetIndex(groupKey: string, count: number): number {
  if (count <= 0) return 0
  const stored = Storage.get<number>(`${WIDGET_INDEX_PREFIX}${groupKey}`, SHARED) ?? 0
  return ((stored % count) + count) % count
}

export function setWidgetIndex(groupKey: string, index: number): void {
  Storage.set(`${WIDGET_INDEX_PREFIX}${groupKey}`, index, SHARED)
}

export function getActiveActivityId(): string | null {
  return Storage.get<string>(ACTIVE_ACTIVITY_KEY, SHARED)
}

export function setActiveActivityId(id: string | null): void {
  if (id == null) {
    Storage.remove(ACTIVE_ACTIVITY_KEY, SHARED)
    return
  }
  Storage.set(ACTIVE_ACTIVITY_KEY, id, SHARED)
}
