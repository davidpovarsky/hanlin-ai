# Preservation Ledger — Unified Integration Branch

**Date:** 2026-10-07  
**Branch:** `integration/hanlin-preserve-all-20261007`  
**Delivered Commit:** `464afc6f808d904e8e8531f778c29c5f445d0f0b`  
**Repository:** `davidpovarsky/hanlin-ai`  

---

## 1. Source Pins & Lineage

The integration branch unifies three distinct source branches into a single authoritative history via two consecutive two-parent merge commits:

| Key | Branch Name | Frozen Commit SHA | Role / Scope |
|:---|:---|:---|:---|
| **S** | `codex/agent-skills-embedded-results` | `03e7c70e66309068ade31fd88cc26f4741f00f53` | Pass 3 completion, Skills execution, Swift/Apple provider truth, clean C++ trampolines |
| **T** | `feat/torah-photo-study` | `e83739594b4552bd65bfd08fae8872fd29fd57d6` | Torah OCR, TorahLibraryKit, deep linking, 180m smoke timeout, dependency staging |
| **A** | `agent/agentui-sdk-adapter` | `05a5d3c11aa95fef9ab3d4a86318176a0be64799` | HanlinAgentUIAdapter package, session wrapping, presentation mapping |

### Merge Commits

1. **Merge 1 (S + T):** `31cfc30f83a72f7f24859045424f40dd30fa53fd`  
   - Parents: `03e7c70e66309068ade31fd88cc26f4741f00f53` (S) + `e83739594b4552bd65bfd08fae8872fd29fd57d6` (T)  
   - Commit Message: `merge: integrate feat/torah-photo-study into codex/agent-skills-embedded-results`
2. **Merge 2 ((S + T) + A):** `464afc6f808d904e8e8531f778c29c5f445d0f0b`  
   - Parents: `31cfc30f83a72f7f24859045424f40dd30fa53fd` (S+T) + `05a5d3c11aa95fef9ab3d4a86318176a0be64799` (A)  
   - Commit Message: `merge: integrate agent/agentui-sdk-adapter`

All three source commit tips are verified ancestors (`git merge-base --is-ancestor = true`). No squashing, rebasing, fast-forwarding, or `git merge -s ours` was performed.

---

## 2. Decision Table: Expo Header & Preparation Sanitization

Per Section 4.1 of the integration directive, all conflicting and overlapping transforms in `Scripts/Expo/prepare-ios-dependencies.mjs` and related build scripts were evaluated for semantic fidelity, ABI preservation, and elimination of fake/dummy fallbacks.

