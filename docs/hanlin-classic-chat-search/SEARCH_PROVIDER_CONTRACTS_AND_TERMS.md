# Search Provider Contracts, Quotas, and Terms (Hardened)

**Document Version:** 1.1.0  
**Verification Date:** 2026-10-21  
**Status:** Live Diagnostic Verified & Hardened (Non-Commercial / Experimental Free Tier)  
**Authoritative Coordinator:** `AutomaticWebSearchCoordinator`  

---

## 1. Provider Architecture & Reliability Pipeline

Hanlin AI implements a single virtual provider, **`Automatic (Free Web Search)`** (`AUTOMATIC_KEYLESS`), managing three ordered keyless backends:

```
                            [ User Search Query ]
                                      │
                                      ▼
                   ┌──────────────────────────────────────┐
                   │   AutomaticWebSearchCoordinator      │
                   │   - 10s Structured Hard Deadline     │
                   │   - Strict Circuit Breaker Cooldown  │
                   │   - 5-Min Canonical Token Cache      │
                   │   - Canonical URL Deduplication      │
                   └──────────────────┬───────────────────┘
                                      │
                                      ▼
                   ┌──────────────────────────────────────┐
                   │    WebSearchRelevanceEvaluator       │
                   │    - Token Relevance Scoring         │
                   │    - Intent Mismatch Defense         │
                   │    - Hotel/Card Game Spam Filtering  │
                   └──────────────────┬───────────────────┘
                                      │
             ┌────────────────────────┼────────────────────────┐
             ▼ (Tier 1)               ▼ (Tier 2 Fallback)      ▼ (Tier 3 Fallback)
    ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
    │     You.com     │      │     Tavily      │      │    Keenable     │
    │     Keyless     │      │     Keyless     │      │     Public      │
    │ (~100 / day/IP) │      │ (Access-Mode)   │      │ (Research Pro)  │
    └─────────────────┘      └─────────────────┘      └─────────────────┘
```

---

## 2. Hardened Reliability & Fallback Mechanics

### 2.1 Strict Cooldown Enforcement & Circuit Breaking
* **Eligibility Filter:** Before querying backends, `executeFallbackLoop` strictly filters providers where `health.isAvailable(at: now)` is `true`. Cooled-down providers are **never** invoked while their cooldown is active.
* **All-Cooldown Outcome:** If all backends are on cooldown, the coordinator deterministically throws `AutomaticSearchError.allProvidersOnCooldown(retryAfter: waitSeconds)` where `waitSeconds` is the delta until the earliest provider recovers.
* **Cooldown Durations:**
  - Standard transient network failure: $60\text{s} \times \min(\text{failureCount}, 5)$.
  - Rate limit (HTTP 429) without `Retry-After`: $120\text{s}$.
  - Authorization / Policy rejection (HTTP 401/403): $3600\text{s}$ (1 hour) extended cooldown to prevent endpoint abuse.

### 2.2 Dual-Format `Retry-After` Header Parsing
The coordinator uses `HTTPHeaderParser.parseRetryAfter(from: response)` supporting:
1. **Delta-Seconds (RFC 7231 §7.1.3):** Integer e.g. `"120"`.
2. **HTTP-Date (RFC 7231 §7.1.1.1):** Formats including RFC 1123 / RFC 2822 (`"Wed, 21 Oct 2026 07:28:00 GMT"`), RFC 850, and ANSI C `asctime()`.
3. **Safety Bounds:** Values are strictly clamped between $5.0\text{s}$ and $3600.0\text{s}$ to prevent negative delays or unbounded stalls.

### 2.3 Topical Relevance & Intent Mismatch Defense
`WebSearchRelevanceEvaluator` inspects returned result sets before acceptance:
* **Token Matching:** Extracts significant alphanumeric tokens ($\ge 2$ characters), excluding English and Hebrew stopwords.
* **Intent Mismatch Detection:**
  - **Torah / Zmanim Protection:** Queries containing prayer or Torah terms (`"תפילה"`, `"זמני"`, `"פרשת"`, `"הלכה"`) that return results containing commercial hotel keywords (`"hotel"`, `"booking"`, `"מלון"`) without religious/halachic relevance are **rejected** as intent mismatches.
  - **Developer Query Protection:** Technical queries (`"SwiftUI"`, `"iOS SDK"`) returning card game bridge results without developer terms are **rejected**.
* **Fallback Trigger:** If a provider returns structurally valid HTTP 200 responses that fail topical relevance, the coordinator rejects them as `AutomaticSearchError.irrelevantResults` and seamlessly advances to the next provider within the deadline budget.

### 2.4 Structured Hard Deadline Concurrency
* The search operation is raced against a deadline task inside a `withThrowingTaskGroup`.
* If the 10-second overall deadline expires before completion, the group cancels the active network task immediately, avoiding orphan background requests.
* Per-provider request timeouts are bounded to 4.0 seconds.

---

## 3. Detailed Endpoint Contracts

### 3.1 Tier 1: You.com Keyless
* **Endpoint:** `GET https://api.you.com/v1/agents/search`
* **Query Params:** `query=<encodedQuery>&count=<1..10>`
* **Headers:** `Accept: application/json`, `User-Agent: HanlinAI/1.0`
* **Decoding:** Parses `results.web[]` with `url`, `title`, `description`, `snippets` (flexible decoding supporting `String` or `[String]`), `favicon_url`, `thumbnail_url`.
* **Observed Quota:** ~100 queries/day per public IP.

### 3.2 Tier 2: Tavily Keyless
* **Endpoint:** `POST https://api.tavily.com/search`
* **Headers:** `Content-Type: application/json; charset=utf-8`, `x-tavily-access-mode: keyless`, `User-Agent: HanlinAI/1.0`
* **Body:** `{"query": "...", "max_results": 5}`
* **Decoding:** Parses `results[]` with `title`, `url`, `content`, `score`.

### 3.3 Tier 3: Keenable Public
* **Endpoint:** `POST https://api.keenable.ai/v1/search/public`
* **Headers:** `Content-Type: application/json; charset=utf-8`, `X-Keenable-Title: HanlinAI-App`, `User-Agent: HanlinAI/1.0`
* **Body:** `{"query": "...", "max_results": 5}`
* **Decoding:** Parses `results[]` with `title`, `url`, `snippet`, `description`, `acquired_at`.

---

## 4. Production Permissions & Terms Notice

1. **Experimental Verification vs Commercial Authorization:** The three endpoints were verified live on 2026-10-21. However, free keyless access does **not** grant unlimited commercial rights or contractual SLA.
2. **Carrier NAT Caveat:** Free quotas are enforced per public IP. On cellular networks (CGNAT), multiple mobile devices may share an IP address, meaning individual user quotas may be constrained by carrier peers.
3. **User Paid Credentials Respected:** Any user-configured API key (Zhipu, Bocha, Tavily, Exa, Brave, Perplexity) remains strictly preserved and takes precedence when active.
