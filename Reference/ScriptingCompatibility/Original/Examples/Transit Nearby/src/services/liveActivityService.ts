import { LiveActivity } from "scripting"
import { TRANSIT_ACTIVITY_NAME, TransitArrivalActivity } from "../../live_activity"
import type { StopBoard, TransitActivityState, TransitArrival, TransitStop } from "../domain/models"
import { getActiveActivityId, setActiveActivityId } from "../storage/transitStorage"

function activityState(stop: TransitStop, arrival: TransitArrival, arrivals: TransitArrival[]): TransitActivityState {
  return {
    stopCode: stop.code,
    stopName: stop.name,
    routeNumber: arrival.routeNumber,
    headsign: arrival.headsign,
    expectedAt: arrival.expectedAt,
    scheduledAt: arrival.scheduledAt,
    delayMinutes: arrival.delayMinutes,
    distanceFromStop: arrival.distanceFromStop,
    updatedAt: Date.now(),
    upcoming: arrivals
      .filter(item => item.routeNumber === arrival.routeNumber && item.expectedAt >= arrival.expectedAt)
      .slice(0, 3)
      .map(item => ({
        routeNumber: item.routeNumber,
        headsign: item.headsign,
        expectedAt: item.expectedAt,
        realtime: item.realtime,
      })),
  }
}

export async function startArrivalActivity(
  stop: TransitStop,
  arrival: TransitArrival,
  arrivals: TransitArrival[] = [arrival],
): Promise<boolean> {
  if (!await LiveActivity.areActivitiesEnabled()) return false
  await endActiveArrivalActivity()
  const activity = TransitArrivalActivity()
  const state = activityState(stop, arrival, arrivals)
  const started = await activity.start(state, {
    staleDate: new Date(Math.min(arrival.expectedAt + 5 * 60_000, Date.now() + 30 * 60_000)),
    relevanceScore: 100,
  })
  if (started && activity.activityId) setActiveActivityId(activity.activityId)
  return started
}

export async function updateActiveArrivalActivity(board: StopBoard): Promise<void> {
  const activityId = getActiveActivityId()
  if (!activityId) return
  const activity = await LiveActivity.from<TransitActivityState>(activityId, TRANSIT_ACTIVITY_NAME)
  if (!activity) {
    setActiveActivityId(null)
    return
  }
  const first = board.arrivals[0]
  if (!first) {
    await activity.end({
      stopCode: board.stop.code,
      stopName: board.stop.name,
      routeNumber: "—",
      headsign: "אין נסיעות נוספות",
      expectedAt: Date.now(),
      scheduledAt: Date.now(),
      delayMinutes: null,
      distanceFromStop: null,
      updatedAt: Date.now(),
      upcoming: [],
    }, { dismissTimeInterval: 60 })
    setActiveActivityId(null)
    return
  }
  await activity.update(activityState(board.stop, first, board.arrivals), {
    staleDate: new Date(Math.min(first.expectedAt + 5 * 60_000, Date.now() + 30 * 60_000)),
    relevanceScore: 100,
  })
}

export async function endActiveArrivalActivity(): Promise<void> {
  const activityId = getActiveActivityId()
  if (!activityId) return
  const activity = await LiveActivity.from<TransitActivityState>(activityId, TRANSIT_ACTIVITY_NAME)
  if (activity) {
    const finalState: TransitActivityState = {
      stopCode: "",
      stopName: "המעקב הסתיים",
      routeNumber: "—",
      headsign: "",
      expectedAt: Date.now(),
      scheduledAt: Date.now(),
      delayMinutes: null,
      distanceFromStop: null,
      updatedAt: Date.now(),
      upcoming: [],
    }
    await activity.end(finalState, { dismissTimeInterval: 0 })
  }
  setActiveActivityId(null)
}
