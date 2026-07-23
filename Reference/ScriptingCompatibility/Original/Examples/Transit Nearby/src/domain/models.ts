export type Coordinate = {
  latitude: number
  longitude: number
}

export type TransitStop = {
  id: string
  motStopId?: string
  code: string
  name: string
  address: string
  city?: string
  coordinate: Coordinate
  distanceMeters: number | null
  walkingDurationSeconds?: number | null
  heading?: number | null
  vehicleType: number | null
}

export type TransitRoute = {
  id: string
  number: string
  longName: string
  headsign: string
  operatorName: string
  color: string | null
  textColor?: string | null
  mode?: string
  direction?: string
  alternative?: string
  isCircular?: boolean
}

export type RealtimeFreshness = "live" | "delayed" | "stale" | "scheduled"

export type TransitArrival = {
  id: string
  routeId: string
  routeNumber: string
  headsign: string
  expectedAt: number
  scheduledAt: number
  realtime: boolean
  delayMinutes: number | null
  vehicleId: string | null
  vehicleCoordinate: Coordinate | null
  distanceFromStop: number | null
  lastReportedAt?: number | null
  realtimeState?: string | null
  wheelchairAccessible?: boolean | null
  platform?: string | null
  confidenceLevel?: number | null
  freshness: RealtimeFreshness
}

export type TransitAlert = {
  id: string
  title: string
  description: string
  updatedAt: number | null
}

export type StopBoard = {
  stop: TransitStop
  routes: TransitRoute[]
  arrivals: TransitArrival[]
  alerts: TransitAlert[]
  updatedAt: number
  hasRealtime: boolean
  stale: boolean
  warningMessage?: string | null
}

export type RouteStop = TransitStop & {
  sequence: number
  pickupAllowed?: boolean
  dropoffAllowed?: boolean
}

export type RouteVehicle = {
  id: string
  coordinate: Coordinate
  bearing: number | null
  speed: number | null
  updatedAt: number | null
}

export type RouteDetails = {
  route: TransitRoute
  patternId: string
  stops: RouteStop[]
  polyline: Coordinate[]
  vehicles: RouteVehicle[]
  alerts: TransitAlert[]
  scheduledTrips: RouteTrip[]
  updatedAt: number
  stale: boolean
}

export type RouteTrip = {
  id: string
  headsign: string
  departureAt: number
}

export type FavoriteRoute = {
  type: "route"
  route: TransitRoute
}

export type RecentSearch = {
  id: string
  title: string
  subtitle: string
  kind: "stop" | "route" | "place"
  savedAt: number
}

export type JourneyPlace = {
  name: string
  coordinate: Coordinate
}

export type JourneyLeg = {
  id: string
  mode: string
  fromName: string
  toName: string
  startAt: number
  endAt: number
  durationSeconds: number
  distanceMeters: number
  routeNumber?: string
  headsign?: string
  realtime: boolean
  intermediateStopNames: string[]
  alertCount: number
}

export type JourneyPlan = {
  id: string
  startAt: number
  endAt: number
  durationSeconds: number
  transfers: number
  walkDurationSeconds: number
  walkDistanceMeters: number
  legs: JourneyLeg[]
  hasRealtime: boolean
  alertCount: number
}

export type ViewState<T> =
  | { status: "idle" }
  | { status: "loading"; previous?: T }
  | { status: "loaded"; data: T; refreshedAt: number; stale: boolean }
  | { status: "empty" }
  | { status: "error"; message: string; previous?: T }

export type TransitActivityState = {
  activityId?: string
  stopCode: string
  stopName: string
  routeNumber: string
  headsign: string
  expectedAt: number
  scheduledAt: number
  delayMinutes: number | null
  distanceFromStop: number | null
  updatedAt: number
  upcoming: Array<{
    routeNumber: string
    headsign: string
    expectedAt: number
    realtime: boolean
  }>
}

export type WidgetSnapshot = {
  stops: TransitStop[]
  selectedIndex: number
  board: StopBoard | null
  errorMessage: string | null
}
