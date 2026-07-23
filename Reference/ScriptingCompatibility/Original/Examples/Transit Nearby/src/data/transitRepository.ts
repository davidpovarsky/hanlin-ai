import type {
  Coordinate,
  JourneyLeg,
  JourneyPlace,
  JourneyPlan,
  RouteDetails,
  RouteStop,
  RouteTrip,
  RouteVehicle,
  StopBoard,
  TransitAlert,
  TransitArrival,
  TransitRoute,
  TransitStop,
} from "../domain/models"
import {
  getCachedBoardState,
  getCachedRoute,
  getCachedRouteDetails,
  getPreferences,
  setCachedBoard,
  setCachedRoute,
  setCachedRouteDetails,
  setRecentStops,
} from "../storage/transitStorage"
import { localDateKey, serviceTimeToTimestamp } from "../utils/dates"
import { decodePolyline6, distanceMeters } from "../utils/geo"
import { asArray, asBoolean, asNumber, asRecord, asString, parseTimestamp, uniqueBy } from "../utils/values"
import { busNearbyClient, kavnavClient } from "./clients"
import { hasBusNearbyToken } from "./auth"

const ROUTE_COLORS = ["systemBlue", "systemGreen", "systemOrange", "systemPurple", "systemRed"]
const boardRequests = new Map<string, Promise<StopBoard>>()
const routeMetadataRequests = new Map<string, Promise<TransitRoute | null>>()

export async function searchStops(query: string, origin?: Coordinate): Promise<TransitStop[]> {
  const trimmed = query.trim()
  if (trimmed.length < 2) return []
  const raw = await busNearbyClient.searchStops(trimmed)
  const stops = asArray(raw).map(item => parseSearchStop(item, origin)).filter(isPresent)
  return uniqueBy(stops, stop => stop.code).sort((left, right) => {
    if (left.distanceMeters == null) return 1
    if (right.distanceMeters == null) return -1
    return left.distanceMeters - right.distanceMeters
  })
}

export async function findNearbyStops(location: Coordinate): Promise<TransitStop[]> {
  if (hasBusNearbyToken()) {
    try {
      const preferences = getPreferences()
      const raw = await busNearbyClient.nearbyStops(
        location.latitude,
        location.longitude,
        preferences.nearbyRadiusMeters,
        preferences.maximumNearbyStops,
      )
      const direct = asArray(raw).map(item => parseIndexedStop(item, location)).filter(isPresent)
      if (direct.length > 0) {
        setRecentStops(direct)
        return direct
      }
    } catch {
      // Continue to the public search fallback below.
    }
  }

  const placemarks = await Location.reverseGeocode({
    latitude: location.latitude,
    longitude: location.longitude,
    locale: "he-IL",
  })
  const placemark = placemarks?.[0]
  const queries = uniqueBy([
    placemark?.thoroughfare,
    placemark?.subLocality,
    placemark?.locality,
    placemark?.name,
  ].filter((value): value is string => typeof value === "string" && value.trim().length >= 2), value => value)

  const results: TransitStop[] = []
  for (const query of queries.slice(0, 3)) {
    try {
      results.push(...await searchStops(query, location))
    } catch {
      // Try the next reverse-geocoded term. A partial result is still useful.
    }
    if (uniqueBy(results, stop => stop.code).filter(stop => (stop.distanceMeters ?? Infinity) <= 3_000).length >= 8) break
  }

  const nearby = uniqueBy(results, stop => stop.code)
    .filter(stop => (stop.distanceMeters ?? Infinity) <= 5_000)
    .sort((left, right) => (left.distanceMeters ?? Infinity) - (right.distanceMeters ?? Infinity))
    .slice(0, 20)

  setRecentStops(nearby)
  return nearby
}

export async function searchRoutes(query: string): Promise<TransitRoute[]> {
  const trimmed = query.trim()
  if (!trimmed) return []
  const raw = await busNearbyClient.patternsByLine(trimmed)
  return uniqueBy(asArray(raw).map(value => parsePatternRoute(asRecord(value), {
    id: "",
    number: trimmed,
    longName: "",
    headsign: "",
    operatorName: "",
    color: null,
  })), route => `${route.id}:${route.headsign}`).filter(route => route.id && route.number)
}

