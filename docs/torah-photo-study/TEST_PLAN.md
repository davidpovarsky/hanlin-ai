# Torah Photo Study — Test Plan & Strategy

---

## 1. Five Tiers of Evidence

| Tier | Name | Target Environment | What It Proves | What It Does NOT Prove |
|---|---|---|---|---|
| **T1** | Unit & Contract | Windows Workstation / CI | Core logic, Hebrew normalization, scalar offset tracking, alignment scoring, resolver rules, deep link URL codecs, error states | Does not prove live network, camera optics, or Apple Vision OCR |
| **T2** | Integration | Windows Workstation / Swift Test | Package interoperability, SQLite/Tantivy bridge models, QuickJS / embedded Python executor sandbox, secret sanitization | Does not prove physical photo capture or dual-app provisioning |
| **T3** | Live Services | Networked Host with API keys | Remote MCP transport handshake, Yochai Knowledge Graph queries, live Cairo Genizah API calls | Does not prove physical camera or UI integration |
| **T4** | Full-App Simulator | macOS Authority / Xcode Simulator | Full SwiftUI capture views, image cropping overlays, Vision OCR pipeline, inter-app URL handler triggers | Does not prove optical camera hardware, physical lens glare, or device entitlements |
| **T5** | Signed Physical Device | Signed iPad on iPadOS 17+ | Real camera sensor capture of physical printed books, optical focus/lighting, App Group shared container permissions, inter-app switching | Does not prove 100% of books in existence |

---

## 2. Fixture Matrix & Ground Truth

The test harness operates on `Tests/Fixtures/TorahPhotoStudy/manifest.json`:
- **Total Fixtures:** 60 distinct inputs.
- **Acquisition Sources:**
  - 33 physical camera captures (`physical_camera`)
  - 17 high-resolution digital scans (`scan`)
  - 10 synthetic challenge cases (`synthetic`)
- **Splits:**
  - **Calibration Set (20 fixtures):** Used for threshold calibration and parameter tuning.
  - **Holdout Set (40 fixtures):** Locked independent evaluation set.
- **Negative & Ambiguous Test Cases (17 fixtures):**
  - Out-of-corpus texts
  - Common liturgical verses repeated across dozens of tractates
  - Severe glare, heavy shadows, blurry captures
  - Explicit contradictory negation words (e.g. "לא")

---

## 3. Test Suites & Execution Matrix

- `BASE-01..08`: Baseline, worktree isolation, build flags, package resolutions.
- `SKL-01..16`: Skill zip import, inline instruction preservation, embedded Python/JS executor.
- `MCP-01..16`: Local & remote MCP, HTTPClientTransport, Yochai preset, secret masking.
- `LIB-01..16`: Shared App Group storage, deep link codecs, locator hydration, Tantivy/Zayit mapping.
- `OCR-01..16`: Vision OCR, Hebrew normalization, niqqud stripping, multi-column Talmud handling.
- `MAT-01..16`: Deterministic passage resolver, score components, citation detection, holdout precision.
- `ENR-01..12`: Linked commentaries, Sefaria provider, Yochai graph, Cairo Genizah research skill.
- `AGT-01..08`: Agent tool exposure, conversation persistence, zero-search transparency.
- `UI-01..12`: Capture view, crop bounding box, "פתח כאן", "פתח ב-Maktabah", RTL layouts.
- `SEC-01..10`: Sandboxing, path traversal rejection, credential protection, conversation deletion.
- `PERF-01..08`: Recognition latency budgets, query latency, memory scaling.
- `REG-01..08`: Non-regression on existing mini-apps, Maktabah navigation, and tool catalogs.
- `E2E-01..08`: Eight end-to-end user journeys from physical print to dual-app reader navigation.

---

## 4. Execution Commands

```bash
# Run all acceptance tiers
python Scripts/Acceptance/run-torah-photo-acceptance.py --tier ALL

# Run deterministic T1/T2 tests only
python Scripts/Acceptance/run-torah-photo-acceptance.py --tier T2

# Run a specific test suite (e.g. MAT)
python Scripts/Acceptance/run-torah-photo-acceptance.py --suite MAT

# Validate test evidence records
python Scripts/Acceptance/validate-torah-photo-evidence.py --input test-results.jsonl
```
