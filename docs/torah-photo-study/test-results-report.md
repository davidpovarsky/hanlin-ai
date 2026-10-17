# Torah Photo Study — Acceptance Test Results Report

**Date:** 2026-10-17T23:18:08.107830+00:00
**Hanlin Implementation SHA:** `d4cb328afd53a4ffb3b0ed891018a1fbdf50ce85`
**Maktabah SHA:** `9df51ca0b74a387cf3d3b73ebf18c8188172c72b`
**Shared Core SHA:** `b8f71e084bcaa1c60a8e3583034328830aa27fb5`

## Summary Statistics

| Status | Count | Percentage |
|---|---|---|
| **PASS** | 15 | 5.8% |
| **BLOCKED** | 145 | 55.8% |
| **FAIL** | 0 | 0.0% |
| **NOT_RUN** | 100 | 38.5% |
| **NOT_APPLICABLE** | 0 | 0.0% |
| **Total Test Records** | 260 | 100.0% |

## Fixture Matrix Evaluation (60 Fixtures)

- Total Fixtures: **60**
- Calibration Split: **20**
- Holdout Split: **40**
- Negative / Ambiguous Fixtures: **17**
- False Positives on Negative Cases: **0**
- True Positives in Local Corpus: **6**
- Holdout Verified Precision: **100.0%**
- Holdout Verified Coverage: **25.0%**

## Detailed Test Inventory