export async function geocodePlaces(query: string): Promise<JourneyPlace[]> {
  if (query.trim().length < 2) return []
  const raw = await busNearbyClient.geocode(query.trim())
  return asArray(raw).map(value => {
    const item = asRecord(value)
    const latitude = asNumber(item.lat)
    const longitude = asNumber(item.lng)
    if (latitude == null || longitude == null) return null
    return {
      name: asString(item.description, query.trim()),
      coordinate: { latitude, longitude },
    }
  }).filter(isPresent)
}

export async function planJourney(options: {
  from: JourneyPlace
  to: JourneyPlace
  date: number
  arriveBy: boolean
  wheelchair: boolean
  maxWalkDistance: number
}): Promise<JourneyPlan[]> {
  const date = new Date(options.date)
  const raw = await busNearbyClient.plan({
    fromPlace: placeParameter(options.from),
    toPlace: placeParameter(options.to),
    date: localDateKey(date),
    time: `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`,
    arriveBy: options.arriveBy,
    wheelchair: options.wheelchair,
    maxWalkDistance: options.maxWalkDistance,
  })
  return parseJourneyPlans(raw)
}

export function loadStopBoard(stop: TransitStop): Promise<StopBoard> {
  const existing = boardRequests.get(stop.code)
  if (existing) return existing
  const request = fetchStopBoard(stop).finally(() => boardRequests.delete(stop.code))
  boardRequests.set(stop.code, request)
  return request
}

async function fetchStopBoard(stop: TransitStop): Promise<StopBoard> {
  const date = localDateKey()
  const [realtimeResult, scheduleResult, summaryResult] = await Promise.allSettled([
    kavnavClient.realtime({ stopCode: stop.code }),
    kavnavClient.stopSchedule(stop.code, date),
    kavnavClient.stopSummary(stop.code),
  ])
  const summaryStopId = summaryResult.status === "fulfilled"
    ? asString(asRecord(asArray(summaryResult.value)[0]).stopId)
    : ""
  const alertsResult = await Promise.allSettled([
    kavnavClient.alerts(summaryStopId || stop.motStopId || stop.id.replace(/^1:/, "")),
  ]).then(results => results[0])

  if (realtimeResult.status === "rejected" && scheduleResult.status === "rejected") {
    const cached = getCachedBoardState(stop.code)
    if (cached) return { ...cached.value, stale: true, warningMessage: "מוצג המידע האחרון שנשמר במכשיר" }
    throw new Error("לא ניתן לטעון זמני הגעה כעת")
  }

  let routes = summaryResult.status === "fulfilled" ? parseRoutes(summaryResult.value) : []
  if (scheduleResult.status === "fulfilled") {
    routes = await enrichRoutes(routes, scheduleResult.value, date)
  }
  const realtime = realtimeResult.status === "fulfilled"
    ? parseRealtimeArrivals(realtimeResult.value, stop.code)
    : []
  const scheduled = scheduleResult.status === "fulfilled"
    ? parseScheduledArrivals(scheduleResult.value, routes, date)
    : []
  const arrivals = mergeArrivals(realtime, scheduled).slice(0, 16)
  const alerts = alertsResult.status === "fulfilled" ? parseAlerts(alertsResult.value) : []

  const board: StopBoard = {
    stop,
    routes,
    arrivals,
    alerts,
    updatedAt: Date.now(),
    hasRealtime: realtime.length > 0,
    stale: false,
    warningMessage: realtimeResult.status === "rejected" || scheduleResult.status === "rejected"
      ? "חלק ממקורות המידע אינם זמינים כרגע"
      : null,
  }
  setCachedBoard(board)
  return board
}

