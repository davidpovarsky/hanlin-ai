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

            // 权限提示（若被拒绝或受限）
            if case .denied(let reason) = speechRecognizer.permissionStatus {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else if case .restricted = speechRecognizer.permissionStatus {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.secondary)
                    Text("语音识别已被系统限制使用")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                        message += speechRecognizer.recognizedText
                        if let url = speechRecognizer.recordedAudioURL {
                            // 执行高级处理，例如上传服务器、语音情感分析等
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

                Spacer()

                if speechRecognizer.isRecording {
                    // 使用新的柱状波形可视化
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
                }

                Spacer()

                if !speechRecognizer.isRecording {

                    Button(action: optimizeMessage) {
                        if isOptimizing {
                            ProgressView() // 显示加载指示器
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
                    .onChange(of: message) {
                        if optimized && (message != optimizedMessage) {
                            optimized = false
                        } else if message == optimizedMessage , !message.isEmpty {
                            optimized = true
                        }
                    }
                }

                // 插入
                Button(action: {
                    isFeedBack.toggle()
                    message = message
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
            speechRecognizer.requestPermissionsAndStartIfAuthorized()
        }
        .onDisappear {
            speechRecognizer.stopRecording()
        }
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
                isOptimizing = true // 开始优化
                original = message // 保留原句
                if !message.isEmpty {
                    do {
                        let optimizer = SystemOptimizer(context: modelContext)
                        optimizedMessage = try await optimizer.optimizePrompt(inputPrompt: message)
                        message = optimizedMessage
                        optimized = true
                    } catch {
                        errorMessage = error.localizedDescription // 捕获错误信息
                        showErrorAlert = true // 显示错误弹窗
                    }
                }
                isOptimizing = false // 优化结束
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

// MARK: - SpeechRecognizer 类
/// 使用 Apple Speech 框架实现语音识别，同时通过 AVAudioEngine 获取音频信号的 RMS 值用于波形可视化
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
    // 保存录音片段的文件 URL
    @Published var recordedAudioURL: URL? = nil
    @Published var permissionStatus: PermissionStatus = .notDetermined

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // 用于写入录音数据
    private var audioFile: AVAudioFile?

    // 跟踪 Tap 状态与世代，避免重复安装或跨世代回调污染
    private var tapInstalled: Bool = false
    private var currentGeneration: Int = 0
    private var audioSink: AudioTapSink?

    override init() {
        super.init()
        // 使用中文语音识别
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        speechRecognizer?.delegate = self

        // 监听音频中断（来电、Siri、后台切换）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .began {
            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
        }
    }

    /// 统一状态化权限检查并在授权后自动开启录音
    func requestPermissionsAndStartIfAuthorized() {
        guard permissionStatus != .requesting else { return }

        if permissionStatus == .authorized {
            startRecording()
            return
        }

        permissionStatus = .requesting

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        switch speechStatus {
        case .authorized:
            checkMicrophonePermission(autoStart: true)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .authorized {
                        self.checkMicrophonePermission(autoStart: true)
                    } else if status == .restricted {
                        self.permissionStatus = .restricted
                    } else {
                        self.permissionStatus = .denied("语音识别权限未开启，请在“设置”中允许使用语音识别")
                    }
                }
            }
        case .denied:
            permissionStatus = .denied("语音识别权限未开启，请在“设置”中允许使用语音识别")
        case .restricted:
            permissionStatus = .restricted
        @unknown default:
            permissionStatus = .denied("语音识别状态未知")
        }
    }

    private func checkMicrophonePermission(autoStart: Bool) {
        if #available(iOS 17.0, *) {
            let recordPermission = AVAudioApplication.shared.recordPermission
            switch recordPermission {
            case .granted:
                permissionStatus = .authorized
                if autoStart { startRecording() }
            case .undetermined:
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if granted {
                            self.permissionStatus = .authorized
                            if autoStart { self.startRecording() }
                        } else {
                            self.permissionStatus = .denied("麦克风权限未开启，请在“设置”中允许使用麦克风")
                        }
                    }
                }
            case .denied:
                permissionStatus = .denied("麦克风权限未开启，请在“设置”中允许使用麦克风")
            @unknown default:
                permissionStatus = .denied("麦克风状态未知")
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                permissionStatus = .authorized
                if autoStart { startRecording() }
            case .undetermined:
                session.requestRecordPermission { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if granted {
                            self.permissionStatus = .authorized
                            if autoStart { self.startRecording() }
                        } else {
                            self.permissionStatus = .denied("麦克风权限未开启，请在“设置”中允许使用麦克风")
                        }
                    }
                }
            case .denied:
                permissionStatus = .denied("麦克风权限未开启，请在“设置”中允许使用麦克风")
            @unknown default:
                permissionStatus = .denied("麦克风状态未知")
            }
        }
    }

    /// 开始录音和语音识别
    func startRecording() {
        if isRecording || tapInstalled { return }
        guard permissionStatus == .authorized else {
            requestPermissionsAndStartIfAuthorized()
            return
        }

        recognizedText = ""
        audioLevel = 0.0

        let generation = currentGeneration + 1
        currentGeneration = generation

        // 配置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("设置音频会话失败：\(error.localizedDescription)")
            stopRecording()
            return
        }

        // 检查输入节点格式
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("无效的输入音频格式: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
            stopRecording()
            return
        }

        // 创建录音文件，匹配输入格式
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).caf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordedAudioURL = fileURL

        var audioFile: AVAudioFile? = nil
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
        } catch {
            print("无法创建录音文件：\(error.localizedDescription)")
            audioFile = nil
        }
        self.audioFile = audioFile

        // 创建识别请求
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest = recognitionRequest
        recognitionRequest.shouldReportPartialResults = true

        // 构造音频回调 Sink（线程安全、@Sendable、限频 UI 派发）
        let sink = AudioTapSink(
            generation: generation,
            request: recognitionRequest,
            audioFile: audioFile
        ) { [weak self] (rms: Float, gen: Int) in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, self.currentGeneration == gen else { return }
                self.audioLevel = rms
            }
        }
        self.audioSink = sink

        // AVAudioEngine 的 tap 回调运行在其私有实时音频队列，不运行在 MainActor。
        // 使用 @Sendable 闭包避免 Swift 6 继承 MainActor 导致运行时 SIGTRAP 断言崩溃。
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { @Sendable buffer, _ in
            sink.processBuffer(buffer)
        }
        tapInstalled = true

        // 启动音频引擎
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("audioEngine 启动失败：\(error.localizedDescription)")
            stopRecording()
            return
        }

        // 开始语音识别任务
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
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
    }

    /// 停止录音和语音识别（幂等安全）
    func stopRecording() {
        if !isRecording && !tapInstalled && recognitionTask == nil { return }

        // 递增世代，废弃旧异步回调
        currentGeneration += 1

        // 关闭 Sink，停止写入音频数据
        audioSink?.close()
        audioSink = nil

        // 移除 tap 并停止引擎
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // 结束请求和任务
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        audioFile = nil

        isRecording = false
        audioLevel = 0.0

        // 释放音频会话，消除状态栏麦克风指示器
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Non-fatal
        }
    }
}

