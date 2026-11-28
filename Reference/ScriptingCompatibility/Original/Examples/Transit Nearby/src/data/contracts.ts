// Raw API contracts mirrored from the supplied captures. These types stay in
// the data layer; screens consume only normalized domain models.

export type KavNavRealtimeResponse = {
  reportingBuses: number
  staleBuses: number
  lastVehicleReport: string
  lastSnapshot: string
  vehicles: unknown[]
  appliedFilters: { stopCode: string | null; routeCode: string | null } | null
}

export type KavNavStopSummaryResponse = Array<{
  stopId: string
  routes: unknown[]
  shapeIdsByRoute: Record<string, string[]>
  headways: Record<string, unknown[]>
  neighbors: unknown[]
  restrictions: Record<string, unknown>
}>

export type KavNavStopScheduleResponse = {
  stopSchedule: Array<{ stopId: string; trips: unknown[] }>
  minDate: string
  maxDate: string
}

export type KavNavRouteResponse = {
  routes: unknown[]
  routeChanges: Record<string, unknown[]>
  headways: Record<string, unknown[]>
  pois: Record<string, unknown[]>
  neighbors: Record<string, unknown[]>
  minDate: string
  maxDate: string
}

export type KavNavRouteScheduleResponse = {
  trips: unknown[]
  serviceExceptions: unknown[]
  stopTimes: Record<string, unknown[]>
  minDate: string
  maxDate: string
}

export type KavNavAlertsResponse = {
  alerts: unknown[]
  lastUpdatedAt: string
}

export type BusNearbyStopSearchItem = {
  latitude: number
  longitude: number
  stop_name: string
  stop_id: string
  stop_code: string
  address: string
  location_type: number
  vehicle_type: number
}

export type BusNearbyIndexedStop = {
  id: string
  code: string
  name: string
  formatted_address: string
  lat: number
  lon: number
  dist?: number
  heading: number
  vehicle_type: number
}

export type BusNearbyGeometryResponse = {
  length: number
  points6: string
}

export type BusNearbyPlanResponse = {
  plan?: {
    from: Record<string, unknown>
    to: Record<string, unknown>
    date: number
    itineraries: unknown[]
  }
}