export async function loadRouteDetails(route: TransitRoute): Promise<RouteDetails> {
  let patternsRaw: unknown
  try {
    patternsRaw = await busNearbyClient.patternsByLine(route.number)
  } catch (error) {
    const cached = getCachedRouteDetails(route.id)
    if (cached) return { ...cached.value, stale: true }
    throw error
  }
  const patterns = asArray(patternsRaw).map(asRecord)
  const matchingPattern = patterns.find(item => {
    const nestedRoute = asRecord(item.route)
    const shortName = asString(nestedRoute.shortName)
    return shortName === route.number && (!route.headsign || asString(item.headsign) === route.headsign)
  }) ?? patterns.find(item => asString(asRecord(item.route).shortName) === route.number) ?? patterns[0]

  const patternId = asString(matchingPattern?.id)
  if (!patternId) throw new Error("לא נמצא מסלול פעיל לקו")

  const [patternResult, geometryResult, scheduleResult, alertsResult] = await Promise.allSettled([
    busNearbyClient.pattern(patternId),
    busNearbyClient.geometry(patternId),
    kavnavClient.routeSchedule(kavNavRouteId(route.id), localDateKey()),
    kavnavClient.routeAlerts(kavNavRouteId(route.id)),
  ])
  if (patternResult.status === "rejected") throw patternResult.reason
  let realtimeRaw: unknown = {}
  try {
    realtimeRaw = await kavnavClient.realtime({ routeCode: route.number })
  } catch {
    // A route can be valid even when no vehicle is currently reporting.
  }

  const pattern = asRecord(patternResult.value)
  const geometry = geometryResult.status === "fulfilled" ? asRecord(geometryResult.value) : {}
  const parsedRoute = parsePatternRoute(pattern, route)
  const details: RouteDetails = {
    route: parsedRoute,
    patternId,
    stops: parsePatternStops(pattern.stops, pattern.pickups, pattern.dropoffs),
    polyline: decodePolyline6(asString(geometry.points6)),
    vehicles: parseRouteVehicles(realtimeRaw),
    alerts: alertsResult.status === "fulfilled" ? parseAlerts(alertsResult.value) : [],
    scheduledTrips: scheduleResult.status === "fulfilled" ? parseRouteTrips(scheduleResult.value, localDateKey()) : [],
    updatedAt: Date.now(),
    stale: false,
  }
  setCachedRouteDetails(details)
  return details
}

function placeParameter(place: JourneyPlace): string {
  return `${place.name}::${place.coordinate.latitude},${place.coordinate.longitude}`
}

function kavNavRouteId(routeId: string): string {
  return routeId.replace(/^1:/, "")
}

function parseIndexedStop(value: unknown, origin: Coordinate): TransitStop | null {
  const item = asRecord(value)
  const latitude = asNumber(item.lat)
  const longitude = asNumber(item.lon)
  const code = asString(item.code)
  if (latitude == null || longitude == null || !code) return null
  const coordinate = { latitude, longitude }
  return {
    id: asString(item.id, `1:${code}`),
    motStopId: asString(item.id).split(":").at(-1),
    code,
    name: asString(item.name, `תחנה ${code}`),
    address: asString(item.formatted_address),
    coordinate,
    distanceMeters: asNumber(item.dist) ?? Math.round(distanceMeters(origin, coordinate)),
    walkingDurationSeconds: Math.round((asNumber(item.dist) ?? distanceMeters(origin, coordinate)) / 1.3),
    heading: asNumber(item.heading),
    vehicleType: asNumber(item.vehicle_type),
  }
}

function parseSearchStop(value: unknown, origin?: Coordinate): TransitStop | null {
  const item = asRecord(value)
  const latitude = asNumber(item.latitude ?? item.lat)
  const longitude = asNumber(item.longitude ?? item.lon)
  const code = asString(item.stop_code ?? item.code)
  if (latitude == null || longitude == null || !code) return null
  const coordinate = { latitude, longitude }
  const rawId = asString(item.stop_id ?? item.id, code)
  return {
    id: rawId.includes(":") ? rawId : `1:${rawId}`,
    motStopId: rawId.includes(":") ? rawId.split(":").at(-1) : rawId,
    code,
    name: asString(item.stop_name ?? item.name, `תחנה ${code}`),
    address: asString(item.address ?? item.formatted_address),
    coordinate,
    distanceMeters: origin ? Math.round(distanceMeters(origin, coordinate)) : null,
    walkingDurationSeconds: origin ? Math.round(distanceMeters(origin, coordinate) / 1.3) : null,
    heading: null,
    vehicleType: asNumber(item.vehicle_type),
  }
}

function parseRoutes(raw: unknown): TransitRoute[] {
  const summary = asRecord(asArray(raw)[0])
  return asArray(summary.routes).map((value, index) => {
    const item = asRecord(value)
    return {
      id: asString(item.routeId),
      number: asString(item.routeNumber, asString(item.code)),
      longName: asString(item.routeLongName),
      headsign: asString(item.headsign),
      operatorName: asString(item.operatorId),
      color: normalizeRouteColor(asString(item.color)) ?? ROUTE_COLORS[index % ROUTE_COLORS.length],
      direction: asString(item.direction),
      alternative: asString(item.alternative),
      isCircular: asBoolean(item.isCircular),
    }
  }).filter(route => route.id.length > 0 && route.number.length > 0)
}

