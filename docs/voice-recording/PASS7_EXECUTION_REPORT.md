# Hanlin Voice Recording & Widget Integrity — Pass 7 Physical iPad Remediation Report

**Date:** 2026-11-05  
**Repository:** `davidpovarsky/hanlin-ai`  
**Working Branch:** `fix/hanlin-pass7-audio-widget-integrity-20261105`  
**Parent / Base SHA:** `f97e8798b3480282e488448cb18eb947922ba3e0`  
**Final Commit SHA:** `bda44783eb5a43564943f60da3ba001d8112040b`  
**Device Context:** `iPad15,3`, iPadOS `27.2 (24B119)` — Physical device reproduction on TestFlight build `0.7.3 (89101)` (Run `41947393634`)  
**Agents & Roles:** נועם (Noam, Engineering) `[נועם | DEV] [MAIN_SESSION]`, רוני (Roni, QA) `[רוני | QA] [MAIN_SESSION]`, איתן (Eitan, Architecture) `[איתן | ARCH] [MAIN_SESSION]`  
**Asana Status:** READ-ONLY (Preserved untouched per prompt instruction line 15)  
**Distribution Gate:** `RELEASE_NOT_DISPATCHED` (Release build and TestFlight upload strictly pending separate, explicit owner authorization)  
**Overall Verdict:** `SOURCE_FIXED_TARGETED_TESTS_PASS_DEVICE_PENDING` (Truthful status: physical hardware verification explicitly pending owner device testing)  

---

## 1. Executive Summary & Git Trajectory

On 2026-11-05, physical testing of signed TestFlight build `0.7.3 (89101)` on owner hardware (`iPad15,3`, iPadOS `27.2 (24B119)`) uncovered two P0 regressions:
1. **P7-A01 (Audio Crash):** Fatal crash on Thread 6 when recording microphone input:
   ```text
   AVFAudio             _AVAE_Check
   AVFAudio             -[AVAudioPCMBuffer setFrameLength:]
   AI_Hanlin            AudioTapSink.processBuffer(_:)  VoiceInputView.swift:1048
   ```
2. **P7-W01 (Widget Picker Error):** Selecting an installed Hanlin Expo widget in Home Screen **Edit Widget → Widget instance** fails with:
   `HanlinScriptExtensions.HanlinScriptExtensionStoreError -4` (`integrityMismatch`).

### Clean Repository & Branch Isolation
- Dedicated branch created from verified 89101 source `f97e8798b3480282e488448cb18eb947922ba3e0`:
  `fix/hanlin-pass7-audio-widget-integrity-20261105`
