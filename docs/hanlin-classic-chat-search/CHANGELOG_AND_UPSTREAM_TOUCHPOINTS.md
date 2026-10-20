# Changelog and Upstream Touchpoints (Hardened)

**Document Version:** 1.1.0  
**Date:** 2026-10-21  
**Target Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/classic-chat-native-composer-search`  

---

## 1. Overview of Hardened Changes

This release delivers the complete **Hardened Automatic Web Search System** (`You.com Keyless` → `Tavily Keyless` → `Keenable Public`), with strict circuit breaking, structured concurrency hard deadlines, adversarial relevance filtering, and deterministic migration.

In accordance with repository `AGENTS.md` ("Hanlin is an independent fork: maintainability and one authoritative implementation path matter more than preserving upstream touchpoints"):
- All search coordination, adapters, relevance evaluation, DTOs, and migration are encapsulated in dedicated downstream files.
- The 4 frozen Chat UI files (`ChatView.swift`, `ChatBubbleView.swift`, `ChatViewBottom.swift`, `ListView.swift`) remain **strictly untouched** pending owner authorization for Asana Gate `1219605282038660`.

---

## 2. Inventory of Touchpoints

### 2.1 Additive Downstream Files

| File Path | Description | Lines | Status |
| :--- | :--- | :--- | :--- |
| `AI_HLY/Services/ChatServices/AutomaticSearch/WebSearchResult.swift` | Canonical typed search result DTO, URL normalization, deduplication, and `ParsedSearchResult` synchronization. | 105 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/WebSearchRelevanceEvaluator.swift` | Topical relevance evaluator with English/Hebrew token scoring, intent mismatch detection, and hotel/card game spam defense. | 105 | **New** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/WebSearchProviderProtocol.swift` | Provider protocol, `AutomaticSearchError` definitions, and `HTTPHeaderParser` (delta-seconds & HTTP-date). | 115 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/YouKeylessSearchAdapter.swift` | REST client for `api.you.com/v1/agents/search` with HTTP 429/401/403 handling. | 150 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/TavilyKeylessSearchAdapter.swift` | REST client for `api.tavily.com/search` keyless mode with HTTP 429/401/403 handling. | 125 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/KeenablePublicSearchAdapter.swift` | REST client for `api.keenable.ai/v1/search/public` with HTTP 429/401/403 handling. | 125 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/AutomaticWebSearchCoordinator.swift` | Actor-isolated coordinator: 3-tier fallback, strict cooldown enforcement, structured concurrency hard deadline race, canonical token cache, and clock injection. | 330 | **Hardened** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/AutomaticSearchMigration.swift` | Single authoritative bootstrap/migration: default auto activation, manual provider preservation, and deduplication. | 85 | **Hardened** |
| `AI_HLYTests/AutomaticWebSearchTests.swift` | 12 comprehensive unit tests with thread-safe actor mocks, sanitized real JSON fixtures, adversarial relevance, fake clock cooldown, and migration. | 340 | **Hardened** |
| `docs/hanlin-classic-chat-search/*` | 4 comprehensive documents (Baseline Matrix, Provider Contracts, Test Matrix, Changelog). | ~550 | **Hardened** |

---

### 2.2 Modified Existing Files

| File Path | Exact Modification | Rationale |
| :--- | :--- | :--- |
| `AI_HLY/Services/ChatServices/WebSearchTool.swift` | Added `case AUTOMATIC_KEYLESS` to `SearchEngine`, routed in `searchTool`, added diagnostic test bypass in `testSearchAPI`. | Connects search tool and settings test to coordinator. |
| `AI_HLY/Services/ChatServices/APIManager.swift` | Added `guard isSearchEnabled()` check and deterministic provider resolution in `getActiveSearchEngine()`. | Respects user's global search toggle (`UserInfo.useSearch`) and prevents ambiguous provider selection. |
| `AI_HLY/Services/DataServices/InfoServices.swift` | Added `AUTOMATIC_SEARCH_KEY` with `isUsing: false` in template; added icon case. | Prevents template from overriding user choices on reload. |
| `AI_HLY/Services/DataServices/PreLoad.swift` | Delegated reconciliation directly to `AutomaticSearchMigration.reconcileDefaultProvider`. | Establishes single authoritative migration path. |
| `AI_HLY/SettingsView.swift` | Updated `noSearchKeys` to recognize that `AUTOMATIC_KEYLESS` requires no API key. | Eliminates false warning badge in settings. |
| `AI_HLY/Views/Components/APISettingView.swift` | Prioritized automatic in list, added free badge, allowed toggle without key, removed misleading "set API key" header for automatic mode, and added honest diagnostic test display. | Clean, truthful settings UX. |
| `AI_HLY/Resource/Localizable.xcstrings` | Added string units for `company_AUTOMATIC_KEYLESS`, `免费 (自动切换)`, and automatic service description in en, he, and zh-Hans. | Native multilingual support. |
