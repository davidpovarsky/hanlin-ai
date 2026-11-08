//
//  VoiceInputView.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 22/3/25.
//

import SwiftUI
@preconcurrency import Speech
@preconcurrency import AVFoundation
import Combine

// MARK: - 语音输入界面
struct VoiceInputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Binding var message: String
    @Binding var voiceExpanded: Bool
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var isOptimizing: Bool = false
    @State private var optimized: Bool = false
    @State private var optimizedMessage: String = ""
    @State private var isFeedBack: Bool = false
    @State private var original: String = ""
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // 实时识别的文字展示
            VStack(alignment: .leading) {
                TextEditor(text: $message)
                    .foregroundColor(.primary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                Spacer()
                ScrollView(.horizontal) {
                    Text(speechRecognizer.recognizedText)
                        .lineLimit(1)
                        .foregroundColor(.hlBluefont)
                        .padding(12)
                }
                .defaultScrollAnchor(.trailing)
            }
            .padding(.horizontal)

            // 语言选择与状态指示条
            HStack {
                Menu {
                    Button(action: { speechRecognizer.changeLocale(to: SpeechRecognizer.resolveDefaultLocale()) }) {
                        Text(String(localized: "系统默认"))
                    }
                    Button(action: { speechRecognizer.changeLocale(to: Locale(identifier: "he-IL")) }) {
                        Text("עברית (ישראל)")
                    }
                    Button(action: { speechRecognizer.changeLocale(to: Locale(identifier: "en-US")) }) {
                        Text("English (US)")
                    }
                    Button(action: { speechRecognizer.changeLocale(to: Locale(identifier: "zh-CN")) }) {
                        Text("简体中文")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(speechRecognizer.selectedLocaleDisplayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color(.systemGray5)))
                    .foregroundColor(.primary)
                }
                .disabled(speechRecognizer.isRecording)

                Spacer()

                if let err = speechRecognizer.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)

            // 权限提示（若被拒绝或受限）
            if case .denied(let reason) = speechRecognizer.permissionStatus {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: openSettings) {
                        Text(String(localized: "打开“设置”"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.hlBluefont)
                    }
                }
                .padding(.horizontal)
            } else if case .restricted = speechRecognizer.permissionStatus {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.secondary)
                    Text(String(localized: "语音识别已被系统限制使用"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: openSettings) {
                        Text(String(localized: "打开“设置”"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.hlBluefont)
                    }
                }
                .padding(.horizontal)
            }

            HStack {
                // 录音/停止按钮
                Button(action: {
                    isFeedBack.toggle()
                    if speechRecognizer.isRecording {
                        // 停止录音
                        speechRecognizer.stopRecording()
                        if !speechRecognizer.recognizedText.isEmpty {
                            message += speechRecognizer.recognizedText
                        }
                        if let url = speechRecognizer.recordedAudioURL {
                            print("录音文件存储在：\(url)")
                        }
                    } else {
                        // 开始录音（如果未授权则先请求权限）
                        if speechRecognizer.permissionStatus == .authorized {
                            speechRecognizer.startRecording()
                        } else {
                            speechRecognizer.requestPermissionsAndStartIfAuthorized()
                        }
                    }
                }) {
                    Image(systemName: speechRecognizer.isRecording
                          ? "arrowtriangle.up.circle"
                          : "microphone.circle"
                    )
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .font(.system(size: 40))
                    .foregroundColor(speechRecognizer.isRecording ? .hlRed : isOptimizing ? .gray : .hlBluefont)
                    .padding(12)
                }
                .disabled(isOptimizing)
                .accessibilityLabel(speechRecognizer.isRecording ? String(localized: "停止录音") : String(localized: "开始录音"))

                Spacer()

                if speechRecognizer.isRecording {
                    // 柱状波形可视化
                    ScrollView(.horizontal) {
                        HStack(alignment: .center) {
                            WaveformBarsView(currentLevel: $speechRecognizer.audioLevel)
                                .frame(
                                    minWidth: UIScreen.main.bounds.width * 0.8,
                                    minHeight: 40,
                                    alignment: .center
                                )
                        }
                        .frame(minHeight: 40, alignment: .center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
                    .defaultScrollAnchor(.trailing)
                    .accessibilityHidden(true)
                }

                Spacer()

                if !speechRecognizer.isRecording {
                    Button(action: optimizeMessage) {
                        if isOptimizing {
                            ProgressView()
                                .frame(width: 40, height: 40)
                                .font(.system(size: 40))
                                .background(Capsule().fill(Color(.hlBluefont).opacity(0.1)))
                                .padding(.vertical, 12)
                        } else if optimized {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .font(.system(size: 40))
                                .foregroundColor(.hlBluefont)
                                .padding(.vertical, 12)
                        } else {
                            Image(systemName: "hammer.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                                .font(.system(size: 40))
                                .foregroundColor(speechRecognizer.isRecording ? .gray : .hlBluefont)
                                .padding(.vertical, 12)
                        }
                    }
                    .disabled(isOptimizing || speechRecognizer.isRecording)
                    .accessibilityLabel(String(localized: "优化提示词"))
                    .onChange(of: message) {
                        if optimized && (message != optimizedMessage) {
                            optimized = false
                        } else if message == optimizedMessage, !message.isEmpty {
                            optimized = true
                        }
                    }
                }

                // 插入
                Button(action: {
                    isFeedBack.toggle()
                    if speechRecognizer.isRecording {
                        speechRecognizer.stopRecording()
                        if !speechRecognizer.recognizedText.isEmpty {
                            message += speechRecognizer.recognizedText
                        }
                    }
                    voiceExpanded = false
                }) {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .font(.system(size: 40))
                        .foregroundColor(speechRecognizer.isRecording ? .gray : .hlBluefont)
                        .padding(12)
                }
                .disabled(isOptimizing || speechRecognizer.isRecording)
                .accessibilityLabel(String(localized: "插入"))
            }
            .background(
                BlurView(style: .systemUltraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .shadow(color: .hlBlue, radius: 1)
            )
            .padding(.horizontal)
            .sensoryFeedback(.impact, trigger: isFeedBack)

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .onAppear {
            speechRecognizer.viewDidAppear()
        }
        .onDisappear {
            speechRecognizer.viewDidDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                speechRecognizer.recheckPermissionsOnForeground()
            } else {
                speechRecognizer.handleAppInactive()
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }

    // 文本优化
    private func optimizeMessage() {
        isFeedBack.toggle()
        Task {
            if optimized {
                if !original.isEmpty {
                    message = original
                }
                optimized = false
            } else {
                optimized = false
                isOptimizing = true
                original = message
                if !message.isEmpty {
                    do {
                        let optimizer = SystemOptimizer(context: modelContext)
                        optimizedMessage = try await optimizer.optimizePrompt(inputPrompt: message)
                        message = optimizedMessage
                        optimized = true
                    } catch {
                        errorMessage = error.localizedDescription
                        showErrorAlert = true
                    }
                }
                isOptimizing = false
            }
        }
    }
}

// MARK: - 波形视图
struct WaveformBarsView: View {
    @Binding var currentLevel: Float
    @State private var amplitudeValues: [Float] = []

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3

    private let refreshTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let maxBarCount = Int(totalWidth / (barWidth + barSpacing))

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0 ..< amplitudeValues.count, id: \.self) { index in
                    let amplitude = amplitudeValues[index]
                    let normalized = max(0.1, min(amplitude * 35, 1.0))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.hlBluefont)
                        .frame(
                            width: barWidth,
                            height: min(CGFloat(normalized) * geometry.size.height, 40)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 40)
            .onReceive(refreshTimer) { _ in
                amplitudeValues.append(currentLevel)
                if amplitudeValues.count > maxBarCount {
                    amplitudeValues.removeFirst(amplitudeValues.count - maxBarCount)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 40)
    }
}

// MARK: - 录音与权限状态
enum RecordingPhase: Equatable, Sendable {
    case idle
    case authorizing(attemptId: UInt64)
    case preparing(attemptId: UInt64)
    case running(attemptId: UInt64)
    case stopping(attemptId: UInt64)
    case failed(attemptId: UInt64, reason: String)
}

enum AudioRecordPermission: Equatable, Sendable {
    case undetermined
    case granted
    case denied
    case restricted
}

// MARK: - SpeechRecognizer 类
/// 使用 Apple Speech 框架实现语音识别，同时通过 AVAudioEngine 获取音频信号的 RMS 值用于波形可视化。
/// 严格遵守 Swift 6 并发模型，支持精确世代失效、全分支资源回滚、多语言自适应及路由中断安全处理。
@MainActor
final class SpeechRecognizer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    enum PermissionStatus: Equatable {
        case notDetermined
        case requesting
        case authorized
        case denied(String)
        case restricted
    }

    @Published var recognizedText: String = ""
    @Published var isRecording: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var recordedAudioURL: URL? = nil
    @Published var permissionStatus: PermissionStatus = .notDetermined
    @Published var phase: RecordingPhase = .idle
    @Published var selectedLocale: Locale
    @Published var effectiveLocale: Locale?
    @Published var errorMessage: String? = nil

    // 测试与依赖注入闭包类型定义
    typealias SpeechAuthChecker = @Sendable () -> SFSpeechRecognizerAuthorizationStatus
    typealias SpeechAuthRequester = @Sendable (@escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    typealias MicAuthChecker = @Sendable () -> AudioRecordPermission
    typealias MicAuthRequester = @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
    typealias AudioSessionConfigurator = @Sendable (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions) throws -> Void
    typealias AudioSessionActivator = @Sendable (Bool, AVAudioSession.SetActiveOptions) throws -> Void
    typealias AudioSessionCategoryProvider = @Sendable () -> AVAudioSession.Category
    typealias AudioFormatProvider = @Sendable () -> AVAudioFormat?
    typealias AudioTapInstaller = @Sendable (AVAudioFormat, @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws -> Void
    typealias AudioTapRemover = @Sendable () -> Void
    typealias AudioEngineStarter = @Sendable () throws -> Void
    typealias AudioEngineStopper = @Sendable () -> Void
    typealias RecognitionTaskStarter = @Sendable (SFSpeechRecognizer, SFSpeechAudioBufferRecognitionRequest, @escaping @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void) -> SFSpeechRecognitionTask?

    private let speechAuthChecker: SpeechAuthChecker
    private let speechAuthRequester: SpeechAuthRequester
    private let micAuthChecker: MicAuthChecker
    private let micAuthRequester: MicAuthRequester
    private let audioSessionConfigurator: AudioSessionConfigurator
    private let audioSessionActivator: AudioSessionActivator
    private let audioSessionCategoryProvider: AudioSessionCategoryProvider
    private let audioFormatProvider: AudioFormatProvider
    private let audioTapInstaller: AudioTapInstaller
    private let audioTapRemover: AudioTapRemover
    private let audioEngineStarter: AudioEngineStarter?
    private let audioEngineStopper: AudioEngineStopper
    private let recognitionTaskStarter: RecognitionTaskStarter

    // 视图可见性与世代跟踪
    private(set) var isVisible: Bool = false
    private(set) var currentAttemptId: UInt64 = 0
    private(set) var currentGeneration: Int = 0

    // 资源归属标志（用于精确安全回滚）
    private(set) var audioSessionActivated: Bool = false
    private(set) var tapInstalled: Bool = false
    private(set) var audioEngineRunning: Bool = false

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var tempRecordingURL: URL?
    private var audioSink: AudioTapSink?

    #if DEBUG
    var testHasRecordingResources: Bool {
        audioFile != nil || audioSink != nil || recognitionRequest != nil || recognitionTask != nil
    }
    #endif

    // 语言展示名
    var selectedLocaleDisplayName: String {
        let id = selectedLocale.identifier
        if id.starts(with: "he") {
            return "עברית"
        } else if id.starts(with: "en") {
            return "English"
        } else if id.starts(with: "zh") {
            return "中文"
        } else {
            return selectedLocale.localizedString(forIdentifier: id) ?? id
        }
    }

    init(
        locale: Locale? = nil,
        speechAuthChecker: @escaping SpeechAuthChecker = { SFSpeechRecognizer.authorizationStatus() },
        speechAuthRequester: @escaping SpeechAuthRequester = { SFSpeechRecognizer.requestAuthorization($0) },
        micAuthChecker: @escaping MicAuthChecker = { SpeechRecognizer.systemMicAuthChecker() },
        micAuthRequester: @escaping MicAuthRequester = { SpeechRecognizer.systemMicAuthRequester($0) },
        audioSessionConfigurator: @escaping AudioSessionConfigurator = { cat, mode, opt in
            try AVAudioSession.sharedInstance().setCategory(cat, mode: mode, options: opt)
        },
        audioSessionActivator: @escaping AudioSessionActivator = { active, opt in
            try AVAudioSession.sharedInstance().setActive(active, options: opt)
        },
        audioSessionCategoryProvider: @escaping AudioSessionCategoryProvider = {
            AVAudioSession.sharedInstance().category
        },
        audioFormatProvider: AudioFormatProvider? = nil,
        audioTapInstaller: AudioTapInstaller? = nil,
        audioTapRemover: AudioTapRemover? = nil,
        audioEngineStarter: AudioEngineStarter? = nil,
        audioEngineStopper: AudioEngineStopper? = nil,
        recognitionTaskStarter: RecognitionTaskStarter? = nil
    ) {
        let resolvedLocale = locale ?? SpeechRecognizer.resolveDefaultLocale()
        self.selectedLocale = resolvedLocale
        self.speechAuthChecker = speechAuthChecker
        self.speechAuthRequester = speechAuthRequester
        self.micAuthChecker = micAuthChecker
        self.micAuthRequester = micAuthRequester
        self.audioSessionConfigurator = audioSessionConfigurator
        self.audioSessionActivator = audioSessionActivator
        self.audioSessionCategoryProvider = audioSessionCategoryProvider
        self.audioEngineStarter = audioEngineStarter

        let engine = self.audioEngine
        self.audioFormatProvider = audioFormatProvider ?? { [weak engine] in
            engine?.inputNode.outputFormat(forBus: 0)
        }
        self.audioTapInstaller = audioTapInstaller ?? { [weak engine] format, handler in
            guard let inputNode = engine?.inputNode else { return }
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                handler(buffer)
            }
        }
        self.audioTapRemover = audioTapRemover ?? { [weak engine] in
            engine?.inputNode.removeTap(onBus: 0)
        }
        self.audioEngineStopper = audioEngineStopper ?? { [weak engine] in
            engine?.stop()
        }
        self.recognitionTaskStarter = recognitionTaskStarter ?? { recognizer, request, handler in
            recognizer.recognitionTask(with: request, resultHandler: handler)
        }

        super.init()

        if let recognizer = resolveRecognizer(for: resolvedLocale) {
            self.speechRecognizer = recognizer
            self.effectiveLocale = recognizer.locale
            recognizer.delegate = self
        } else {
            self.speechRecognizer = nil
            self.effectiveLocale = nil
            self.errorMessage = String(localized: "当前语言不支持语音识别")
        }

        // 监听音频中断与硬件路由变更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 语言解析与切换
    nonisolated static func resolveDefaultLocale() -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        for preferred in Locale.preferredLanguages {
            let preferredLocale = Locale(identifier: preferred)
            if supported.contains(preferredLocale) {
                return preferredLocale
            }
            if let langCode = preferredLocale.language.languageCode?.identifier {
                if let match = supported.first(where: { $0.language.languageCode?.identifier == langCode }) {
                    return match
                }
            }
        }
        if supported.contains(Locale(identifier: "he-IL")) {
            return Locale(identifier: "he-IL")
        }
        if supported.contains(Locale(identifier: "en-US")) {
            return Locale(identifier: "en-US")
        }
        if supported.contains(Locale(identifier: "zh-CN")) {
            return Locale(identifier: "zh-CN")
        }
        return supported.first ?? Locale(identifier: "en-US")
    }

    func changeLocale(to newLocale: Locale) {
        if isRecording {
            stopRecording()
        }
        selectedLocale = newLocale
        errorMessage = nil
        if let recognizer = resolveRecognizer(for: newLocale) {
            speechRecognizer = recognizer
            effectiveLocale = recognizer.locale
            recognizer.delegate = self
        } else {
            effectiveLocale = nil
            let msg = String(localized: "当前语言不支持语音识别")
            errorMessage = msg
        }
    }

    private func resolveRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        if let r = SFSpeechRecognizer(locale: locale), r.isAvailable {
            return r
        }
        return nil
    }

    // MARK: - 视图与前后台生命周期
    func viewDidAppear() {
        isVisible = true
        requestPermissionsAndStartIfAuthorized()
    }

    func viewDidDisappear() {
        isVisible = false
        currentAttemptId += 1
        stopRecording()
    }

    func handleAppInactive() {
        if isRecording || phase != .idle {
            stopRecording()
        }
    }

    func recheckPermissionsOnForeground() {
        guard isVisible else { return }
        let speechStatus = speechAuthChecker()
        let micStatus = micAuthChecker()
        if speechStatus == .authorized && micStatus == .granted {
            permissionStatus = .authorized
            errorMessage = nil
        } else if speechStatus == .denied || micStatus == .denied {
            if isRecording {
                stopRecording()
            }
            if speechStatus == .denied {
                permissionStatus = .denied(String(localized: "语音识别权限未开启，请在“设置”中允许使用语音识别"))
            } else {
                permissionStatus = .denied(String(localized: "麦克风权限未开启，请在“设置”中允许使用麦克风"))
            }
        }
    }

    // MARK: - 通知处理
    @objc nonisolated private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .began {
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stopRecording()
            }
        }
    }

    @objc nonisolated private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        Task { @MainActor [weak self] in
            self?.handleAudioRouteChange(reason: reason)
        }
    }

    func handleAudioRouteChange(reason: AVAudioSession.RouteChangeReason) {
        guard isRecording else { return }
        switch reason {
        case .categoryChange where audioSessionCategoryProvider() == .record:
            // Starting our own recording changes the category to .record. Its
            // notification is delivered after start finishes; it is not a lost input.
            return
        case .oldDeviceUnavailable, .categoryChange:
            stopRecording()
            errorMessage = String(localized: "音频输入路由已更改，录音已停止")
        default:
            break
        }
    }

    // MARK: - 权限请求
    func requestPermissionsAndStartIfAuthorized() {
        guard isVisible else { return }
        if isRecording { return }
        if case .preparing = phase { return }
        if case .running = phase { return }

        currentAttemptId += 1
        let attemptId = currentAttemptId
        phase = .authorizing(attemptId: attemptId)
        permissionStatus = .requesting
        errorMessage = nil

        let speechStatus = speechAuthChecker()
        switch speechStatus {
        case .authorized:
            checkMicrophonePermission(attemptId: attemptId)
        case .notDetermined:
            speechAuthRequester { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self, self.isVisible, self.currentAttemptId == attemptId, case .authorizing = self.phase else {
                        return
                    }
                    if status == .authorized {
                        self.checkMicrophonePermission(attemptId: attemptId)
                    } else if status == .restricted {
                        self.permissionStatus = .restricted
                        self.phase = .failed(attemptId: attemptId, reason: String(localized: "语音识别已被系统限制使用"))
                    } else {
                        let reason = String(localized: "语音识别权限未开启，请在“设置”中允许使用语音识别")
                        self.permissionStatus = .denied(reason)
                        self.phase = .failed(attemptId: attemptId, reason: reason)
                    }
                }
            }
        case .denied:
            let reason = String(localized: "语音识别权限未开启，请在“设置”中允许使用语音识别")
            permissionStatus = .denied(reason)
            phase = .failed(attemptId: attemptId, reason: reason)
        case .restricted:
            permissionStatus = .restricted
            phase = .failed(attemptId: attemptId, reason: String(localized: "语音识别已被系统限制使用"))
        @unknown default:
            let reason = String(localized: "语音识别权限未开启，请在“设置”中允许使用语音识别")
            permissionStatus = .denied(reason)
            phase = .failed(attemptId: attemptId, reason: reason)
        }
    }

    private func checkMicrophonePermission(attemptId: UInt64) {
        guard isVisible, currentAttemptId == attemptId, case .authorizing = phase else { return }
        let micStatus = micAuthChecker()
        switch micStatus {
        case .granted:
            permissionStatus = .authorized
            startRecordingSession(attemptId: attemptId)
        case .undetermined:
            micAuthRequester { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.isVisible, self.currentAttemptId == attemptId, case .authorizing = self.phase else {
                        return
                    }
                    if granted {
                        self.permissionStatus = .authorized
                        self.startRecordingSession(attemptId: attemptId)
                    } else {
                        let reason = String(localized: "麦克风权限未开启，请在“设置”中允许使用麦克风")
                        self.permissionStatus = .denied(reason)
                        self.phase = .failed(attemptId: attemptId, reason: reason)
                    }
                }
            }
        case .denied:
            let reason = String(localized: "麦克风权限未开启，请在“设置”中允许使用麦克风")
            permissionStatus = .denied(reason)
            phase = .failed(attemptId: attemptId, reason: reason)
        case .restricted:
            permissionStatus = .restricted
            phase = .failed(attemptId: attemptId, reason: String(localized: "麦克风已被系统限制使用"))
        }
    }

    // MARK: - 录音控制
    func startRecording() {
        guard isVisible else { return }
        if isRecording || tapInstalled || audioEngineRunning { return }
        guard permissionStatus == .authorized else {
            requestPermissionsAndStartIfAuthorized()
            return
        }

        currentAttemptId += 1
        let attemptId = currentAttemptId
        startRecordingSession(attemptId: attemptId)
    }

    private func startRecordingSession(attemptId: UInt64) {
        guard isVisible, currentAttemptId == attemptId else { return }
        guard !isRecording && !tapInstalled && !audioEngineRunning else { return }

        phase = .preparing(attemptId: attemptId)
        currentGeneration += 1
        let generation = currentGeneration

        recognizedText = ""
        audioLevel = 0.0
        errorMessage = nil

        // 1. 语言与识别器校验
        guard let recognizer = speechRecognizer ?? resolveRecognizer(for: selectedLocale) else {
            let errorMsg = String(localized: "当前语言不支持语音识别")
            rollbackPartialStart(attemptId: attemptId, reason: errorMsg)
            return
        }
        guard recognizer.isAvailable else {
            let errorMsg = String(localized: "语音识别服务暂不可用")
            rollbackPartialStart(attemptId: attemptId, reason: errorMsg)
            return
        }
        self.speechRecognizer = recognizer
        self.effectiveLocale = recognizer.locale
        recognizer.delegate = self

        // 2. 配置与激活音频会话
        do {
            try audioSessionConfigurator(.record, .measurement, .duckOthers)
            try audioSessionActivator(true, .notifyOthersOnDeactivation)
            audioSessionActivated = true
        } catch {
            rollbackPartialStart(attemptId: attemptId, reason: error.localizedDescription)
            return
        }

        // 3. 校验音频输入格式
        guard let recordingFormat = audioFormatProvider(),
              recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            rollbackPartialStart(attemptId: attemptId, reason: "Invalid audio format")
            return
        }

        // 4. 创建录音文件（可选，文件不可用时不阻断语音转文字）
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).caf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        var audioFile: AVAudioFile? = nil
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
            self.tempRecordingURL = fileURL
            self.recordedAudioURL = fileURL
        } catch {
            self.tempRecordingURL = nil
            self.recordedAudioURL = nil
            audioFile = nil
        }
        self.audioFile = audioFile

        // 5. 创建识别请求与 AudioTapSink
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let sink = AudioTapSink(
            generation: generation,
            request: request,
            audioFile: audioFile,
            recordingFormat: recordingFormat
        ) { [weak self] (rms: Float, gen: Int) in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, self.currentGeneration == gen else { return }
                self.audioLevel = rms
            }
        }
        self.audioSink = sink

        // 6. 安装实时音频 Tap
        if tapInstalled {
            audioTapRemover()
            tapInstalled = false
        }
        do {
            try audioTapInstaller(recordingFormat) { buffer in
                sink.processBuffer(buffer)
            }
            tapInstalled = true
        } catch {
            rollbackPartialStart(attemptId: attemptId, reason: error.localizedDescription)
            return
        }

        // 7. 启动音频引擎
        if let customStarter = audioEngineStarter {
            do {
                try customStarter()
                audioEngineRunning = true
            } catch {
                rollbackPartialStart(attemptId: attemptId, reason: error.localizedDescription)
                return
            }
        } else {
            audioEngine.prepare()
            do {
                try audioEngine.start()
                audioEngineRunning = true
            } catch {
                rollbackPartialStart(attemptId: attemptId, reason: error.localizedDescription)
                return
            }
        }

        // 8. 启动语音识别任务
        let task = recognitionTaskStarter(recognizer, request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil

            Task { @MainActor [weak self] in
                guard let self, self.currentGeneration == generation else { return }
                if let text {
                    self.recognizedText = text
                }
                if hasError || isFinal {
                    self.stopRecording()
                }
            }
        }
        self.recognitionTask = task

        isRecording = true
        phase = .running(attemptId: attemptId)
    }

    private func rollbackPartialStart(attemptId: UInt64, reason: String) {
        cleanupOwnedResources()
        phase = .failed(attemptId: attemptId, reason: reason)
        errorMessage = reason
        isRecording = false
        audioLevel = 0.0
        if let tempURL = tempRecordingURL {
            try? FileManager.default.removeItem(at: tempURL)
            tempRecordingURL = nil
            recordedAudioURL = nil
        }
    }

    /// 停止录音和语音识别（幂等安全，不丢失已有识别文字）
    func stopRecording() {
        currentAttemptId += 1
        cleanupOwnedResources()
        isRecording = false
        audioLevel = 0.0
        if case .running = phase {
            phase = .idle
        } else if case .authorizing = phase {
            phase = .idle
        } else if case .preparing = phase {
            phase = .idle
        }
    }

    private func cleanupOwnedResources() {
        currentGeneration += 1

        audioSink?.close()
        audioSink = nil

        if tapInstalled {
            audioTapRemover()
            tapInstalled = false
        }
        if audioEngineRunning || audioEngine.isRunning {
            audioEngineStopper()
            audioEngineRunning = false
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        audioFile = nil

        if audioSessionActivated {
            audioSessionActivated = false
            let currentCategory = audioSessionCategoryProvider()
            if currentCategory != .playback {
                do {
                    try audioSessionActivator(false, .notifyOthersOnDeactivation)
                } catch {
                    // Non-fatal
                }
            }
        }
    }

    // MARK: - 系统权限适配
    nonisolated static func systemMicAuthChecker() -> AudioRecordPermission {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .undetermined: return .undetermined
            case .denied: return .denied
            @unknown default: return .denied
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted: return .granted
            case .undetermined: return .undetermined
            case .denied: return .denied
            @unknown default: return .denied
            }
        }
    }

    nonisolated static func systemMicAuthRequester(_ completion: @escaping @Sendable (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(completion)
        }
    }
}