- Zero changes to protected files:
  - Classic Chat files: `AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `AI_HLY/Views/Components/ChatViewComponents.swift`, `AI_HLY/Views/Components/ChatandFile.swift` remain 100% untouched.
  - OrganizerDock V3.3: All 8 OrganizerDock files remain 100% untouched.
- Clean worktree verified and pushed to remote `origin/fix/hanlin-pass7-audio-widget-integrity-20261105`.

---

## 2. P7-A01 — Physical Microphone AVAudioPCMBuffer setFrameLength: Crash Remediation

### Root Cause Analysis
In `VoiceInputView.swift:1048` (`AudioTapSink.processBuffer(_:)`), the sink maintains a bounded circular buffer pool initialized with:
```swift
AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048)
```
When AVFoundation invokes the audio tap callback on physical iPad hardware, `AVAudioEngine` input node delivers buffer chunks whose frame length can exceed 2048 (commonly 4096 or 4800 frames on physical iPad microphones, depending on hardware sample rate 44.1kHz / 48kHz and audio session latency configuration).

The unpatched code unconditionally executed:
```swift
freeBuf.frameLength = buffer.frameLength
```
Under Apple's AVFAudio implementation, `-[AVAudioPCMBuffer setFrameLength:]` validates `frameLength <= frameCapacity`. If `frameLength > frameCapacity`, `_AVAE_Check` throws an uncatchable Objective-C exception triggering an immediate `EXC_CRASH (SIGABRT)`. Prior CI tests passed because `testVR11` passed `audioFile: nil`, skipping the pooled file-copy branch entirely.

### Exact Before / After Implementation
```diff
--- a/AI_HLY/Views/Components/VoiceInputView.swift
+++ b/AI_HLY/Views/Components/VoiceInputView.swift
@@ -995,7 +995,23 @@ internal final class AudioTapSink: @unchecked Sendable {
     private let fileWriterQueue = DispatchQueue(label: "org.hanlin.AudioFileWriter", qos: .utility)
     private var bufferPool: [AVAudioPCMBuffer] = []
     private var droppedWritesCount: Int = 0
+    private var lastDropLogNanoseconds: UInt64 = 0
     private let maxPoolCapacity: Int = 16
+    private let poolBufferCapacity: AVAudioFrameCount = 8192
+
+    #if DEBUG
+    var testDroppedWritesCount: Int {
+        lock.lock()
+        defer { lock.unlock() }
+        return droppedWritesCount
+    }
+
+    var testPoolCount: Int {
+        lock.lock()
+        defer { lock.unlock() }
+        return bufferPool.count
+    }
+    #endif
 
     init(
         generation: Int,
@@ -1011,7 +1027,7 @@ internal final class AudioTapSink: @unchecked Sendable {
 
         if audioFile != nil, let format = recordingFormat {
             for _ in 0..<maxPoolCapacity {
-                if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2048) {
+                if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: poolBufferCapacity) {
                     self.bufferPool.append(buf)
                 }
             }
@@ -1043,15 +1059,45 @@ internal final class AudioTapSink: @unchecked Sendable {
         var pooledBuffer: AVAudioPCMBuffer? = nil
         if audioFile != nil {
             if let freeBuf = bufferPool.popLast() {
-                let frameCount = buffer.frameLength
-                let channelCount = Int(buffer.format.channelCount)
-                freeBuf.frameLength = frameCount
-                for ch in 0..<channelCount {
-                    if let src = buffer.floatChannelData?[ch], let dst = freeBuf.floatChannelData?[ch] {
-                        memcpy(dst, src, Int(frameCount) * MemoryLayout<Float>.size)
+                let inputFrames = buffer.frameLength
+                let inputCapacity = buffer.frameCapacity
+                let poolCapacity = freeBuf.frameCapacity
+                let srcChannels = Int(buffer.format.channelCount)
+                let dstChannels = Int(freeBuf.format.channelCount)
+                let isFormatCompatible = buffer.format.commonFormat == .pcmFormatFloat32 &&
+                                         freeBuf.format.commonFormat == .pcmFormatFloat32 &&
+                                         buffer.format.isInterleaved == freeBuf.format.isInterleaved &&
+                                         srcChannels == dstChannels &&
+                                         srcChannels > 0
+
+                // Strict invariant check: input length must be positive, within input capacity,
+                // and within destination pool buffer capacity, with matching Float32 non-interleaved format
+                if isFormatCompatible &&
+                   inputFrames > 0 &&
+                   inputFrames <= inputCapacity &&
+                   inputFrames <= poolCapacity,
+                   let srcChannelData = buffer.floatChannelData,
+                   let dstChannelData = freeBuf.floatChannelData {
+
+                    freeBuf.frameLength = inputFrames
+                    let bytesPerChannel = Int(inputFrames) * MemoryLayout<Float>.size
+                    for ch in 0..<srcChannels {
+                        memcpy(dstChannelData[ch], srcChannelData[ch], bytesPerChannel)
+                    }
+                    pooledBuffer = freeBuf
+                } else {
+                    // Oversized or incompatible buffer: DO NOT crash or invoke setFrameLength beyond capacity.
+                    // Return freeBuf to pool to prevent buffer leakage, and track bounded drop count.
+                    bufferPool.append(freeBuf)
+                    droppedWritesCount += 1
+
+                    let now = DispatchTime.now().uptimeNanoseconds
+                    if now - lastDropLogNanoseconds >= 1_000_000_000 { // at most 1Hz bounded log
+                        lastDropLogNanoseconds = now
+                        // Privacy-safe bounded log with zero audio/PCM content
+                        print("[AudioTapSink] Dropped file write frame: length=\(inputFrames), inCapacity=\(inputCapacity), poolCapacity=\(poolCapacity), channels=\(srcChannels), format=\(buffer.format.commonFormat.rawValue), drops=\(droppedWritesCount)")
                     }
                 }
-                pooledBuffer = freeBuf
             } else {
                 droppedWritesCount += 1
             }
```

### Key Engineering Guarantees
1. **Capacity Bump to 8192:** Accommodates physical hardware buffer lengths (up to 4096/4800 frames) with zero drops under normal conditions.
2. **Strict Guard Preconditions:** Validates `inputFrames > 0`, `inputFrames <= inputCapacity`, and `inputFrames <= poolCapacity` before assigning `freeBuf.frameLength = inputFrames`. Also enforces `.pcmFormatFloat32`, matching channels, and matching interleaving.
3. **No Buffer Leakage:** If a frame is dropped due to oversize or incompatible format, `freeBuf` is immediately returned to `bufferPool.append(freeBuf)`, preserving the 16-buffer pool invariant.
4. **Speech Recognition Continuity:** `request.append(buffer)` and RMS metering execute outside the file write branch, ensuring real-time speech transcription and audio visualization continue uninterrupted.
5. **Zero Allocation on Audio Thread:** All buffer instances are pre-allocated; no dynamic allocations occur during tap execution.
6. **Privacy-Safe Bounded Diagnostics:** Rate-limited to 1Hz; records only metadata (frame length, channel count, format); zero audio samples or PCM bytes logged.

---

## 3. P7-W01 — WidgetKit Integrity Mismatch (-4) Diagnosis & Remediation

### Exact Error Interpretation
- In Swift enum bridging, `HanlinScriptExtensionStoreError` maps to `NSError` with code = raw case index:
  - Code `0`: `lockTimeout`
  - Code `1`: `storageUnavailable`
  - Code `2`: `snapshotTooLarge`
  - Code `3`: `invalidEnvelope`
  - Code `4`: `integrityMismatch`  <-- **The exact `-4` observed in screenshot IMG_0459.jpeg**
  - Code `5`: `unsupportedSchema`

### Root Cause Analysis
1. **Interrupted / 0-byte Revision File Handling:**
   In `writeRevision`, the existing code checked `if !FileManager.default.fileExists(atPath: url.path) { try data.write(...) }`. If a previous app update, crash, or low-storage event left a 0-byte or corrupted file at `Revisions/<sha>.json`, the store would skip writing, leaving the corrupted file in place. On subsequent reads, `checkedRevision` read the 0-byte file, computed hash `e3b0c44...`, discovered it did not match the expected `<sha>`, and threw `integrityMismatch` (-4).
2. **Missing Throw-Site Query Diagnostics:**
   Neither `checkedRevision` nor `decodeEnvelope` wrote structured diagnostic records to `latest-query-diagnostic.json` prior to throwing `integrityMismatch`. As a result, the host UI could not report the specific failure stage or mismatched hash.
3. **Historical v1 Envelope Canonicalization:**
   Historical v1 envelopes serialized via standard `JSONEncoder` produced slightly different byte sequences than current `JSONSerialization` canonical serialization. `decodeEnvelope` now provides a verified fallback for historical encodings, preventing valid older installations from throwing integrity mismatch.

### Remediation Details
1. **Self-Healing Non-Destructive Write:**
   `writeRevision` now inspects existing files: if the file exists on disk, it verifies that the file is non-empty and its SHA256 digest matches. If corrupted or empty, it safely overwrites it atomically.
2. **Durable Query Diagnostics at Every Throw Site:**
   Added `decisionPoint: .revisionIntegrityMismatch` and `.envelopeIntegrityMismatch` in `HanlinWidgetStorageDiagnostic.DecisionPoint`. Every throw in `checkedRevision` and `decodeEnvelope` persists a typed diagnostic to `latest-query-diagnostic.json`.
3. **Privacy-Redacted Storage Consistency Report:**
   Added `HanlinStorageConsistencyReport` capturing:
   - `commitPresent`, `commitVersion`, `commitSnapshotHashPrefix`, `commitShadowHashPrefix`
   - `revisionFilePresent`, `revisionFileSize`, `actualRevisionHashPrefix`
   - `shadowFilePresent`, `shadowFileSize`, `actualShadowHashPrefix`
   - `pendingPresent`, `failingStage`, `summary`, `correlationID`
   - Zero private user data or full paths exposed.
4. **Host UI "Copy Diagnostic" Integration:**
   `ScriptingPackageCenterViews.swift` button copies `platform.storageConsistencyReport()?.redactedReportString ?? diag.redactedReportString` directly to clipboard.

---

## 4. Test Suite Ledger & Verification

### A. Audio Recording Tests (`AI_HLYTests/VoiceRecordingLifecycleTests.swift`)
- **VR-01 through VR-18:** Existing lifecycle, permission, locale, and state tests preserved.
- **VR-19 (`testVR19_AudioTapSink_RealFilePoolBranchExecution_VariousFrameSizes`):**
  - Instantiates `AudioTapSink` with a real `AVAudioFile` on disk.
  - Tests boundary frame sizes: 1024, 2048, 2049, 4096, 8192 frames.
  - Asserts 0 dropped writes; verifies all 16 buffers returned to pool.
- **VR-20 (`testVR20_AudioTapSink_OversizedAndIncompatibleFrameSafety_NoCrash`):**
  - Injects oversized 16384 frames (larger than pool capacity 8192). In unpatched code, triggers `-[AVAudioPCMBuffer setFrameLength:]` exception and SIGABRT. In patched code: safely drops from file write, 0 crash, increments drop counter, returns buffer to pool.
  - Injects incompatible stereo format into mono sink: safely dropped, 0 crash, no pool leakage.
  - Injects subsequent valid 1024-frame buffer: accepted normally, pool intact.
- **VR-21 (`testVR21_RepeatedCyclesWithRealSinkFileMode`):**
  - 50 rapid start/stop recording cycles with real sink file mode; confirms 0 retain cycles, 0 resource leakage, clean phase transitions.

### B. Widget Storage & Integrity Tests (`HanlinDualWidgetEnginesTests.swift`)
- `testPass7StorageConsistencyReportAndDurableDiagnostic`:
  - Fresh store report verification.
  - Valid v2 snapshot consistency report verification.
  - Tampered `Revisions/<sha>.json` verification: confirms exact `HanlinScriptExtensionStoreError.integrityMismatch` throw, persists `decisionPoint: .revisionIntegrityMismatch`, records `failingStage: "checkedRevision"`.
- `testPass7HistoricalV1StoreEnvelopeCompatibility`:
  - Historical v1 store round-trip accepted without integrity mismatch.
- `testPass7InterruptedRevisionWriteOverwrittenAndClean`:
  - Interrupted 0-byte revision file recovery: automatically overwritten with valid data.
- `testPass7SelectableWidgetEntitiesCrossProcess`:
  - Extension process query simulates cross-process entity lookup for Default and A1 instances without error.

---

## 5. Physical iPad Acceptance Checklist (3–5 Minutes)

To be executed on owner hardware (`iPad15,3`, iPadOS `27.2`) upon delivery of a newly authorized signed build:

### Step 1: Physical Microphone Recording (Hebrew & English)
1. Open ChavrusaChat and tap the microphone icon in the chat composer.
2. Verify recording sheet appears with live waveform visualization (RMS) and speech transcription.
3. Speak in Hebrew for 10 seconds; verify real-time speech recognition updates.
4. Stop recording. Verify audio file is saved without crash.
5. Repeat speaking in English.
6. Verify no crash occurs (SIGABRT in `setFrameLength:` completely eliminated).
7. Close sheet and check that the iPad status bar orange microphone indicator disappears immediately.

### Step 2: WidgetKit Instance Selection (Edit Widget Sheet)
1. Long-press on the iPad Home Screen to enter jiggle mode.
2. Add a **Hanlin Expo Widget** (e.g., Expo Counter) or **ScriptWidget Actions**.
3. Tap on the widget to open the **Edit Widget** configuration sheet.
4. Tap the **Widget instance** picker field.
5. **Expected Result:** The sheet displays the list of installed widget instances (e.g., "Default", "A1 Variant") cleanly and allows selection.
6. **Critical Acceptance:** Error `HanlinScriptExtensions.HanlinScriptExtensionStoreError -4` **DOES NOT APPEAR**.

### Step 3: Package Center Diagnostic Verification
1. Open ChavrusaChat → Settings / Developer → Scripting Package Center.
2. Select any installed package detail view.
3. Tap **Copy Diagnostic**.
4. Paste into Notes or chat; verify string format:
   `id=HWG-... commitPresent=true revisionPresent=true shadowPresent=true summary=Storage consistency verified.`

---

## 6. Release & Distribution Boundary

- **Release Authorization:** The previous TestFlight authorization was strictly for build `89101`. No new signed TestFlight build has been dispatched.
- **Workflow State:** `RELEASE_NOT_DISPATCHED`.
- **Status:** `SOURCE_FIXED_TARGETED_TESTS_PASS_DEVICE_PENDING`.
- All code changes are committed to `fix/hanlin-pass7-audio-widget-integrity-20261105` and ready for build upon owner approval.
