export class TransitHttpError extends Error {
  constructor(
    message: string,
    readonly status: number | null,
    readonly category: "network" | "timeout" | "authentication" | "rateLimited" | "server" | "invalidResponse",
    readonly endpoint: string,
  ) {
    super(message)
    this.name = "TransitHttpError"
  }
}

type FetchJsonOptions = {
  headers?: Record<string, string>
  timeoutMs?: number
  retries?: number
  onAuthenticationFailure?: () => void
}

function wait(milliseconds: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, milliseconds))
}

export async function fetchJson<T = unknown>(
  url: string,
  debugLabel: string,
  options: FetchJsonOptions = {},
): Promise<T> {
  const endpoint = url.split("?")[0]
  const retries = Math.max(0, Math.min(2, options.retries ?? 1))

  for (let attempt = 0; attempt <= retries; attempt++) {
    let response: Response
    try {
      response = await fetch(url, {
        signal: AbortSignal.timeout(options.timeoutMs ?? 10_000),
        debugLabel,
        headers: { Accept: "application/json", ...options.headers },
      })
    } catch (error) {
      if (attempt < retries) {
        await wait(250 * 2 ** attempt)
        continue
      }
      const rawMessage = error instanceof Error ? error.message : String(error)
      const timeout = /abort|timeout/i.test(rawMessage)
      throw new TransitHttpError(
        timeout ? "הבקשה ארכה זמן רב מדי" : "לא ניתן להתחבר לרשת",
        null,
        timeout ? "timeout" : "network",
        endpoint,
      )
    }

    if (response.ok) {
      try {
        return await response.json() as T
      } catch {
        throw new TransitHttpError("התקבלה תשובה לא תקינה", response.status, "invalidResponse", endpoint)
      }
    }

    if (response.status === 401 || response.status === 403) {
      options.onAuthenticationFailure?.()
      throw new TransitHttpError("נדרש אימות מחדש מול BusNearby", response.status, "authentication", endpoint)
    }
    if (response.status === 429) {
      throw new TransitHttpError("בוצעו יותר מדי בקשות. נסה שוב בעוד רגע", 429, "rateLimited", endpoint)
    }
    if (response.status >= 500 && attempt < retries) {
      await wait(250 * 2 ** attempt)
      continue
    }

    let detail = ""
    try {
      detail = (await response.text()).trim().slice(0, 160)
    } catch {
      // A missing error body is expected on some gateways.
    }
    const suffix = detail && !/[A-Za-z0-9_-]{40,}/.test(detail) ? `: ${detail}` : ""
    throw new TransitHttpError(`השרת החזיר שגיאה ${response.status}${suffix}`, response.status, "server", endpoint)
  }

  throw new TransitHttpError("הבקשה נכשלה", null, "network", endpoint)
}
