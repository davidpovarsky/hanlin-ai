export function localDateKey(date = new Date()): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

export function serviceTimeToTimestamp(dateKey: string, time: string): number | null {
  const dateParts = dateKey.split("-").map(Number)
  const timeParts = time.split(":").map(Number)
  if (dateParts.length !== 3 || timeParts.length < 2 || dateParts.some(Number.isNaN) || timeParts.some(Number.isNaN)) {
    return null
  }
  const [year, month, day] = dateParts
  const [rawHour, minute, second = 0] = timeParts
  const dayOffset = Math.floor(rawHour / 24)
  const hour = rawHour % 24
  return new Date(year, month - 1, day + dayOffset, hour, minute, second).getTime()
}

export function minutesUntil(timestamp: number, now = Date.now()): number {
  return Math.max(0, Math.round((timestamp - now) / 60_000))
}

export function arrivalLabel(timestamp: number, now = Date.now()): string {
  const minutes = minutesUntil(timestamp, now)
  if (minutes <= 1) return "עכשיו"
  return `עוד ${minutes} דק׳`
}

export function shortTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString("he-IL", {
    hour: "2-digit",
    minute: "2-digit",
  })
}

export function relativeUpdateLabel(timestamp: number): string {
  const minutes = Math.max(0, Math.floor((Date.now() - timestamp) / 60_000))
  if (minutes === 0) return "מעודכן עכשיו"
  if (minutes === 1) return "עודכן לפני דקה"
  return `עודכן לפני ${minutes} דקות`
}