// MARK: - AudioTapSink (Swift 6 实时音频回调安全隔离)
/// 专用于桥接 AVAudioEngine 实时音频回调与 SFSpeechAudioBufferRecognitionRequest 的线程安全接收器。
/// 关键并发保证：
/// 1. AVFoundation 在内部专用音频线程串行调用 tap 回调。
/// 2. mutable 状态（isClosed, audioFile, request）由锁保护。
/// 3. RMS 计算为无锁、无堆分配（Zero-allocation）。
/// 4. UI 派发限制在 ~20Hz（50ms），防止音频线程产生大量并发 Task 饱和 MainActor。
/// 5. close() 调用后，所有后续音频数据立即丢弃。
private final class AudioTapSink: @unchecked Sendable {
    private let generation: Int
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let audioFile: AVAudioFile?
    private let onRmsLevel: @Sendable (Float, Int) -> Void

    private let lock = NSLock()
    private var isClosed = false
    private var lastRmsDispatchTime: UInt64 = 0

    init(
        generation: Int,
        request: SFSpeechAudioBufferRecognitionRequest,
        audioFile: AVAudioFile?,
        onRmsLevel: @escaping @Sendable (Float, Int) -> Void
    ) {
        self.generation = generation
        self.request = request
        self.audioFile = audioFile
        self.onRmsLevel = onRmsLevel
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }

        // 1. 将音频数据写入识别请求
        request.append(buffer)

        // 2. 写入录音文件（忽略单帧写入异常，避免阻塞音频线程）
        if let audioFile {
            do {
                try audioFile.write(from: buffer)
            } catch {
                // 忽略非致命写入错误
            }
        }
        lock.unlock()

        // 3. 计算 RMS 振幅（直接指针遍历，无数组拷贝与堆分配）
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData?[0] else { return }

        var sumOfSquares: Float = 0.0
        for index in 0..<frameCount {
            let sample = channelData[index]
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(frameCount))

        // 4. 限频派发 UI 波形电平（至多 20Hz / 50ms 一次）
        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastRmsDispatchTime >= 50_000_000 {
            lastRmsDispatchTime = now
            onRmsLevel(rms, generation)
        }
    }
}