async function enrichRoutes(existing: TransitRoute[], scheduleRaw: unknown, date: string): Promise<TransitRoute[]> {
  const routeIds = uniqueBy(
    asArray(asRecord(scheduleRaw).stopSchedule)
      .flatMap(value => asArray(asRecord(value).trips))
      .map(value => asString(asRecord(value).routeId))
      .filter(Boolean),
    value => value,
  )
  const existingIds = new Set(existing.map(route => route.id))
  const cached = routeIds
    .filter(routeId => !existingIds.has(routeId))
    .map(getCachedRoute)
    .filter(isPresent)
  const knownIds = new Set([...existingIds, ...cached.map(route => route.id)])
  const missing = routeIds.filter(routeId => !knownIds.has(routeId)).slice(0, 10)
  const fetched = await Promise.allSettled(missing.map(routeId => loadRouteMetadata(routeId, date)))
  const parsed = fetched.flatMap(result => result.status === "fulfilled" && result.value ? [result.value] : [])
  return uniqueBy([...existing, ...cached, ...parsed], route => route.id)
}

function loadRouteMetadata(routeId: string, date: string): Promise<TransitRoute | null> {
  const existing = routeMetadataRequests.get(routeId)
  if (existing) return existing
  const request = kavnavClient.route(routeId, date).then(raw => {
    const route = parseRequestedRoute(raw, routeId)
    if (route) setCachedRoute(route)
    return route
  }).finally(() => routeMetadataRequests.delete(routeId))
  routeMetadataRequests.set(routeId, request)
  return request
}

function parseRequestedRoute(raw: unknown, requestedRouteId: string): TransitRoute | null {
  const candidates = asArray(asRecord(raw).routes).map(asRecord)
  const item = candidates.find(route => asString(route.routeId) === requestedRouteId) ?? candidates[0]
  if (!item) return null
  const id = asString(item.routeId, requestedRouteId)
  const number = asString(item.routeNumber, asString(item.code))
  if (!id || !number) return null
  return {
    id,
    number,
    longName: asString(item.routeLongName),
    headsign: asString(item.direction),
    operatorName: asString(item.operatorId),
    color: normalizeRouteColor(asString(item.color)),
    direction: asString(item.direction),
    alternative: asString(item.alternative),
    isCircular: asBoolean(item.isCircular),
  }
}

function parseRealtimeArrivals(raw: unknown, stopCode: string): TransitArrival[] {
  const vehicles = asArray(asRecord(raw).vehicles)
  return vehicles.map(value => {
    const vehicle = asRecord(value)
    const trip = asRecord(vehicle.trip)
    const gtfs = asRecord(trip.gtfsInfo)
    const calls = asArray(asRecord(trip.onwardCalls).calls).map(asRecord)
    const matchingCall = calls.find(call => asString(call.stopCode) === stopCode)
    const nextCall = asRecord(trip.nextCall)
    const expectedAt = parseTimestamp(matchingCall?.eta)
      ?? (asString(nextCall.stopCode) === stopCode ? parseTimestamp(asRecord(trip.departure).departureTime) : null)
    if (expectedAt == null || expectedAt < Date.now() - 60_000) return null
    const geo = asRecord(vehicle.geo)
    const location = asRecord(geo.location)
    const latitude = asNumber(location.lat)
    const longitude = asNumber(location.lon)
    const scheduledAt = parseTimestamp(trip.plannedDepartureTime) ?? expectedAt
    const lastReportedAt = parseTimestamp(vehicle.lastReported) ?? parseTimestamp(geo.lastUpdated)
    return {
      id: `rt:${asString(vehicle.vehicleId)}:${stopCode}:${expectedAt}`,
      routeId: asString(trip.routeId),
      routeNumber: asString(gtfs.routeNumber),
      headsign: asString(gtfs.headsign),
      expectedAt,
      scheduledAt,
      realtime: true,
      delayMinutes: asNumber(asRecord(trip.departure).delayMinutes),
      vehicleId: asString(vehicle.vehicleId) || null,
      vehicleCoordinate: latitude != null && longitude != null ? { latitude, longitude } : null,
      distanceFromStop: asNumber(nextCall.distanceFromStop),
      lastReportedAt,
      realtimeState: asString(trip.confidenceLevel) || null,
      wheelchairAccessible: null,
      platform: null,
      confidenceLevel: confidenceNumber(trip.confidenceLevel),
      freshness: realtimeFreshness(lastReportedAt),
    } satisfies TransitArrival
  }).filter(isPresent)
}

