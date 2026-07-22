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
                        // 开始录音
                        speechRecognizer.startRecording()
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
            speechRecognizer.requestAuthorization()
            speechRecognizer.startRecording()
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
    @Published var recognizedText: String = ""
    @Published var isRecording: Bool = false
    @Published var audioLevel: Float = 0.0
    // 新增：保存录音片段的文件 URL
    @Published var recordedAudioURL: URL? = nil

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // 用于写入录音数据
    private var audioFile: AVAudioFile?
    
    override init() {
        super.init()
        // 使用中文语音识别
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        speechRecognizer?.delegate = self
    }
    
    /// 请求语音识别及录音权限
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("语音识别授权成功")
                case .denied, .restricted, .notDetermined:
                    print("语音识别未被授权")
                @unknown default:
                    print("未知授权状态")
                }
            }
        }
        
        AVAudioApplication.requestRecordPermission { granted in
            if granted {
                print("麦克风授权成功")
            } else {
                print("麦克风未被授权")
            }
        }
    }
    
    /// 开始录音和语音识别
    func startRecording() {
        if isRecording { return }
        recognizedText = ""
        
        // 创建录音文件，存储到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording-\(UUID().uuidString).caf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordedAudioURL = fileURL
        
        // 定义录音文件设置（这里以 CAF 格式为例，可根据需求调整）
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, // 原始 PCM 数据
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        } catch {
            print("无法创建录音文件：\(error.localizedDescription)")
        }
        
        // 配置音频会话
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("设置音频会话失败：\(error.localizedDescription)")
        }
        
        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("无法创建 SFSpeechAudioBufferRecognitionRequest 对象")
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // 安装 tap 获取音频数据，并写入录音文件
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let activeRequest = recognitionRequest
        let activeAudioFile = audioFile
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            // 将音频数据写入识别请求
            activeRequest.append(buffer)
            
            // 同时写入录音文件
            do {
                try activeAudioFile?.write(from: buffer)
            } catch {
                print("写入录音文件失败：\(error.localizedDescription)")
            }
            
            // 更新音频级别（用于波形显示）
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
            let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
            Task { @MainActor [weak self] in
                self?.audioLevel = rms
            }
        }
        
        // 启动音频引擎
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("audioEngine 启动失败：\(error.localizedDescription)")
        }
        
        // 开始语音识别任务
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let recognizedText = result?.bestTranscription.formattedString
            let shouldStop = error != nil || (result?.isFinal ?? false)
            Task { @MainActor [weak self] in
                if let recognizedText { self?.recognizedText = recognizedText }
                if shouldStop { self?.stopRecording() }
            }
        }
    }
    
    /// 停止录音和语音识别
    func stopRecording() {
        if !isRecording { return }
        
        // 移除 tap 并停止引擎
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        // 结束请求和任务
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        isRecording = false
    }
}
