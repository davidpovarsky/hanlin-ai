import { fetchJson } from "./http"
import { busNearbyAuthorizationHeader, getBusNearbyToken, removeBusNearbyToken } from "./auth"
import type {
  BusNearbyGeometryResponse,
  BusNearbyIndexedStop,
  BusNearbyPlanResponse,
  BusNearbyStopSearchItem,
  KavNavAlertsResponse,
  KavNavRealtimeResponse,
  KavNavRouteResponse,
  KavNavRouteScheduleResponse,
  KavNavStopScheduleResponse,
  KavNavStopSummaryResponse,
} from "./contracts"

const KAVNAV_ORIGIN = "https://kavnav.com"
const BUS_NEARBY_API_ORIGIN = "https://api.busnearby.co.il"
const BUS_NEARBY_APP_ORIGIN = "https://app.busnearby.co.il"

function url(origin: string, path: string, params: Record<string, string | number | boolean | undefined>): string {
  const query = Object.entries(params)
    .filter((entry): entry is [string, string | number | boolean] => entry[1] !== undefined)
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`)
    .join("&")
  return `${origin}${path}${query.length > 0 ? `?${query}` : ""}`
}

export const kavnavClient = {
  realtime(params: { stopCode?: string; routeCode?: string } = {}) {
    return fetchJson<KavNavRealtimeResponse>(url(KAVNAV_ORIGIN, "/api/realtime", params), "KavNav realtime")
  },

  stopSchedule(stopCode: string, date: string) {
    return fetchJson<KavNavStopScheduleResponse>(url(KAVNAV_ORIGIN, "/api/stopSchedule", { stopCode, date }), "KavNav stop schedule")
  },

  stopSummary(stopCode: string) {
    return fetchJson<KavNavStopSummaryResponse>(url(KAVNAV_ORIGIN, "/api/stopSummary", { stopCode }), "KavNav stop summary")
  },

  alerts(stopId: string) {
    return fetchJson<KavNavAlertsResponse>(url(KAVNAV_ORIGIN, "/api/alerts", { stopId }), "KavNav alerts")
  },

  route(routeId: string, date: string) {
    return fetchJson<KavNavRouteResponse>(url(KAVNAV_ORIGIN, "/api/route", { routeId, date }), "KavNav route")
  },

  routeSchedule(routeId: string, date: string) {
    return fetchJson<KavNavRouteScheduleResponse>(url(KAVNAV_ORIGIN, "/api/routeSchedule", { routeId, date }), "KavNav route schedule")
  },

  routeAlerts(routeId: string) {
    return fetchJson<KavNavAlertsResponse>(url(KAVNAV_ORIGIN, "/api/alerts", { routeId }), "KavNav route alerts")
  },

  stopPOIs(stopCode: string) {
    return fetchJson(url(KAVNAV_ORIGIN, "/api/stopPOIs", { stopCode }), "KavNav stop POIs")
  },
}

function authenticatedFetch(path: string, params: Record<string, string | number | boolean | undefined>, label: string, timeoutMs = 10_000) {
  if (!getBusNearbyToken()) throw new Error("נדרש אסימון BusNearby")
  return fetchJson(url(BUS_NEARBY_API_ORIGIN, path, params), label, {
    headers: busNearbyAuthorizationHeader(),
    timeoutMs,
    onAuthenticationFailure: removeBusNearbyToken,
  })
}

export const busNearbyClient = {
  searchStops(query: string) {
    return fetchJson<BusNearbyStopSearchItem[]>(url(BUS_NEARBY_APP_ORIGIN, "/stopSearch", { locale: "he", query }), "BusNearby stop search", { timeoutMs: 8_000 })
  },

  geocode(query: string) {
    return fetchJson(url(BUS_NEARBY_API_ORIGIN, "/geocode", { locale: "he", query }), "BusNearby geocode", { timeoutMs: 8_000 })
  },

  nearbyStops(latitude: number, longitude: number, radius = 1_000, max = 20) {
    return authenticatedFetch("/directions/index/stops", { locale: "he", lat: latitude, lon: longitude, radius, max }, "BusNearby nearby stops") as Promise<BusNearbyIndexedStop[]>
  },

  stop(stopId: string) {
    return authenticatedFetch(`/directions/index/stops/${encodeURIComponent(stopId)}`, { locale: "he" }, "BusNearby stop")
  },

  stopRoutes(stopId: string) {
    return authenticatedFetch(`/directions/index/stops/${encodeURIComponent(stopId)}/routes`, {}, "BusNearby stop routes")
  },

  stopTimes(stopId: string, startTime: number, numberOfDepartures = 12, timeRange = 7_200) {
    return authenticatedFetch(`/directions/index/stops/${encodeURIComponent(stopId)}/stoptimes`, {
      locale: "he", startTime, numberOfDepartures, timeRange,
    }, "BusNearby stop times", 8_000)
  },

  stopAlerts(stopId: string) {
    return authenticatedFetch(`/directions/patch/stopAlerts/${encodeURIComponent(stopId)}`, { locale: "he" }, "BusNearby stop alerts")
  },

  patternsByLine(routeNumber: string) {
    return fetchJson(
      url(BUS_NEARBY_API_ORIGIN, `/directions/index/patterns/byshortname/${encodeURIComponent(routeNumber)}`, { locale: "he" }),
      "BusNearby line patterns",
    )
  },

  pattern(patternId: string) {
    return fetchJson(
      url(BUS_NEARBY_API_ORIGIN, `/directions/index/patterns/${encodeURIComponent(patternId)}`, { locale: "he" }),
      "BusNearby route pattern",
    )
  },

  geometry(patternId: string) {
    return authenticatedFetch(`/directions/index/patterns/${encodeURIComponent(patternId)}/geometry`, {}, "BusNearby route geometry") as Promise<BusNearbyGeometryResponse>
  },

  routeAlerts(routeId: string) {
    return fetchJson(url(BUS_NEARBY_API_ORIGIN, `/directions/patch/routeAlerts/${encodeURIComponent(routeId)}`, { locale: "he" }), "BusNearby route alerts")
  },

  plan(params: {
    fromPlace: string
    toPlace: string
    date?: string
    time?: string
    arriveBy: boolean
    wheelchair: boolean
    maxWalkDistance: number
  }) {
    return authenticatedFetch("/directions/plan", {
      ...params,
      locale: "he",
      mode: "TRANSIT,WALK",
      showIntermediateStops: true,
      numItineraries: 4,
      optimize: "QUICK",
      ignoreRealtimeUpdates: false,
    }, "BusNearby journey plan", 20_000) as Promise<BusNearbyPlanResponse>
  },
}
