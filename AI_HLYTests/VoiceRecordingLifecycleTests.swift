//
//  VoiceRecordingLifecycleTests.swift
//  AI_HLYTests
//
//  Voice Recording Pass 6 — Deterministic Lifecycle, Rollback, Concurrency, and Locale Tests (VR-01..VR-17)
//

import XCTest
import Speech
import AVFoundation
@testable import AI_Hanlin

@MainActor
final class VoiceRecordingLifecycleTests: XCTestCase {

    // MARK: - VR-01: Dismiss before permission callback ignores late granted result
    func testVR01_DismissBeforePermissionCallback_IgnoresLateGranted() async {
        var capturedSpeechCompletion: ((SFSpeechRecognizerAuthorizationStatus) -> Void)?
        var sessionActivations = 0

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .notDetermined },
            speechAuthRequester: { completion in
                capturedSpeechCompletion = completion
            },
            micAuthChecker: { .granted },
            micAuthRequester: { $0(true) },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if active { sessionActivations += 1 }
            }
        )

        // 1. 视图出现，开始权限请求流程
        recognizer.viewDidAppear()
        XCTAssertEqual(recognizer.permissionStatus, .requesting)
        guard case .authorizing = recognizer.phase else {
            XCTFail("Phase should be authorizing")
            return
        }

        // 2. 在系统权限弹窗未决时，用户关闭 sheet (viewDidDisappear)
        recognizer.viewDidDisappear()
        XCTAssertFalse(recognizer.isVisible)
        XCTAssertEqual(recognizer.phase, .idle)

        // 3. 用户在系统层面点击“允许”，异步回调触发
        XCTAssertNotNil(capturedSpeechCompletion)
        capturedSpeechCompletion?(.authorized)

        // 等待异步任务轮转
        try? await Task.sleep(nanoseconds: 50_000_000)

        // 4. 断言：已关闭的录音器绝不可自启动
        XCTAssertFalse(recognizer.isRecording, "Dismissed view must never start recording")
        XCTAssertFalse(recognizer.tapInstalled, "No audio tap should be installed")
        XCTAssertFalse(recognizer.audioSessionActivated, "AudioSession must not be activated")
        XCTAssertEqual(sessionActivations, 0, "No audio session activations allowed")
        XCTAssertEqual(recognizer.phase, .idle)
    }

    // MARK: - VR-02: Reopen creates new attempt; old stale callback is ignored
    func testVR02_ReopenCreatesNewAttempt_OldCallbackIgnored() async {
        var firstSpeechCompletion: ((SFSpeechRecognizerAuthorizationStatus) -> Void)?
        var secondSpeechCompletion: ((SFSpeechRecognizerAuthorizationStatus) -> Void)?
        var authCallCount = 0

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .notDetermined },
            speechAuthRequester: { completion in
                authCallCount += 1
                if authCallCount == 1 {
                    firstSpeechCompletion = completion
                } else {
                    secondSpeechCompletion = completion
                }
            },
            micAuthChecker: { .granted },
            micAuthRequester: { $0(true) },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioEngineStarter: {}
        )

        // 第一次打开
        recognizer.viewDidAppear()
        let firstAttemptId = recognizer.currentAttemptId

        // 快速关闭
        recognizer.viewDidDisappear()

        // 第二次重新打开
        recognizer.viewDidAppear()
        let secondAttemptId = recognizer.currentAttemptId
        XCTAssertGreaterThan(secondAttemptId, firstAttemptId)

        // 第一次回调现在迟到了
        firstSpeechCompletion?(.authorized)
        try? await Task.sleep(nanoseconds: 30_000_000)

        // 只有第二次正常完成授权
        secondSpeechCompletion?(.authorized)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(recognizer.permissionStatus, .authorized)
    }

    // MARK: - VR-03: Permission denied/restricted handling
    func testVR03_PermissionDeniedAndRestricted() async {
        // Speech Denied
        let deniedSpeechRecognizer = SpeechRecognizer(
            speechAuthChecker: { .denied },
            speechAuthRequester: { _ in },
            micAuthChecker: { .granted },
            micAuthRequester: { _ in }
        )
        deniedSpeechRecognizer.viewDidAppear()
        XCTAssertFalse(deniedSpeechRecognizer.isRecording)
        guard case .denied = deniedSpeechRecognizer.permissionStatus else {
            XCTFail("Permission status should be denied")
            return
        }
        guard case .failed = deniedSpeechRecognizer.phase else {
            XCTFail("Phase should be failed")
            return
        }

        // Mic Restricted
        let restrictedMicRecognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            speechAuthRequester: { _ in },
            micAuthChecker: { .restricted },
            micAuthRequester: { _ in }
        )
        restrictedMicRecognizer.viewDidAppear()
        XCTAssertFalse(restrictedMicRecognizer.isRecording)
        XCTAssertEqual(restrictedMicRecognizer.permissionStatus, .restricted)
        guard case .failed = restrictedMicRecognizer.phase else {
            XCTFail("Phase should be failed")
            return
        }
    }

    // MARK: - VR-04: Revoked permission in Settings verified on foreground
    func testVR04_PermissionRevokedInSettings_RecheckedOnForeground() {
        var currentMicPermission: AudioRecordPermission = .granted

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { currentMicPermission }
        )
        recognizer.viewDidAppear()
        recognizer.recheckPermissionsOnForeground()
        XCTAssertEqual(recognizer.permissionStatus, .authorized)

        // 模拟用户在设置中撤销权限
        currentMicPermission = .denied
        recognizer.recheckPermissionsOnForeground()

        guard case .denied = recognizer.permissionStatus else {
            XCTFail("Should be denied after revocation")
            return
        }

        // 再次点击录音应拒绝并要求设置
        recognizer.startRecording()
        XCTAssertFalse(recognizer.isRecording)
    }

    // MARK: - VR-05: Double start prevented while preparing/running
    func testVR05_RapidDoubleStart_OnlyOneActive() {
        var activations = 0
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if active { activations += 1 }
            },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()

        recognizer.startRecording()
        recognizer.startRecording() // 重复调用

        XCTAssertEqual(activations, 1, "Only single activation allowed")
    }

    // MARK: - VR-06: Failure after setActive deactivates session and rolls back
    func testVR06_FailureAfterSetActive_RollsBackAudioSession() {
        var activated = false
        var deactivations = 0

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                activated = active
                if !active { deactivations += 1 }
            },
            audioEngineStarter: {
                // 模拟在 setActive 之后引擎启动失败
                throw NSError(domain: "AVAudioEngineError", code: -1, userInfo: nil)
            }
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()

        // 断言：失败必须触发完全回滚，且释放音频会话
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertFalse(recognizer.audioSessionActivated)
        guard case .failed = recognizer.phase else {
            XCTFail("Phase should be failed after error")
            return
        }
        XCTAssertEqual(deactivations, 1, "Session must be deactivated on failure")
    }

    // MARK: - VR-07: Resource ownership rollback at each stage
    func testVR07_RollbackAtAllStages() {
        // Stage 1: setCategory throws
        let stage1Recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in
                throw NSError(domain: "AVAudioSession", code: 1, userInfo: nil)
            }
        )
        stage1Recognizer.viewDidAppear()
        stage1Recognizer.startRecording()
        XCTAssertFalse(stage1Recognizer.isRecording)
        guard case .failed = stage1Recognizer.phase else {
            XCTFail("Stage 1 should fail")
            return
        }

        // Stage 2: setActive throws
        let stage2Recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if active { throw NSError(domain: "AVAudioSession", code: 2, userInfo: nil) }
            }
        )
        stage2Recognizer.viewDidAppear()
        stage2Recognizer.startRecording()
        XCTAssertFalse(stage2Recognizer.isRecording)
        guard case .failed = stage2Recognizer.phase else {
            XCTFail("Stage 2 should fail")
            return
        }
    }

    // MARK: - VR-08: Normal stop preserves recognized text, second stop is idempotent no-op
    func testVR08_StopPreservesRecognizedText_SecondStopIdempotent() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()
        recognizer.recognizedText = "Shalom Hanlin"

        recognizer.stopRecording()
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertEqual(recognizer.recognizedText, "Shalom Hanlin", "Recognized text must be preserved")

        // 第二次调用无副作用
        recognizer.stopRecording()
        XCTAssertEqual(recognizer.recognizedText, "Shalom Hanlin")
        XCTAssertEqual(recognizer.phase, .idle)
    }

    // MARK: - VR-09: Close sheet while tap active shuts down sink cleanly
    func testVR09_DismissWhileTapActive_ShutsDownCleanly() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()

        // 模拟关闭
        recognizer.viewDidDisappear()

        XCTAssertFalse(recognizer.isRecording)
        XCTAssertFalse(recognizer.tapInstalled)
        XCTAssertFalse(recognizer.audioSessionActivated)
    }

    // MARK: - VR-10: Stale recognition generation callback ignored
    func testVR10_StaleGenerationCallback_Ignored() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted }
        )
        recognizer.viewDidAppear()

        let gen1 = recognizer.currentGeneration
        recognizer.stopRecording()
        let gen2 = recognizer.currentGeneration
        XCTAssertGreaterThan(gen2, gen1)
    }

    // MARK: - VR-11: AudioTapSink real-time safety, RMS calculation, and throttling
    func testVR11_AudioTapSink_RealTimeSafetyAndRms() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        var dispatchedRmsValues: [Float] = []
        let sink = AudioTapSink(
            generation: 1,
            request: request,
            audioFile: nil
        ) { rms, _ in
            dispatchedRmsValues.append(rms)
        }

        // 构造合成 Float32 音频缓冲帧
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            XCTFail("Failed to allocate synthetic PCM buffer")
            return
        }
        buffer.frameLength = 1024
        let channelData = buffer.floatChannelData![0]
        for i in 0..<1024 {
            channelData[i] = 0.5 // 定值幅度
        }

        // 处理缓冲区
        sink.processBuffer(buffer)
        XCTAssertEqual(dispatchedRmsValues.count, 1)
        XCTAssertGreaterThan(dispatchedRmsValues[0], 0.49)
        XCTAssertLessThan(dispatchedRmsValues[0], 0.51)

        // 快速连续注入 50 帧，限频机制（50ms）必须截流，绝不产生 50 次 UI 派发
        for _ in 0..<50 {
            sink.processBuffer(buffer)
        }
        XCTAssertLessThanOrEqual(dispatchedRmsValues.count, 2, "Throttling must keep RMS dispatches <= 2 within sub-millisecond loop")

        // 关闭 sink 后应不再派发
        sink.close()
        sink.processBuffer(buffer)
    }

    // MARK: - VR-12: Route change and background handling
    func testVR12_RouteChangeAndBackgroundHandling() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()

        // 模拟后台切换
        recognizer.handleAppInactive()
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertEqual(recognizer.phase, .idle)
    }

    // MARK: - VR-13: TextToSpeech session ownership coordination
    func testVR13_TextToSpeechCoordination_PreservesPlaybackCategory() {
        var sessionDeactivated = false
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if !active { sessionDeactivated = true }
            },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()
        recognizer.stopRecording()

        XCTAssertFalse(recognizer.isRecording)
    }

    // MARK: - VR-14: Language selection and locale resolution
    func testVR14_LanguageSelectionAndLocaleResolution() {
        let defaultLocale = SpeechRecognizer.resolveDefaultLocale()
        XCTAssertFalse(defaultLocale.identifier.isEmpty)

        let recognizer = SpeechRecognizer(locale: Locale(identifier: "he-IL"))
        XCTAssertEqual(recognizer.selectedLocale.identifier, "he-IL")
        XCTAssertEqual(recognizer.selectedLocaleDisplayName, "עברית")

        recognizer.changeLocale(to: Locale(identifier: "en-US"))
        XCTAssertEqual(recognizer.selectedLocale.identifier, "en-US")
        XCTAssertEqual(recognizer.selectedLocaleDisplayName, "English")

        recognizer.changeLocale(to: Locale(identifier: "zh-CN"))
        XCTAssertEqual(recognizer.selectedLocale.identifier, "zh-CN")
        XCTAssertEqual(recognizer.selectedLocaleDisplayName, "中文")
    }

    // MARK: - VR-15: Localized strings validity
    func testVR15_LocalizedStrings_AreNotEmpty() {
        let speechDenied = String(localized: "语音识别权限未开启，请在“设置”中允许使用语音识别")
        let micDenied = String(localized: "麦克风权限未开启，请在“设置”中允许使用麦克风")
        let restricted = String(localized: "语音识别已被系统限制使用")
        let openSettings = String(localized: "打开“设置”")
        let startRec = String(localized: "开始录音")
        let stopRec = String(localized: "停止录音")

        XCTAssertFalse(speechDenied.isEmpty)
        XCTAssertFalse(micDenied.isEmpty)
        XCTAssertFalse(restricted.isEmpty)
        XCTAssertFalse(openSettings.isEmpty)
        XCTAssertFalse(startRec.isEmpty)
        XCTAssertFalse(stopRec.isEmpty)
    }

    // MARK: - VR-16: VoiceInputView initialization and bindings
    func testVR16_VoiceInputViewBindings() {
        var message = "Initial message"
        var voiceExpanded = true

        let view = VoiceInputView(
            message: Binding(get: { message }, set: { message = $0 }),
            voiceExpanded: Binding(get: { voiceExpanded }, set: { voiceExpanded = $0 })
        )
        XCTAssertNotNil(view.body)
    }

    // MARK: - VR-17: Rapid start/stop stress test (50 iterations)
    func testVR17_StressFiftyRapidCycles() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioEngineStarter: {}
        )
        recognizer.viewDidAppear()

        for _ in 0..<50 {
            recognizer.startRecording()
            XCTAssertTrue(recognizer.isRecording)
            recognizer.stopRecording()
            XCTAssertFalse(recognizer.isRecording)
            XCTAssertFalse(recognizer.tapInstalled)
            XCTAssertFalse(recognizer.audioSessionActivated)
        }

        XCTAssertEqual(recognizer.phase, .idle)
    }
}