| Test ID | Tier | Status | Details / Blockers |
|---|---|---|---|
| `BASE-01` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `BASE-03` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-06` | `T1` | **PASS** | Verified via targeted test 'HebrewTextNormalizer strips vocalization and cantillation while mapping indices' (Hebrew text normalizer strips vocalization and accurately maps scalar indices) |
| `BASE-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `BASE-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `BASE-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-01` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SKL-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-03` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-04` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-05` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-06` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-07` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-08` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-08` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-09` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SKL-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-10` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-11` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-11` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SKL-12` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-13` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-13` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SKL-14` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-14` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SKL-15` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-16` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SKL-16` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-01` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MCP-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-03` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-03` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-08` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-10` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MCP-11` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-11` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-12` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MCP-13` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-14` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-14` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MCP-15` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MCP-16` | `T3` | **BLOCKED** | Live Yochai API key (YOCHAI_API_KEY) not configured in test environment; live Knowledge Graph integration blocked per spec [Blocker: YOCHAI_API_KEY secret not provisioned] |
| `MCP-16` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-01` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-02` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-03` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-03` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-04` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-05` | `T2` | **PASS** | Verified via targeted test 'ITorahSharedStorage mode distinction and truthful provenance' (ITorahSharedStorage honestly distinguishes App Group container vs private fallback) |
| `LIB-06` | `T2` | **PASS** | Verified via targeted test 'Zayit provider surfaces Tantivy index availability and SQLite fallback honestly' (Zayit provider surfaces Tantivy index availability and SQLite fallback provenance honestly) |
| `LIB-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-09` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `LIB-09` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-10` | `T1` | **PASS** | Verified via targeted test 'TorahStudyDeepLink encodes and decodes round-trip accurately' (TorahStudyDeepLink URL encoding and decoding round-trip contract) |
| `LIB-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-11` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-11` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `LIB-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-12` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `LIB-13` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-13` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `LIB-14` | `T2` | **PASS** | Verified via targeted test 'Coordinator getLinks and getTopics route correctly and fail closed on unknown provider' (Coordinator links/topics dispatch routes correctly and fails closed on unknown provider) |
| `LIB-15` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-16` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `LIB-16` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-02` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-03` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-04` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-05` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-06` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-07` | `T2` | **PASS** | Verified via targeted test 'TorahSourceResolver handles insufficient image gracefully' (TorahSourceResolver gracefully rejects unreadable or insufficient excerpt text) |
| `OCR-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-09` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-10` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-11` | `T3` | **BLOCKED** | HebVL vision endpoint / GPU backend not configured for remote OCR validation [Blocker: HEBVL_REMOTE_ENDPOINT not configured] |
| `OCR-12` | `T1` | **PASS** | Verified via targeted test 'HebrewTextNormalizer strips vocalization and cantillation while mapping indices' (Hebrew normalizer contract strips niqqud and cantillation correctly) |
| `OCR-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-13` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-13` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-14` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `OCR-14` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-15` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `OCR-15` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `OCR-16` | `T3` | **BLOCKED** | HebVL vision endpoint / GPU backend not configured for remote OCR validation [Blocker: HEBVL_REMOTE_ENDPOINT not configured] |
| `OCR-16` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-01` | `T2` | **PASS** | Verified via targeted test 'TorahSourceResolver marks unique primary source as verified' (TorahSourceResolver marks unambiguous unique primary work as verified) |
| `MAT-01` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MAT-02` | `T2` | **PASS** | Verified via targeted test 'Resolver selects correct candidate from mock corpus' (Resolver correctly selects and ranks highest-confidence candidate from corpus) |
| `MAT-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MAT-03` | `T2` | **PASS** | Verified via targeted test 'TorahTextAlignment aligns OCR tokens with source text' (TorahTextAlignment aligns OCR word tokens with source canonical text) |
| `MAT-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-05` | `T2` | **PASS** | Verified via targeted test 'TorahSourceResolver distinguishes quoted work and marks ambiguity' (TorahSourceResolver distinguishes quoted secondary sources and avoids false verification) |
| `MAT-06` | `T2` | **PASS** | Verified via targeted test 'Resolver discovers source from actual Otzaria SQLite corpus file using OCR text only' (TorahSourceResolver discovers source directly from test Otzaria SQLite corpus) |
| `MAT-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MAT-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-09` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MAT-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-10` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-11` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-13` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-13` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `MAT-14` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `MAT-14` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-15` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `MAT-15` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `MAT-16` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `MAT-16` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `ENR-01` | `T2` | **PASS** | Verified via targeted test 'Sefaria throws typed error on HTTP 500 server failure rather than empty hits' (Sefaria provider distinguishes HTTP 500, 401, 429 and decoding errors from empty hits) |
| `ENR-01` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `ENR-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `ENR-03` | `T3` | **BLOCKED** | Live Yochai API key (YOCHAI_API_KEY) not configured in test environment; live Knowledge Graph integration blocked per spec [Blocker: YOCHAI_API_KEY secret not provisioned] |
| `ENR-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-04` | `T3` | **BLOCKED** | Live Yochai API key (YOCHAI_API_KEY) not configured in test environment; live Knowledge Graph integration blocked per spec [Blocker: YOCHAI_API_KEY secret not provisioned] |
| `ENR-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `ENR-06` | `T3` | **BLOCKED** | Live GenizahSearch API external network request requires verified network session; unprobed in offline local acceptance runner [Blocker: Live GenizahSearch network session unprobed] |
| `ENR-06` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `ENR-07` | `T3` | **BLOCKED** | Live GenizahSearch API external network request requires verified network session; unprobed in offline local acceptance runner [Blocker: Live GenizahSearch network session unprobed] |
| `ENR-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-08` | `T3` | **BLOCKED** | Live GenizahSearch API external network request requires verified network session; unprobed in offline local acceptance runner [Blocker: Live GenizahSearch network session unprobed] |
| `ENR-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-09` | `T3` | **BLOCKED** | Live GenizahSearch API external network request requires verified network session; unprobed in offline local acceptance runner [Blocker: Live GenizahSearch network session unprobed] |
| `ENR-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-10` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `ENR-11` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `ENR-12` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `ENR-12` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-01` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `AGT-01` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-02` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `AGT-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-03` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `AGT-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-04` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `AGT-04` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-05` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `AGT-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `AGT-06` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `AGT-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `AGT-07` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `AGT-08` | `T3` | **BLOCKED** | Live remote service provider credentials or live model endpoint not configured in this test session [Blocker: Live LLM / Service endpoint not configured] |
| `UI-01` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-02` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-03` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-04` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-04` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-05` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `UI-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-06` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-07` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-08` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-09` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-09` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-10` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-10` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `UI-11` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-12` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `UI-12` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SEC-01` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SEC-02` | `T1` | **PASS** | Verified via targeted test 'Coordinator identifyExcerpt with allowRemoteFallback false never contacts Sefaria' (Coordinator local-only policy strictly prevents remote network calls) |
| `SEC-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-03` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-04` | `T2` | **PASS** | Verified via targeted test 'Coordinator identifyExcerpt with allowRemoteFallback false never contacts Sefaria' (Coordinator identifyExcerpt with allowRemoteFallback=false never contacts Sefaria) |
| `SEC-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-06` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-07` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SEC-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-08` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `SEC-09` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `SEC-09` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `SEC-10` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `PERF-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `PERF-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `PERF-02` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `PERF-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `PERF-03` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `PERF-04` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `PERF-04` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `PERF-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `PERF-05` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `PERF-06` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `PERF-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `PERF-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `PERF-08` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `PERF-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `REG-01` | `T1` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-01` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-02` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-02` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `REG-03` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `REG-04` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `REG-05` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-05` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `REG-06` | `T4` | **BLOCKED** | macOS Xcode / iOS Simulator authority layer required for full-app simulation; running on Windows workstation [Blocker: macOS iOS Simulator host unavailable] |
| `REG-07` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `REG-08` | `T2` | **NOT_RUN** | Scenario not targeted in TorahLibraryKit package test suite; requires full app host harness [Blocker: Requires full app host harness execution] |
| `REG-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-01` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-02` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-03` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-04` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-05` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-06` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-07` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
| `E2E-08` | `T5` | **BLOCKED** | Physical signed iPad device with optical camera and installed App Group required for T5 verification (spec §12.1, §15.2, §16.4) [Blocker: Physical iPad hardware required] |
