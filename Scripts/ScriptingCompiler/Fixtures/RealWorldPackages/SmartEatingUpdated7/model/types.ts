// model/types.ts — Type definitions

export interface Station {
  id: number
  name: string
  iconKey: string   // key into STATION_ICONS (e.g. "breakfast")
  timeStart: string
  timeEnd: string
  suggestions: string[]
}

export interface StationLog {
  stationId: number
  completedAt: number
  note: string
  points: number
}

export interface DayLog {
  date: string
  stations: StationLog[]
  totalPoints: number
}

export interface AppData {
  streak: number
  lastStreakDate: string
  history: DayLog[]
}