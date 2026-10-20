# Changelog and Upstream Touchpoints

**Document Version:** 1.0.0  
**Date:** 2026-10-21  
**Target Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `codex/classic-chat-native-composer-search`  

---

## 1. Overview of Changes

This implementation introduces the **Automatic Web Search System** (`You.com Keyless` → `Tavily Keyless` → `Keenable Public`), integrates it into Hanlin AI's runtime and settings, and documents the baseline restoration and modern composer architectures while respecting the Asana Chat UI freeze gate.

In accordance with repository `AGENTS.md` ("Prefer additive downstream modules plus narrow integration hooks"):
- All core search coordination, REST adapters, DTOs, caching, and migration logic are implemented in **new, isolated downstream files**.
- Existing upstream files were modified using **minimal, surgical hooks** to preserve future branch mergeability.
- The 4 frozen Chat UI files (`ChatView.swift`, `ChatBubbleView.swift`, `ChatViewBottom.swift`, `ListView.swift`) were **strictly preserved untouched** due to Asana Gate `1219605282038660`.

---

## 2. Inventory of File Touchpoints

### 2.1 Newly Added Files (Additive Downstream Architecture)

| File Path | Responsibility | Lines | Merge Risk |
| :--- | :--- | :--- | :--- |
| `AI_HLY/Services/ChatServices/AutomaticSearch/WebSearchResult.swift` | Canonical typed search result DTO, URL normalization, deduplication, and `ParsedSearchResult` synchronization. | 95 | **None (Zero upstream collision)** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/WebSearchProviderProtocol.swift` | Provider protocol contract and typed `AutomaticSearchError` definitions. | 65 | **None** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/YouKeylessSearchAdapter.swift` | REST client for `api.you.com/v1/agents/search`. | 145 | **None** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/TavilyKeylessSearchAdapter.swift` | REST client for `api.tavily.com/search` keyless mode. | 115 | **None** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/KeenablePublicSearchAdapter.swift` | REST client for `api.keenable.ai/v1/search/public`. | 120 | **None** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/AutomaticWebSearchCoordinator.swift` | Actor-isolated coordinator: 3-tier fallback, circuit breaker cooldowns, 5-min TTL cache, and diagnostic probes. | 225 | **None** |
| `AI_HLY/Services/ChatServices/AutomaticSearch/AutomaticSearchMigration.swift` | Default provider bootstrap and migration logic for fresh and existing databases. | 75 | **None** |
| `AI_HLYTests/AutomaticWebSearchTests.swift` | Full regression test suite (13 unit tests) covering fallback, caching, deduplication, Hebrew encoding, and migration. | 275 | **None** |
| `docs/hanlin-classic-chat-search/BASELINE_AND_PRESERVATION_MATRIX.md` | Full baseline mapping (`478cdd2c` vs SwiftChat Liquid Glass vs Asana gate). | ~130 | **None (Documentation)** |
| `docs/hanlin-classic-chat-search/SEARCH_PROVIDER_CONTRACTS_AND_TERMS.md` | Endpoint schemas, live diagnostic evidence, and provider terms. | ~140 | **None (Documentation)** |
| `docs/hanlin-classic-chat-search/TEST_MATRIX.md` | Test matrix detailing PASS, BLOCKED, and NOT_RUN states. | ~95 | **None (Documentation)** |
| `docs/hanlin-classic-chat-search/CHANGELOG_AND_UPSTREAM_TOUCHPOINTS.md` | This file. | ~100 | **None (Documentation)** |

---

### 2.2 Modified Existing Files (Surgical Touchpoints)

| File Path | Exact Modification | Diff Stats | Upstream Conflict Potential |
| :--- | :--- | :--- | :--- |
| `AI_HLY/Services/ChatServices/WebSearchTool.swift` | 1. Added `case AUTOMATIC_KEYLESS` to `SearchEngine` enum.<br>2. Added `case .AUTOMATIC_KEYLESS:` route in `searchTool(...)`.<br>3. Added diagnostic bypass in `testSearchAPI(...)`. | `+10 / -0` | **Extremely Low:** 3 localized switch-case additions. |
| `AI_HLY/Services/DataServices/InfoServices.swift` | 1. Added `AUTOMATIC_SEARCH_KEY` to `getSearchKeyList()`.<br>2. Added `case "AUTOMATIC_KEYLESS": return "defaultIcon"` to `getCompanyIcon`. | `+11 / -0` | **Extremely Low:** Additive list item and icon case. |
| `AI_HLY/Services/DataServices/PreLoad.swift` | Added default migration step before `context.save()`: activates automatic provider on fresh install, preserves valid user keys. | `+25 / -1` | **Low:** Self-contained logic block in database synchronization. |
| `AI_HLY/SettingsView.swift` | Updated `noSearchKeys` predicate to recognize `AUTOMATIC_KEYLESS` as valid without requiring an API key. | `+3 / -2` | **Extremely Low:** Single condition adjustment. |
| `AI_HLY/Views/Components/APISettingView.swift` | 1. Prioritized `AUTOMATIC_KEYLESS` in `sortedSearchKeys`.<br>2. Added "Free (Auto-fallback)" badge.<br>3. Permitted toggling `AUTOMATIC_KEYLESS` without API key.<br>4. Added dedicated information view & real diagnostic runner in `editKeyView`. | `+108 / -26` | **Low:** Scoped entirely to search settings views (`SearchSettingView`). |
| `AI_HLY/Resource/Localizable.xcstrings` | Added string units for `company_AUTOMATIC_KEYLESS` and `免费 (自动切换)` in English, Hebrew, and Simplified Chinese. | `+46 / -0` | **Extremely Low:** Additive JSON string dictionary entries. |

---

## 3. Upstream Merge & Maintenance Assessment

1. **No Invasive Core Engine Refactors:** `APIManager.swift` lines 360–455 (`searchOnline`) and lines 1971–2026 (`performWebSearchTask`) resolve the active search engine via `getActiveSearchEngine()` and `searchTool(...)`. Because `AUTOMATIC_KEYLESS` conforms to `SearchEngine` and routes through `searchTool`, **zero edits were required in `APIManager.swift`**, guaranteeing zero regression to chat streaming or agent tool loops.
2. **SwiftData Schema Integrity:** The existing `SearchKeys` schema remains completely untouched. No schema version bump or migration plan required; `AUTOMATIC_KEYLESS` is stored as standard `SearchKeys` records.
3. **No External Package Dependencies Added:** The entire implementation relies purely on native Swift Foundation (`URLSession`, `JSONDecoder`) and SwiftData.
4. **Safety from Frozen UI:** Because the Asana gate `1219605282038660` was recognized and obeyed, zero risk of merge collisions or regressions was introduced into the core Chat UI files.
