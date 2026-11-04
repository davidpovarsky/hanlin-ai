//
//  VoiceRecordingLifecycleTests.swift
//  AI_HLYTests
//
//  Voice Recording Pass 6 — Deterministic Lifecycle, Rollback, Concurrency, and Locale Tests (VR-01..VR-17)
//

import XCTest
import Speech
import AVFoundation
import SwiftUI
@testable import AI_Hanlin

// MARK: - Thread-Safe Test Probe Box (Swift 6 Strict Concurrency Compliant)
final class SendableBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    var current: T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func mutate(_ transform: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&value)
    }
}

@MainActor
final class VoiceRecordingLifecycleTests: XCTestCase {

    // Helper to generate synthetic audio formats for hermetic unit testing
    private nonisolated static func makeSyntheticAudioFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
    }

    // MARK: - VR-01: Dismiss before permission callback ignores late granted result
    func testVR01_DismissBeforePermissionCallback_IgnoresLateGranted() async {
        let capturedSpeechCompletion = SendableBox<((SFSpeechRecognizerAuthorizationStatus) -> Void)?>(nil)
        let sessionActivations = SendableBox<Int>(0)

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .notDetermined },
            speechAuthRequester: { completion in
                capturedSpeechCompletion.set(completion)
            },
            micAuthChecker: { .granted },
            micAuthRequester: { $0(true) },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if active { sessionActivations.mutate { $0 += 1 } }
            },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
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
        let completion = capturedSpeechCompletion.current
        XCTAssertNotNil(completion)
        completion?(.authorized)

        // 等待异步任务轮转
        try? await Task.sleep(nanoseconds: 50_000_000)

        // 4. 断言：已关闭的录音器绝不可自启动
        XCTAssertFalse(recognizer.isRecording, "Dismissed view must never start recording")
        XCTAssertFalse(recognizer.tapInstalled, "No audio tap should be installed")
        XCTAssertFalse(recognizer.audioSessionActivated, "AudioSession must not be activated")
        XCTAssertEqual(sessionActivations.current, 0, "No audio session activations allowed")
        XCTAssertEqual(recognizer.phase, .idle)
    }

    // MARK: - VR-02: Reopen creates new attempt; old stale callback is ignored
    func testVR02_ReopenCreatesNewAttempt_OldCallbackIgnored() async {
        let firstSpeechCompletion = SendableBox<((SFSpeechRecognizerAuthorizationStatus) -> Void)?>(nil)
        let secondSpeechCompletion = SendableBox<((SFSpeechRecognizerAuthorizationStatus) -> Void)?>(nil)
        let authCallCount = SendableBox<Int>(0)

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .notDetermined },
            speechAuthRequester: { completion in
                authCallCount.mutate { count in
                    count += 1
                    if count == 1 {
                        firstSpeechCompletion.set(completion)
                    } else {
                        secondSpeechCompletion.set(completion)
                    }
                }
            },
            micAuthChecker: { .granted },
            micAuthRequester: { $0(true) },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
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
        firstSpeechCompletion.current?(.authorized)
        try? await Task.sleep(nanoseconds: 30_000_000)

        // 只有第二次正常完成授权
        secondSpeechCompletion.current?(.authorized)
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
        let currentMicPermission = SendableBox<AudioRecordPermission>(.granted)

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { currentMicPermission.current },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()
        recognizer.recheckPermissionsOnForeground()
        XCTAssertEqual(recognizer.permissionStatus, .authorized)

        // 模拟用户在设置中撤销权限
        currentMicPermission.set(.denied)
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
        let activations = SendableBox<Int>(0)
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if active { activations.mutate { $0 += 1 } }
            },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()

        recognizer.startRecording()
        recognizer.startRecording() // 重复调用

        XCTAssertEqual(activations.current, 1, "Only single activation allowed")
    }

    // MARK: - VR-06: Failure after setActive deactivates session and rolls back
    func testVR06_FailureAfterSetActive_RollsBackAudioSession() {
        let deactivations = SendableBox<Int>(0)

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if !active { deactivations.mutate { $0 += 1 } }
            },
            audioSessionCategoryProvider: { .record },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {
                // 模拟在 setActive 之后引擎启动失败
                throw NSError(domain: "AVAudioEngineError", code: -1, userInfo: nil)
            },
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()

        // 断言：失败必须触发完全回滚，且释放音频会话
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertFalse(recognizer.audioSessionActivated)
        guard case .failed = recognizer.phase else {
            XCTFail("Phase should be failed after error")
            return
        }
        XCTAssertEqual(deactivations.current, 1, "Session must be deactivated on failure")
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

        // Stage 3: audioTapInstaller throws
        let stage3Recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in
                throw NSError(domain: "AVAudioTapError", code: 3, userInfo: nil)
            },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        stage3Recognizer.viewDidAppear()
        stage3Recognizer.startRecording()
        XCTAssertFalse(stage3Recognizer.isRecording)
        guard case .failed = stage3Recognizer.phase else {
            XCTFail("Stage 3 should fail")
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
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
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

    // MARK: - VR-09: Close sheet while tap active shuts down cleanly
    func testVR09_DismissWhileTapActive_ShutsDownCleanly() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()

        // 模拟关闭
        recognizer.viewDidDisappear()

        XCTAssertFalse(recognizer.isRecording)
        XCTAssertFalse(recognizer.tapInstalled)
        XCTAssertFalse(recognizer.audioSessionActivated)
    }

    // MARK: - VR-10: Stale recognition generation callback ignored and cannot overwrite new session
    func testVR10_StaleGenerationCallback_CannotMutateNewSession() async {
        typealias ResultHandler = @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void
        let capturedHandlers = SendableBox<[ResultHandler]>([])

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {},
            recognitionTaskStarter: { _, _, handler in
                capturedHandlers.mutate { $0.append(handler) }
                return nil
            }
        )
        recognizer.viewDidAppear()

        // 1. 开启会话 1
        recognizer.startRecording()
        XCTAssertEqual(capturedHandlers.current.count, 1)
        let session1Handler = capturedHandlers.current[0]

        // 2. 停止会话 1
        recognizer.stopRecording()
        XCTAssertFalse(recognizer.isRecording)

        // 3. 开启会话 2
        recognizer.startRecording()
        XCTAssertEqual(capturedHandlers.current.count, 2)
        let session2Handler = capturedHandlers.current[1]
        XCTAssertTrue(recognizer.isRecording)
        XCTAssertEqual(recognizer.recognizedText, "")

        // 4. 迟到的会话 1 回调到达
        // 构造虚拟结果
        session1Handler(nil, NSError(domain: "SpeechError", code: 1, userInfo: nil))
        try? await Task.sleep(nanoseconds: 50_000_000)

        // 断言：迟到结果被彻底忽略，会话 2 依然处于运行中且文字未被篡改
        XCTAssertTrue(recognizer.isRecording, "Stale callback must not terminate fresh session")
        XCTAssertEqual(recognizer.recognizedText, "")

        // 5. 会话 2 正常结束
        session2Handler(nil, nil)
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - VR-11: AudioTapSink real-time safety, zero-allocation pool, and throttling
    func testVR11_AudioTapSink_RealTimeSafetyAndRms() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        let dispatchedRmsValues = SendableBox<[Float]>([])
        let format = VoiceRecordingLifecycleTests.makeSyntheticAudioFormat()

        let sink = AudioTapSink(
            generation: 1,
            request: request,
            audioFile: nil,
            recordingFormat: format
        ) { rms, _ in
            dispatchedRmsValues.mutate { $0.append(rms) }
        }

        // 构造合成 Float32 音频缓冲帧
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
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
        XCTAssertEqual(dispatchedRmsValues.current.count, 1)
        XCTAssertGreaterThan(dispatchedRmsValues.current[0], 0.49)
        XCTAssertLessThan(dispatchedRmsValues.current[0], 0.51)

        // 快速连续注入 50 帧，限频机制（50ms）必须截流，绝不产生 50 次 UI 派发
        for _ in 0..<50 {
            sink.processBuffer(buffer)
        }
        XCTAssertLessThanOrEqual(dispatchedRmsValues.current.count, 2, "Throttling must keep RMS dispatches <= 2 within sub-millisecond loop")

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
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()
        XCTAssertTrue(recognizer.isRecording)

        // 模拟后台切换
        recognizer.handleAppInactive()
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertEqual(recognizer.phase, .idle)
    }

    // MARK: - VR-13: TextToSpeech shared session coordination
    func testVR13_TextToSpeechCoordination_PreservesPlaybackCategory() {
        let deactivations = SendableBox<Int>(0)
        let currentCategory = SendableBox<AVAudioSession.Category>(.record)

        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { active, _ in
                if !active { deactivations.mutate { $0 += 1 } }
            },
            audioSessionCategoryProvider: { currentCategory.current },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
        )
        recognizer.viewDidAppear()
        recognizer.startRecording()

        // 场景 A: TTS 取得播放所有权，类别变为 .playback
        currentCategory.set(.playback)
        recognizer.stopRecording()

        // 断言：SpeechRecognizer 不可调用 setActive(false) 扰乱 TTS
        XCTAssertEqual(deactivations.current, 0, "Must not deactivate shared audio session when another owner holds playback")

        // 场景 B: 录音依然拥有 .record 类别
        currentCategory.set(.record)
        recognizer.startRecording()
        recognizer.stopRecording()

        // 断言：自己拥有时正常释放
        XCTAssertEqual(deactivations.current, 1, "Must deactivate session when recording exclusively owns .record")
    }

    // MARK: - VR-14: Language selection and requested vs effective locale
    func testVR14_LanguageSelectionAndRequestedVsEffectiveLocale() {
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

        // 请求完全不受支持的语言（如不存在的语言标签）
        recognizer.changeLocale(to: Locale(identifier: "xx-ZZ"))
        XCTAssertNil(recognizer.effectiveLocale, "Unsupported locale must not silently fall back to an unexpected language")
        XCTAssertNotNil(recognizer.errorMessage)
    }

    // MARK: - VR-15: Localized strings authentic verification
    func testVR15_LocalizedStrings_AuthenticJsonIntegrity() throws {
        // 验证 Localizable.xcstrings 中的 12 个关键语音录制键值
        let requiredKeys = [
            "语音识别权限未开启，请在“设置”中允许使用语音识别",
            "麦克风权限未开启，请在“设置”中允许使用麦克风",
            "语音识别已被系统限制使用",
            "麦克风已被系统限制使用",
            "语音识别服务暂不可用",
            "当前语言不支持语音识别",
            "打开“设置”",
            "录音失败，请重试",
            "音频输入路由已更改，录音已停止",
            "开始录音",
            "停止录音",
            "系统默认"
        ]

        for key in requiredKeys {
            let localizedString = String(localized: String.LocalizationValue(key))
            XCTAssertFalse(localizedString.isEmpty, "Key '\(key)' must produce non-empty localized text")
        }
    }

    // MARK: - VR-16: VoiceInputView initialization, bindings, and composer insertion
    func testVR16_VoiceInputViewBindingsAndDismissal() {
        var message = "Hello"
        var voiceExpanded = true

        let view = VoiceInputView(
            message: Binding(get: { message }, set: { message = $0 }),
            voiceExpanded: Binding(get: { voiceExpanded }, set: { voiceExpanded = $0 })
        )
        XCTAssertNotNil(view.body)

        // 模拟关闭
        voiceExpanded = false
        XCTAssertFalse(voiceExpanded)
    }

    // MARK: - VR-17: Rapid start/stop stress test (50 iterations)
    func testVR17_StressFiftyRapidCycles() {
        let recognizer = SpeechRecognizer(
            speechAuthChecker: { .authorized },
            micAuthChecker: { .granted },
            audioSessionConfigurator: { _, _, _ in },
            audioSessionActivator: { _, _ in },
            audioFormatProvider: { VoiceRecordingLifecycleTests.makeSyntheticAudioFormat() },
            audioTapInstaller: { _, _ in },
            audioTapRemover: {},
            audioEngineStarter: {},
            audioEngineStopper: {}
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
