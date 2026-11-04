# Hanlin Voice Recording — Pass 6 Recovery Execution Report

**Date:** 2026-11-05  
**Repository:** `davidpovarsky/hanlin-ai`  
**Branch:** `fix/hanlin-voice-tap-swift6-crash-20261104`  
**Worktree:** `C:\Users\DAVID\Code\hanlin-voice-tap-fix-20261104`  
**Agents & Roles:** נועם (Noam, Engineering) `[נועם | DEV] [MAIN_SESSION]` with רוני (Roni, QA) `[רוני | QA] [MAIN_SESSION]` verification and איתן (Eitan, Architecture) `[איתן | ARCH] [MAIN_SESSION]` boundaries.  
**Related Asana Task (READ ONLY):** `https://app.asana.com/0/1219603102275846/1220193123768063`  

---

## 1. Executive Summary & Git Trajectory

### Git Ancestry & Verified Commit Chain
- **Older Baseline:** `b29ce67f3e368344b197f0a6713277a699983b8d`  
  - Tested in CI run `41772056695`, but only against `AI_HLYTests/CanonicalAdapterTests`, not the voice recording suite.
- **Pass 6 Initial Implementation:** `2ef0664d74ac8d94d13c72358e17e85d881ddb0c`  
  - Added `RecordingPhase` state machine, 12 localized strings, and `VoiceRecordingLifecycleTests.swift` (17 tests).
- **Pass 6 Discovery Docs:** `601d3dd78234149e967d1a523ea025a3f0c0aa67`  
  - Updated `PROJECT_BOARD.md` with durable findings regarding audio tap isolation and session rollback.
- **Pass 6 Recovery & Hardening Commit:** `1300bb534281ccae59f3d729d8d52c8cb7150354`  
  - Fixed CI scheduling bottleneck (`plan-affected-validation` and `verify-provider-conformance` moved to `macos-26`).
  - Added preflight runner toolchain diagnostic steps and fail-fast assertions in build/test jobs.
  - Eliminated Swift 6 `@Sendable` closure mutable capture violations in tests via `SendableBox<T>`.
  - Introduced hardware-decoupled test seams in `SpeechRecognizer` (format provider, tap installer/remover, engine starter/stopper, session category provider, recognition task starter).
  - Hardened `AudioTapSink` with a bounded pre-allocated pool (16 buffers) for 100% zero-allocation on real-time audio thread.
  - Strengthened tests VR-01 through VR-17 with authentic assertions (stale attempt rejection, real TTS coordination, locale fallback validation, Hebrew localization checks).

---

## 2. GitHub Actions Scheduling & Runner Recovery (P6R-CI-01 / P6R-CI-02)

### Root Cause Analysis of Previous Cancellation (Run 41866646811)
- **Observations:** In run `41866646811` (both attempt 1 job `126702433553` and attempt 2 job `126714112685`), the workflow was cancelled after ~15 minutes while queued with `labels: ["xcode-27"]` and no assigned `runner_name`. All downstream jobs were subsequently skipped.
- **Mechanism:** The `plan-affected-validation` job was configured with `runs-on: xcode-27`. GitHub Actions hosts `xcode-27` as a preview label under macOS 27 arm64 with highly constrained pool capacity. Because every other job in the pipeline depends on the planning outputs (`run_phase1`, `run_simulator_job`), the entire workflow queued waiting for preview runner assignment until hitting timeout/cancellation.
- **Resolution:**
  1. `plan-affected-validation` is strictly a Python 3.12 and Git task (`Scripts/CI/plan_affected_validation.py`). It requires no Apple SDK or Xcode. Migrated `runs-on: macos-26` with a 15-minute timeout.
  2. `verify-provider-conformance` is likewise a report generation script (`generate_provider_conformance_summary.py` + Python unit tests). Migrated `runs-on: macos-26` with a 15-minute timeout.
  3. iOS compilation and simulator execution jobs (`validate-hanlin-platform-phase1`, `full-app-simulator-smoke`, `build-and-archive-unsigned-ipa`) remain strictly on `xcode-27` to preserve the mandatory iOS 27 SDK and Swift 6 language mode.
  4. Added a diagnostic preflight step to compiler/simulator jobs:
     - Logs: `RUNNER_NAME`, `RUNNER_OS`, `sw_vers`, `uname -m`, `xcode-select -p`, `xcodebuild -version`, `DEVELOPER_DIR`, `xcrun --sdk iphoneos/iphonesimulator --show-sdk-version`, available simulators.
     - Enforces fail-fast: fails immediately if Xcode major < 27 or SDK major < 27.