// MARK: - AudioTapSink (Swift 6 实时音频回调安全隔离与非阻塞零分配写入)
/// 专用于桥接 AVAudioEngine 实时音频回调与 SFSpeechAudioBufferRecognitionRequest 的线程安全接收器。
/// 关键并发与实时性保证：
/// 1. AVFoundation 在内部专用音频线程串行调用 tap 回调。
/// 2. mutable 状态由轻量 NSLock 保护，仅持锁微秒级别执行 request.append 与预分配内存池借用。
/// 3. 音频文件写入移至后台串行队列，带最大有界深度保护（16个预分配池化缓冲区），无堆分配（Zero-allocation），避免阻塞实时音频线程或产生内存膨胀。
/// 4. RMS 计算为无锁、无堆分配（Zero-allocation），严格校验 Float32 格式及有限值。
/// 5. UI 派发限制在 ~20Hz（50ms），最后派发时间戳在锁内安全同步，杜绝数据竞争。
/// 6. close() 安全标记并清理内存池，无死锁与主线程阻塞风险。
internal final class AudioTapSink: @unchecked Sendable {
    private let generation: Int
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let audioFile: AVAudioFile?
    private let onRmsLevel: @Sendable (Float, Int) -> Void

    private let lock = NSLock()
    private var isClosed = false
    private var lastRmsDispatchTime: UInt64 = 0