| Component / Transform | S Implementation | T Implementation | Integration Disposition | Rationale & Evidence |
|:---|:---|:---|:---|:---|
| `copyDeps` helper | S only copied root `Headers` & `ReactModularHeaders` | T searched root + 3 slices (`ios-arm64_x86_64-simulator`, `ios-arm64`, `ios-arm64_x86_64-maccatalyst`) and created `DoubleConversion` & `RCT-Folly/folly` aliases | **Merged** | Incorporates T's multi-slice discovery and aliasing alongside S's `ReactModularHeaders` staging. |
| `follyStub` fallback | Trampoline `#if __has_include` forwarding to real `dynamic.h` or `folly/json/dynamic.h` | Dummy struct with `size() { return 0; }`, empty string, and `false` returns | **Replaced-by-equivalent** | Per directive Section 4.1: Dummy stubs that discard runtime data are strictly prohibited. S's real header trampolines preserve full ABI and data fidelity without loss. |
| `YOGA_STYLE_FALLBACK_DEFINED` | Relies on real `yoga` headers staged from `ReactNativeDependencies` | Defines minimal fake `yoga::Style` struct | **Replaced-by-equivalent** | Real `yoga` headers from `ReactNativeDependencies.xcframework` are staged via `copyDeps`. No fake fallback struct needed. |
| `Utf8.h` collision | Did not explicitly remove | Removed colliding `jsinspector-modern/Utf8.h` to prevent collision with `cmark-gfm/utf8.h` | **Merged** | Integrated into `sanitizeHeaders` when encountering `Utf8.h` in `jsinspector-modern`. Prevents Clang module collision. |
| `RCTInspectorNetworkHelper.h` | Changed angled `<jsinspector-modern/...>` to quotes | Neutralized `#import <jsinspector-modern/ReactCdp.h>` and used quotes | **Merged** | Neutralizes non-modular `ReactCdp.h` import and quotes includes, preventing modular Clang failures. |
| `yoga` internal subdirs | Left subdirectories intact | Removed internal C++ subdirs (`algorithm`, `debug`, `enums`, `node`, `style`, `config`, `event`) | **Merged** | Integrated into `sanitizeHeaders` when traversing `yoga`. Leaves public C API clean for modular frameworks. |
| `hash_combine.h` C++17 | Guarded C++17 compatibility fallback with real hash algorithm | Removed `requires` and `Hashable` concepts completely | **Preserved (S)** | S's guarded implementation maintains standard-conforming hash combinations under both C++17 and C++20 without stripping signatures. |
| `fnv1a.h` identity | Functor `fnv1a_identity` compatible across C++17 and C++20 | Replaced `std::identity` with internal `std::__identity` | **Preserved (S)** | S avoids non-portable standard library private symbols (`std::__identity`), providing clean standard C++ functor. |
| `Base.h` SFINAE | Not patched | Patched `requires is_jsi_v` with `std::enable_if_t` | **Merged** | Safe standard SFINAE transformation allowing compilation in C++17 mode while preserving C++20 semantics. |
| `ScopedExecutor.h` | Not patched | Replaced `requires std::derived_from` with template `Func` | **Merged** | Enables broader template instantiation without concepts requirement. |
| `EnumArray.h`, `Props.h`, `RawProps.h` | Not patched | Guarded C++20 concepts with `#if defined(__cpp_concepts)` | **Merged** | Standard preprocessor guards ensuring compatibility in both C++17 and C++20 compilation environments. |
| `RCTComponentViewProtocol.h` | Not patched | Added `#pragma once` header guard | **Merged** | Prevents multiple include collisions. |
| `ExpoModulesCore_umbrella.h` | Stripped Fabric headers + ensured `EXHostWrapper.h` precedes `ExpoModulesCore.h` | Stripped Fabric headers | **Preserved (S)** | S's logic includes exact header ordering required to resolve `EXHostWrapper` before core imports. |
| `resignXcf` and `findFrameworks` | Re-signs all `.xcframework`s in `artifactsRoot`, recursively finding inner `.framework` bundles | Separate re-signing for React and ReactNativeHeaders only | **Preserved (S)** | S's implementation covers the entirety of `artifactsRoot` recursively. |
| Codesign remove signature | `codesign --force --deep` | `codesign --remove-signature` before `--force --deep` | **Merged** | T's removal of stale signatures prior to ad-hoc deep signing integrated into final Darwin signing block. |

---

## 3. Subsystem Resolution Ledger

### 3.1 Apple Local Providers (`AI_HLYTests/AppleLocalProvidersTests.swift`)
- **Conflict:** S added `MockFoundationBackend`, unified streaming tests, and `@unchecked Sendable Accumulator`. T added concurrency isolation fixes.
- **Resolution:** Retained S's authoritative test implementations and new mock seams, incorporating T's sendability attributes. Verified that all Apple local provider availability checks remain truthful (no synthetic passes).

### 3.2 HanlinExpoRuntime (`Packages/HanlinExpoRuntime/Package.swift`)
- **Conflict:** S introduced C++20 flag (`-Xcc -std=gnu++20`) and `ReactNativeDependencies` search paths. T added device and simulator search paths for `ReactNativeHeaders.xcframework`.
- **Resolution:** Retained `-Xcc -std=gnu++20` and unified all header search paths (ReactModularHeaders, dependencies, simulator slices, and device slices). C++ interop mode remains active.

