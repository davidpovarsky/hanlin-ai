# Search Provider Contracts, Quotas, and Terms

**Document Version:** 1.0.0  
**Verification Date:** 2026-10-21  
**Status:** Live Diagnostic Verified (Non-Commercial / Experimental Free Tier)  
**Authoritative Coordinator:** `AutomaticWebSearchCoordinator`  

---

## 1. Provider Contract Overview

Hanlin AI implements a virtual provider, **`Automatic (Free Web Search)`** (`AUTOMATIC_KEYLESS`), which manages three ordered backends. Each backend communicates via native Swift `URLSession` adapters using typed `Codable` DTOs with strict input validation, timeouts, and error mappings.

```
                              [ User Search Query ]
                                       │
                                       ▼
                     ┌──────────────────────────────────┐
                     │  AutomaticWebSearchCoordinator   │
                     │  - 10s Overall Bounded Deadline  │
                     │  - Ephemeral Circuit Breaker     │
                     │  - 5-Min Local TTL Query Cache   │
                     │  - Canonical URL Deduplication   │
                     └─────────────────┬────────────────┘
                                       │
             ┌─────────────────────────┼─────────────────────────┐
             ▼ (Tier 1)                ▼ (Tier 2 Fallback)       ▼ (Tier 3 Fallback)
    ┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
    │     You.com     │       │     Tavily      │       │    Keenable     │
    │     Keyless     │       │     Keyless     │       │     Public      │
    └─────────────────┘       └─────────────────┘       └─────────────────┘
```

---

## 2. Backend Technical Specifications

### 2.1 Tier 1: You.com Keyless Search

- **Endpoint URL:** `https://api.you.com/v1/agents/search`
- **HTTP Method:** `GET`
- **Query Parameters:**
  - `query`: URL percent-encoded search query (supports full UTF-8 Unicode Hebrew & English).
  - `count`: Integer requested results count (bounded to 1–10, default 5).
- **Request Headers:**
  - `Accept: application/json`
  - `User-Agent: HanlinAI/1.0`
- **Authentication:** None (Keyless).
- **Observed Response Schema:**
  ```json
  {
    "results": {
      "web": [
        {
          "url": "https://developer.apple.com/swiftui/",
          "title": "SwiftUI - Apple Developer",
          "description": "SwiftUI is an innovative...",
          "snippets": "SwiftUI uses a declarative syntax...",
          "thumbnail_url": "https://developer.apple.com/news/images/og/swiftui-og.png",
          "favicon_url": "https://you.com/favicon?domain=developer.apple.com&size=128"
        }
      ]
    },
    "metadata": {
      "latency": 0.218
    }
  }
  ```
- **Live Verification Metrics (2026-10-21):**
  - Query: `"SwiftUI"` → HTTP 200, 2 results, 218ms latency.
  - Query: `"זמני תפילה ירושלים"` → HTTP 200, valid Hebrew Torah/Zmanim sites returned.
- **Observed Limits & Quotas:** Published free fair-use allowance is approximately **100 searches/day per IP**.
- **Compliance & Terms Caveat:** Keyless endpoint is provided for developer evaluation and fair use. High-volume, commercial distribution or automated bulk scraping is not permitted. Revalidate commercial terms prior to wide TestFlight/App Store distribution.

---

### 2.2 Tier 2: Tavily Keyless Search

- **Endpoint URL:** `https://api.tavily.com/search`
- **HTTP Method:** `POST`
- **Request Headers:**
  - `Content-Type: application/json; charset=utf-8`
  - `x-tavily-access-mode: keyless`
  - `User-Agent: HanlinAI/1.0`
- **Request Body:**
  ```json
  {
    "query": "זמני תפילה ירושלים",
    "max_results": 5
  }
  ```
- **Authentication:** None (`x-tavily-access-mode: keyless` header).
- **Observed Response Schema:**
  ```json
  {
    "query": "זמני תפילה ירושלים",
    "results": [
      {
        "url": "https://...",
        "title": "זמני היום בירושלים...",
        "content": "זמני תפילה וזמנים הלכתיים...",
        "score": 0.98
      }
    ]
  }
  ```