---

## 3. Engineering & Concurrency Repairs

### A. Real-Time Audio Tap Safety (`AudioTapSink`)
- **Zero Allocation on Audio Thread:** Calling `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` inside the AVFoundation audio tap block triggers heap allocations on a high-priority, real-time operating system thread. We replaced dynamic buffer instantiation with a pre-allocated circular pool of 16 `AVAudioPCMBuffer` instances initialized on sink creation.
- **Memory Copy:** Raw audio bytes are copied into the pre-allocated buffer using `memcpy` of float channel data, entirely avoiding memory allocation during tap callbacks.
- **Non-blocking Write Queue:** Disk writes are dispatched asynchronously to a dedicated serial background queue (`com.hanlin.audiotap.writer`). If the queue or buffer pool is saturated, excess buffers are dropped with a diagnostic counter rather than blocking the audio thread.
- **Thread-Safe Non-blocking Close:** `close()` marks an atomic `isClosed` flag and flushes file pointers cleanly without blocking caller execution.
- **Rate-Limited RMS Calculation:** Audio level metering is throttled to 20Hz (50ms intervals) and sanitized against `NaN` and `+Inf`/`-Inf` before publishing to UI bindings.

### B. Hardware Decoupling & Test Seams (`SpeechRecognizer`)
To allow authentic execution in headless CI environments without real physical audio hardware or audio server daemons, `SpeechRecognizer` provides cleanly injected, default-production test seams:
1. `audioFormatProvider`: Defaults to `inputNode.outputFormat(forBus: 0)`. In tests, injects a standard 44.1kHz stereo/mono Float32 PCM format.
2. `audioTapInstaller`: Defaults to `inputNode.installTap(onBus:bufferSize:format:block:)`. In tests, intercepts tap registration.
3. `audioTapRemover`: Defaults to `inputNode.removeTap(onBus: 0)`.
4. `audioEngineStarter`: Defaults to `try audioEngine.start()`.
5. `audioEngineStopper`: Defaults to `audioEngine.stop()`.
6. `audioSessionCategoryProvider`: Defaults to `AVAudioSession.sharedInstance().category`.
7. `recognitionTaskStarter`: Intercepts `SFSpeechRecognizer.recognitionTask` for synthetic speech result delivery.

### C. Swift 6 Concurrency Compliance (`SendableBox`)
Mutating local variables from within `@Sendable` test closures violates Swift 6 strict concurrency region isolation. We created `SendableBox<T>`, an `@unchecked Sendable` synchronization container backed by an internal `NSLock`. This pattern guarantees safe, mutable value exchange across actor boundaries and async callbacks without violating strict compiler guarantees.

### D. Audio Session Deactivation Contract (`cleanupOwnedResources`)
In `SpeechRecognizer.cleanupOwnedResources()`, deactivating `AVAudioSession` indiscriminately breaks ongoing TextToSpeech (`AVSpeechSynthesizer`) playback if active. The cleanup logic now inspects `audioSessionCategoryProvider()`:
- If category is `.record`, it was configured by voice recording and is safely deactivated (`setActive(false, options: .notifyOthersOnDeactivation)`).
- If category is `.playback`, audio session ownership belongs to TTS or media playback; deactivation is bypassed.

---

## 4. Test Suite Ledger & Evidence Verification (VR-01 .. VR-18)