### 3.3 Living Project Board (`PROJECT_BOARD.md`)
- **Conflict:** Add/add conflict across S, T, and A. S contained Pass 3 completion records and authoritative evidence pipeline details. T contained the complete Expo Multi-Exposure implementation plan. A contained standard placeholder template.
- **Resolution:** Retained all Discoveries & Tips from S and T, retained Pass 3 and final closure items under `Done`, and embedded the complete Expo multi-exposure plan under `Planned / Todo`. Preserved living board integrity. Validated via `scripts/validate-project-board.sh`.

### 3.4 CI Workflow (`.github/workflows/build-ios26-unsigned-ipa.yml`)
- **Conflict:** Overlapping changes in toolchain configuration, device build flags, simulator xcconfigs, header staging paths, and smoke timeouts.
- **Resolution:** Preserved S's compiler and header staging optimizations, preserved T's 180-minute timeout for `full-app-simulator-smoke`, preserved warm rebuild parameters, and maintained explicit manual-only trigger constraints. Zero conflict markers remain.

### 3.5 Affected Validation Map (`Scripts/CI/affected-validation-map.json` & `test_affected_validation.py`)
- **Conflict:** Divergence in CI routing mappings and exclusion patterns.
- **Resolution:** Narrowed `no_impact_patterns` (removed overly broad `Scripts/**/*.mjs`, `Skills/**`, etc.). Added dedicated components for `skill_resource_acceptance`, `skills_content`, `torah_fixtures`, and `agent_ui_adapter` with exact test suite target routing. Added comprehensive unit test suite `test_affected_validation.py` covering all 10 critical path patterns. All 47 unit tests pass.

### 3.6 AgentUI SDK Adapter (`Packages/HanlinAgentUIAdapter`)
- **Integration:** Staged all 9 files from Branch A (`Package.swift`, `README.md`, 6 sources, 1 test suite).
- **Boundary Policy:** Kept existing app chat screens and navigation entry points strictly unmodified. Did not replace active chat view or alter chat defaults. Retained experimental package in its designated directory without side-effects on core app flows.

### 3.7 Torah Study & TorahLibraryKit (`Packages/TorahLibraryKit` & `AI_HLY/Downstream/TorahStudy`)
- **Integration:** Preserved all 22 files from Branch T:
  - `TorahLibraryKit` package (Contracts, Coordinator, Matching, Navigation, Normalizer, Providers, Storage, Fixtures, Unit Tests).
  - Native host tools: `TorahOCRService.swift`, `TorahPhotoStudyCaptureView.swift`, `TorahStudyNativeTools.swift`.
  - Skills and fixtures: `Skills/torah-photo-study/`, `Skills/cairo-genizah-research/`, `Skills/yochai-study/`, `Tests/Fixtures/TorahPhotoStudy/`.
  - Acceptance scripts: `Scripts/Acceptance/run-torah-photo-acceptance.py`, `validate-torah-photo-evidence.py`, etc.
  - Zero-stubs enforcement: `Scripts/CI/verify-zero-stubs.py` passes cleanly (no stubs in production Torah files).

### 3.8 Semantic Auto-Merged Files Verification
- **`RuntimeToolSupport.swift`:** Verified presence of both `.missingKey` (from S) and `.invalidArguments` (from T) in error mapping switches.
- **`ProviderLongHorizonTests.swift`:** Verified that test S12 enforces `maxSteps: 32` (from S) against `0...36` responses (from T).
- **`OutputGenerator.swift` & Modifiers:** Verified that `@ViewBuilder` and availability guards are present for `documentLaunchSubtitle`, `documentLaunchTitle`, and `swipeActionsContainer`.
- **`AI_HLY.xcodeproj/project.pbxproj`:** Verified presence of `TorahLibraryKit` target/product references and `SWIFT_OBJC_INTEROP_MODE = objcxx`.

---

## 4. Audit & Verification Summary

- **Union Changed Paths:** 125 paths across S, T, and A.
- **Unambiguous Candidate Deviations:** 0 (all unique paths preserved bit-for-bit).
- **Operational Errors:** 0.
- **Staging / Working Copy:** `git ls-files -u` is empty; 0 conflict markers.
- **Worktree Isolation:** The user's original worktree (`c:\Users\DAVID\Code\hanlin-agent-skills-embedded-results`) was never touched and remains completely clean.