function parseScheduledArrivals(raw: unknown, routes: TransitRoute[], date: string): TransitArrival[] {
  const schedule = asArray(asRecord(raw).stopSchedule)
  const routeById = new Map(routes.map(route => [route.id, route]))
  return schedule.flatMap(value => asArray(asRecord(value).trips)).map(value => {
    const trip = asRecord(value)
    const departureAt = serviceTimeToTimestamp(date, asString(trip.departureTime))
    if (departureAt == null || departureAt < Date.now() - 60_000) return null
    const routeId = asString(trip.routeId)
    const route = routeById.get(routeId)
    return {
      id: `sc:${asString(trip.tripId)}:${departureAt}`,
      routeId,
      routeNumber: route?.number ?? "—",
      headsign: asString(trip.headsign, route?.headsign ?? ""),
      expectedAt: departureAt,
      scheduledAt: departureAt,
      realtime: false,
      delayMinutes: null,
      vehicleId: null,
      vehicleCoordinate: null,
      distanceFromStop: null,
      lastReportedAt: null,
      realtimeState: null,
      wheelchairAccessible: null,
      platform: null,
      confidenceLevel: null,
      freshness: "scheduled",
    } satisfies TransitArrival
  }).filter(isPresent)
}

function mergeArrivals(realtime: TransitArrival[], scheduled: TransitArrival[]): TransitArrival[] {
  const realtimeKeys = new Set(realtime.map(item => `${item.routeId}:${Math.round(item.scheduledAt / 300_000)}`))
  return [...realtime, ...scheduled.filter(item => !realtimeKeys.has(`${item.routeId}:${Math.round(item.scheduledAt / 300_000)}`))]
    .sort((left, right) => left.expectedAt - right.expectedAt)
}

function parseAlerts(raw: unknown): TransitAlert[] {
  return asArray(asRecord(raw).alerts).map(value => {
    const item = asRecord(value)
    return {
      id: asString(item.alertId),
      title: localizedText(item.header, "עדכון שירות"),
      description: localizedText(item.description, ""),
      updatedAt: parseTimestamp(item.updatedAt),
    }
  }).filter(alert => alert.id.length > 0 && alert.title.length > 0)
}

function localizedText(value: unknown, fallback: string): string {
  const item = asRecord(value)
  return asString(item.he) || asString(item.en) || asString(item.ar) || fallback
}

function parsePatternRoute(pattern: Record<string, unknown>, fallback: TransitRoute): TransitRoute {
  const route = asRecord(pattern.route)
  const agency = asRecord(route.agency)
  return {
    id: fallback.id || asString(route.id),
    number: asString(route.shortName, fallback.number),
    longName: asString(route.longName, fallback.longName),
    headsign: asString(pattern.headsign, fallback.headsign),
    operatorName: asString(agency.name, fallback.operatorName),
    color: normalizeRouteColor(asString(route.color)) ?? fallback.color,
    textColor: normalizeRouteColor(asString(route.textColor)),
    mode: asString(route.mode),
    direction: asString(pattern.direction),
    alternative: asString(pattern.motAlternative),
  }
}

function parsePatternStops(raw: unknown, pickupsRaw?: unknown, dropoffsRaw?: unknown): RouteStop[] {
  const pickups = asArray(pickupsRaw).map(value => asNumber(value))
  const dropoffs = asArray(dropoffsRaw).map(value => asNumber(value))
  return asArray(raw).map((value, index) => {
    const item = asRecord(value)
    const latitude = asNumber(item.lat)
    const longitude = asNumber(item.lon)
    const code = asString(item.code)
    if (latitude == null || longitude == null || !code) return null
    return {
      id: asString(item.id, `1:${code}`),
      motStopId: asString(item.id).split(":").at(-1),
      code,
      name: asString(item.name, `תחנה ${code}`),
      address: asString(item.formatted_address),
      coordinate: { latitude, longitude },
      distanceMeters: null,
      walkingDurationSeconds: null,
      heading: asNumber(item.heading),
      vehicleType: asNumber(item.vehicle_type),
      sequence: index,
      pickupAllowed: pickups[index] == null ? undefined : pickups[index] === 0,
      dropoffAllowed: dropoffs[index] == null ? undefined : dropoffs[index] === 0,
    } satisfies RouteStop
  }).filter(isPresent)
}

function realtimeFreshness(lastReportedAt: number | null): "live" | "delayed" | "stale" {
  if (lastReportedAt == null) return "delayed"
  const ageSeconds = Math.max(0, (Date.now() - lastReportedAt) / 1_000)
  if (ageSeconds <= 90) return "live"
  if (ageSeconds <= 300) return "delayed"
  return "stale"
}