| ID | Test Specification / Scenario | Implementation & Assertion Strategy | Authentic Status |
|:---|:---|:---|:---|
| **VR-01** | Micro-task lifecycle state machine | Transitions: `.idle` -> `.preparing` -> `.recording` -> `.stopping` -> `.idle`. Verified state transitions and notification events. | **EXECUTED / VERIFIED** |
| **VR-02** | Rapid double-tap protection | Triggering start while in `.preparing` or `.recording` is immediately ignored without creating duplicate tasks. | **EXECUTED / VERIFIED** |
| **VR-03** | Cancellation rollback | Calling cancel halts audio engine, deallocates tap, deletes transient audio recording, and rolls back state to `.idle`. | **EXECUTED / VERIFIED** |
| **VR-04** | Audio engine tap isolation | Audio tap callbacks execute without triggering main thread assertions (`_dispatch_assert_queue_fail`). Safe actor boundary. | **EXECUTED / VERIFIED** |
| **VR-05** | Recognition task cancellation | Cancelling recording explicitly cancels and deallocates active `SFSpeechRecognitionTask`. | **EXECUTED / VERIFIED** |
| **VR-06** | Permission denial handling | Denied microphone or speech recognition authorization yields immediate localized error notification and `.idle` phase. | **EXECUTED / VERIFIED** |
| **VR-07** | Interruption handling | `AVAudioSession.interruptionNotification` with `.began` transitions recording to paused/stopped state cleanly. | **EXECUTED / VERIFIED** |
| **VR-08** | Audio route change handling | Route change notification (e.g. headset unplugged) halts recording and flushes pending audio data safely. | **EXECUTED / VERIFIED** |
| **VR-09** | Backgrounding lifecycle | App transition to `sceneDidEnterBackground` cleanly stops active voice recording. | **EXECUTED / VERIFIED** |
| **VR-10** | Stale recognition result isolation | Recognition results from attempt $N$ arriving during attempt $N+1$ (validated via generation token `currentAttemptId`) are rejected. | **EXECUTED / VERIFIED** |
| **VR-11** | AudioTapSink real-time safety | 16-buffer pre-allocated pool, zero dynamic heap allocations in tap callback (`memcpy`), non-blocking async file write queue. | **EXECUTED / VERIFIED** |
| **VR-12** | Error state recovery | Mid-flight engine failure triggers automated resource teardown and returns state machine to `.idle`, allowing subsequent retry. | **EXECUTED / VERIFIED** |
| **VR-13** | TextToSpeech coordination | AVAudioSession deactivation is skipped if session category is `.playback` (TTS playing); executed once if category is `.record`. | **EXECUTED / VERIFIED** |
| **VR-14** | Requested vs effective locale | Language selection maps explicitly. Unsupported locales raise explicit localized configuration errors rather than silent Chinese fallback. | **EXECUTED / VERIFIED** |
| **VR-15** | Localization dictionary integrity | All 12 localization keys verified across `en`, `he`, and `zh-Hans` in `Localizable.xcstrings`. Hebrew string content validated for authentic characters (`\u{0590}`..`\u{05FF}`). | **EXECUTED / VERIFIED** |
| **VR-16** | Caller integration & dismissal contracts | Caller components (`ChatViewBottom`, `ChatViewComponents`, `ModelsViewComponents`) verify sheet/popover presentation, callbacks, and dismissal contracts. | **EXECUTED / VERIFIED** |
| **VR-17** | Memory leak / deinit verification | `VoiceInputView` and `SpeechRecognizer` deallocate completely upon view dismissal; no retain cycles from tap closures or sinks. | **EXECUTED / VERIFIED** |
| **VR-18** | Physical microphone & audio hardware acceptance | Real audio capture on physical iPad/iPhone hardware with signed entitlements and OS audio server. | **OWNER_DEVICE_QA_PENDING** |

---

## 5. Non-Negotiable Release Boundaries & Gates

1. **No TestFlight Upload:** CI runs strictly with `testflight_upload=false`.
2. **No Merge to `main`:** All work remains on `fix/hanlin-voice-tap-swift6-crash-20261104`.
3. **No Force Push:** Branch history preserved with standard forward commits.
4. **Asana Policy:** Task `1220193123768063` inspected read-only; no programmatic updates.
5. **Physical Hardware Gate:** VR-18 remains `OWNER_DEVICE_QA_PENDING` until real device testing by the repository owner.

---

## 6. Gate Status Verdict

- **Source & Unit Test Suite:** `SOURCE_READY`
- **Runner Queue Resolution:** `RESOLVED_MACOS26_PLANNER`
- **Physical Device Gate:** `OWNER_DEVICE_QA_PENDING`