    private let fileWriterQueue = DispatchQueue(label: "org.hanlin.AudioFileWriter", qos: .utility)
    private var bufferPool: [AVAudioPCMBuffer] = []
    private var droppedWritesCount: Int = 0
    private var lastDropLogNanoseconds: UInt64 = 0
    private let maxPoolCapacity: Int = 16
    private let poolBufferCapacity: AVAudioFrameCount = 8192

    #if DEBUG
    var testDroppedWritesCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return droppedWritesCount
    }

    var testPoolCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return bufferPool.count
    }

    func waitForPendingTestWrites() async {
        await withCheckedContinuation { continuation in
            fileWriterQueue.async { continuation.resume() }
        }
    }
    #endif

    init(
        generation: Int,
        request: SFSpeechAudioBufferRecognitionRequest,
        audioFile: AVAudioFile?,
        recordingFormat: AVAudioFormat? = nil,
        onRmsLevel: @escaping @Sendable (Float, Int) -> Void
    ) {
        self.generation = generation
        self.request = request
        self.audioFile = audioFile
        self.onRmsLevel = onRmsLevel

        if audioFile != nil, let format = recordingFormat {
            for _ in 0..<maxPoolCapacity {
                if let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: poolBufferCapacity) {
                    self.bufferPool.append(buf)
                }
            }
        }
    }

    func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        bufferPool.removeAll()
        lock.unlock()
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }

        // 1. 写入识别请求（Apple 官方设计支持在 tap 回调中实时追加）
        request.append(buffer)

        // 2. 预分配池化复制并异步将音频写入文件（在实时音频线程中零堆分配，不执行磁盘 I/O）
        var pooledBuffer: AVAudioPCMBuffer? = nil
        if audioFile != nil {
            if let freeBuf = bufferPool.popLast() {
                let inputFrames = buffer.frameLength
                let inputCapacity = buffer.frameCapacity
                let poolCapacity = freeBuf.frameCapacity
                let srcChannels = Int(buffer.format.channelCount)
                let dstChannels = Int(freeBuf.format.channelCount)
                let isFormatCompatible = buffer.format.commonFormat == .pcmFormatFloat32 &&
                                         freeBuf.format.commonFormat == .pcmFormatFloat32 &&
                                         !buffer.format.isInterleaved &&
                                         !freeBuf.format.isInterleaved &&
                                         buffer.format.sampleRate == freeBuf.format.sampleRate &&
                                         srcChannels == dstChannels &&
                                         srcChannels > 0

                // Strict invariant check: input length must be positive, within input capacity,
                // and within destination pool buffer capacity, with matching Float32 non-interleaved format
                if isFormatCompatible &&
                   inputFrames > 0 &&
                   inputFrames <= inputCapacity &&
                   inputFrames <= poolCapacity,
                   let srcChannelData = buffer.floatChannelData,
                   let dstChannelData = freeBuf.floatChannelData {

                    freeBuf.frameLength = inputFrames
                    let bytesPerChannel = Int(inputFrames) * MemoryLayout<Float>.size
                    for ch in 0..<srcChannels {
                        memcpy(dstChannelData[ch], srcChannelData[ch], bytesPerChannel)
                    }
                    pooledBuffer = freeBuf
                } else {
                    // Oversized or incompatible buffer: DO NOT crash or invoke setFrameLength beyond capacity.
                    // Return freeBuf to pool to prevent buffer leakage, and track bounded drop count.
                    bufferPool.append(freeBuf)
                    droppedWritesCount += 1

                    let now = DispatchTime.now().uptimeNanoseconds
                    if now - lastDropLogNanoseconds >= 1_000_000_000 { // at most 1Hz bounded log
                        lastDropLogNanoseconds = now
                        // Privacy-safe bounded log with zero audio/PCM content
                        print("[AudioTapSink] Dropped file write frame: length=\(inputFrames), inCapacity=\(inputCapacity), poolCapacity=\(poolCapacity), channels=\(srcChannels), format=\(buffer.format.commonFormat.rawValue), drops=\(droppedWritesCount)")
                    }
                }
            } else {
                droppedWritesCount += 1
            }
        }

        // 3. 限频派发检查（在锁内同步时间戳，消除多线程数据竞争）
        let now = DispatchTime.now().uptimeNanoseconds
        var shouldDispatchRms = false
        if now - lastRmsDispatchTime >= 50_000_000 { // 50ms = 20Hz
            lastRmsDispatchTime = now
            shouldDispatchRms = true
        }
        lock.unlock()

        // 异步写入文件
        if let audioFile, let writeBuf = pooledBuffer {
            fileWriterQueue.async { [weak self, audioFile, writeBuf] in
                try? audioFile.write(from: writeBuf)
                self?.returnBufferToPool(writeBuf)
            }
        }

        guard shouldDispatchRms else { return }

        // 4. 计算 RMS 振幅（严格 Float32 格式与通道数据校验，Zero-allocation）
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = buffer.floatChannelData else {
            return
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        var sumOfSquares: Float = 0.0
        let ptr = channelData[0]
        for index in 0..<frameCount {
            let sample = ptr[index]
            if !sample.isNaN && !sample.isInfinite {
                sumOfSquares += sample * sample
            }
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))
        if !rms.isNaN && !rms.isInfinite {
            onRmsLevel(rms, generation)
        }
    }

    private func returnBufferToPool(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if bufferPool.count < maxPoolCapacity && !isClosed {
            bufferPool.append(buffer)
        }
        lock.unlock()
    }
}