- **Live Verification Metrics (2026-10-21):**
  - Query: `"SwiftUI"` → HTTP 200, 2 results.
  - Query: `"זמני תפילה ירושלים"` → HTTP 200, highly relevant Hebrew results.
- **Observed Limits & Quotas:** Rate-limited on high concurrency; returns HTTP 429 when threshold exceeded. Long-term volume and redistribution terms are not contractually guaranteed.
- **Compliance & Terms Caveat:** Keyless mode is an unauthenticated fallback mode. Commercial distribution requires an official paid Tavily API key.

---

### 2.3 Tier 3: Keenable Public Search

- **Endpoint URL:** `https://api.keenable.ai/v1/search/public`
- **HTTP Method:** `POST`
- **Request Headers:**
  - `Content-Type: application/json; charset=utf-8`
  - `X-Keenable-Title: HanlinAI-App`
  - `User-Agent: HanlinAI/1.0`
- **Request Body:**
  ```json
  {
    "query": "SwiftUI",
    "max_results": 5
  }
  ```
- **Authentication:** Application title identification (`X-Keenable-Title`).
- **Observed Response Schema:**
  ```json
  {
    "query": "SwiftUI",
    "mode": "pro",
    "results": [
      {
        "title": "SwiftUI - Apple Developer",
        "url": "https://developer.apple.com/swiftui",
        "snippet": "SwiftUI helps you build great-looking apps...",
        "description": "",
        "acquired_at": "2026-09-27T17:10:50Z"
      }
    ]
  }
  ```
- **Live Verification Metrics (2026-10-21):**
  - Query: `"SwiftUI"` → HTTP 200, rich developer documentation snippets returned.
  - Query: `"זמני תפילה ירושלים"` → HTTP 200, Hebrew titles returned.
- **Observed Limits & Quotas:** Public research endpoint. Not intended as a high-throughput primary search engine. Bounded by provider IP rate limits.

---

## 3. Disallowed and Rejected Scraping Alternatives

Direct scraping of consumer search engines was experimentally evaluated and **strictly rejected** from production architecture for the following definitive technical and security reasons:

| Rejected Provider / Method | Diagnostic Observation | Technical & Policy Barrier |
| :--- | :--- | :--- |
| **DuckDuckGo HTML / Lite** | HTTP 202 (CAPTCHA Challenge) | Cloudflare bot protection; blocks automated client requests immediately. |
| **Brave Search HTML** | HTTP 429 (Too Many Requests) | IP rate limit triggered on initial unauthenticated probes. |
| **Google Search HTML** | HTTP 200 with consent/interstitial | Returns consent/reCAPTCHA wall; no extractable structured search results. |
| **Bing HTML / RSS** | High rate of irrelevant ads & spam | Inconsistent result structure, violates App Store guideline 5.1.1 on unconsented scraping. |

> [!IMPORTANT]
> **No WebKit / HTML Scraping Policy:** All search requests in Hanlin AI use isolated REST API endpoints with structured JSON schemas. No browser scraping, WebKit headless sessions, or CAPTCHA circumvention techniques are employed.

---

## 4. Production Readiness & Legal Notice

1. **Experimental vs. Production Status:** The three keyless endpoints are verified functional on 2026-10-21. However, free keyless access does **not** grant unlimited capacity, guaranteed SLA, or indefinite future availability.
2. **Graceful Degradation:** When keyless quotas are exhausted or endpoints become unavailable, Hanlin AI fails gracefully:
   - Evaluates Tier 1 → Tier 2 → Tier 3.
   - If all tiers fail, surfaces an honest, structured error message (`AutomaticSearchError.allProvidersFailed`).
   - Does **not** hallucinate sources or fabricate citation links.
3. **User Paid Keys Always Respected:** Users who configure personal API keys for Zhipu, Bocha, Tavily, Exa, Brave, or Perplexity retain complete control, and automatic mode will not override their explicit preference.
