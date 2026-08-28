// ai/formatting.ts - AI Chat Formatting Utilities

export function formatTime(ts: number): string {
  const d = new Date(ts)
  return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
}

export function formatDate(ts: number): string {
  const d = new Date(ts)
  return String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0") + " " + formatTime(ts)
}

export function formatMessageCount(count: number): string {
  return count + " הודעות"
}

export function formatConversationAge(createdAt: number): string {
  const now = Date.now()
  const diff = now - createdAt
  const minutes = Math.floor(diff / (1000 * 60))
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)

  if (days > 0) {
    return `לפני ${days} ימים`
  }
  if (hours > 0) {
    return `לפני ${hours} שעות`
  }
  if (minutes > 0) {
    return `לפני ${minutes} דקות`
  }
  return "זה עתה"
}

export function truncateText(text: string, maxLength: number): string {
  if (text.length <= maxLength) return text
  return text.substring(0, maxLength).trim() + "..."
}

export function formatStreamingMessage(content: string): string {
  return content + " ..."
}