function confidenceNumber(value: unknown): number | null {
  const numeric = asNumber(value)
  if (numeric != null) return numeric
  const normalized = asString(value).toLowerCase()
  if (normalized === "high") return 1
  if (normalized === "medium") return 0.65
  if (normalized === "low") return 0.3
  return null
}

function parseRouteTrips(raw: unknown, date: string): RouteTrip[] {
  return asArray(asRecord(raw).trips).map(value => {
    const item = asRecord(value)
    const departureAt = serviceTimeToTimestamp(date, asString(item.departureTime))
    if (departureAt == null || departureAt < Date.now() - 60_000) return null
    return {
      id: asString(item.tripId, `${departureAt}`),
      headsign: asString(item.headsign),
      departureAt,
    }
  }).filter(isPresent).sort((left, right) => left.departureAt - right.departureAt).slice(0, 12)
}

function parseJourneyPlans(raw: unknown): JourneyPlan[] {
  const plan = asRecord(asRecord(raw).plan)
  return asArray(plan.itineraries).map((value, itineraryIndex) => {
    const item = asRecord(value)
    const legs = asArray(item.legs).map((legValue, legIndex) => parseJourneyLeg(legValue, itineraryIndex, legIndex)).filter(isPresent)
    const startAt = parseTimestamp(item.startTime)
    const endAt = parseTimestamp(item.endTime)
    if (startAt == null || endAt == null) return null
    const alertCount = legs.reduce((sum, leg) => sum + leg.alertCount, 0)
    return {
      id: `journey:${startAt}:${endAt}:${itineraryIndex}`,
      startAt,
      endAt,
      durationSeconds: asNumber(item.duration) ?? Math.max(0, (endAt - startAt) / 1_000),
      transfers: asNumber(item.transfers) ?? Math.max(0, legs.filter(leg => leg.routeNumber).length - 1),
      walkDurationSeconds: asNumber(item.walkTime) ?? 0,
      walkDistanceMeters: asNumber(item.walkDistance) ?? 0,
      legs,
      hasRealtime: legs.some(leg => leg.realtime),
      alertCount,
    }
  }).filter(isPresent)
}

function parseJourneyLeg(value: unknown, itineraryIndex: number, legIndex: number): JourneyLeg | null {
  const item = asRecord(value)
  const startAt = parseTimestamp(item.startTime)
  const endAt = parseTimestamp(item.endTime)
  if (startAt == null || endAt == null) return null
  const from = asRecord(item.from)
  const to = asRecord(item.to)
  const intermediateStopNames = asArray(item.intermediateStops).map(stop => asString(asRecord(stop).name)).filter(Boolean)
  const alerts = asArray(item.alerts)
  return {
    id: `leg:${itineraryIndex}:${legIndex}:${startAt}`,
    mode: asString(item.mode, "WALK"),
    fromName: asString(from.name),
    toName: asString(to.name),
    startAt,
    endAt,
    durationSeconds: asNumber(item.duration) ?? Math.max(0, (endAt - startAt) / 1_000),
    distanceMeters: asNumber(item.distance) ?? 0,
    routeNumber: asString(item.routeShortName, asString(item.route)) || undefined,
    headsign: asString(item.headsign) || undefined,
    realtime: asBoolean(item.realTime),
    intermediateStopNames,
    alertCount: alerts.length,
  }
}

function parseRouteVehicles(raw: unknown): RouteVehicle[] {
  return asArray(asRecord(raw).vehicles).map(value => {
    const item = asRecord(value)
    const geo = asRecord(item.geo)
    const location = asRecord(geo.location)
    const latitude = asNumber(location.lat)
    const longitude = asNumber(location.lon)
    if (latitude == null || longitude == null) return null
    return {
      id: asString(item.vehicleId),
      coordinate: { latitude, longitude },
      bearing: asNumber(geo.bearing),
      speed: asNumber(geo.speed),
      updatedAt: parseTimestamp(item.lastReported),
    } satisfies RouteVehicle
  }).filter(isPresent)
}

function normalizeRouteColor(value: string): string | null {
  const hex = value.replace(/^#/, "").trim()
  return /^[0-9a-fA-F]{6}$/.test(hex) ? `#${hex}` : null
}

function isPresent<T>(value: T | null): value is T {
  return value != null
}
