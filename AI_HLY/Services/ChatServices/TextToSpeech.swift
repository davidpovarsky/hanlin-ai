//
//  TextToSpeech.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 8/2/25.
//

// TextToSpeech.swift
import Foundation
import AVFoundation
import SwiftData  // 确保引入 SwiftData

class TextToSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    @Published var isAsking = false
    private var selectedModel: String = "Siri" // 默认值
    private var messageId: UUID?
    private var context: ModelContext?

    // 用于 API 播放的 AVAudioPlayer
    private var audioPlayer: AVAudioPlayer?
    
    init(context: ModelContext? = nil) {
        self.context = context
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    // 更新消息ID
    func setMessageId(_ id: UUID) {
        self.messageId = id
    }
    
    // 更新 context
    func setContextIfNeeded(_ context: ModelContext) {
        self.context = context
    }
    
    // 更新 selectedModel
    func updateSelectedModel() {
        let fetchDescriptor = FetchDescriptor<UserInfo>()
        do {
            let results = try context!.fetch(fetchDescriptor)
            if let userInfo = results.first {
                // 这里假设 textToSpeechModel 可能为空，做个安全解包
                self.selectedModel = userInfo.textToSpeechModel
            }
        } catch {
            print("查询 UserInfo 失败：\(error.localizedDescription)")
        }
    }
    
    func toggleSpeech(text: String) {
        if selectedModel.lowercased() == "siri" {
            // Siri 模式：使用 AVSpeechSynthesizer 内建的暂停/继续功能
            if synthesizer.isSpeaking {
                if synthesizer.isPaused {
                    synthesizer.continueSpeaking()
                } else {
                    synthesizer.pauseSpeaking(at: .immediate)
                }
            } else {
                speakSiri(text: text)
            }
        } else {
            // API 模式（如 "4o-mini-tts"）：使用 AVAudioPlayer 播放返回的音频
            if let player = audioPlayer {
                if player.isPlaying {
                    // 如果正在播放，则暂停
                    player.pause()
                    DispatchQueue.main.async { self.isSpeaking = false }
                } else {
                    // 如果已开始但暂停，则恢复播放；否则重新发起 API 请求播放音频
                    if player.currentTime > 0 && player.currentTime < player.duration {
                        player.play()
                        DispatchQueue.main.async { self.isSpeaking = true }
                    } else {
                        speakAPISpeech(text: text, selectedModel: selectedModel)
                    }
                }
            } else {
                // audioPlayer 为空，直接发起播放请求
                speakAPISpeech(text: text, selectedModel: selectedModel)
            }
        }
    }
    
    private func speakSiri(text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        DispatchQueue.main.async { self.isSpeaking = true }
        
        let utterance = AVSpeechUtterance(string: text)
        
        // 动态选择语音：根据系统语言选择中文/英文语音
        let languageCode = Locale.preferredLanguages.first ?? "zh-CN"
        
        if languageCode.hasPrefix("zh-Hant") {
            // 中文繁体
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        } else if languageCode.hasPrefix("zh") {
            // 中文简体，优先使用 siri 男声（若可用）
            utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.siri_male_zh-CN_premium")
                ?? AVSpeechSynthesisVoice(language: "zh-CN")
        } else if languageCode.hasPrefix("en") {
            // 英文（美国）
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        } else {
            // 默认使用系统语言（若以上都不匹配）
            utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        }

        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.1
        utterance.volume = 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        synthesizer.speak(utterance)
    }
    
    private func getAPIKey(for company: String) -> String? {
        let predicate = #Predicate<APIKeys> { $0.company == company }
        let fetchDescriptor = FetchDescriptor<APIKeys>(predicate: predicate)
        return (try? context!.fetch(fetchDescriptor).first)?.resolvedKey
    }
    
    private func speakAPISpeech(text: String, selectedModel: String) {
        
        DispatchQueue.main.async { self.isAsking = true }
        
        // 1. 尝试从本地缓存读取音频
        if let id = messageId, let ctx = context {
            let desc = FetchDescriptor<ChatMessages>(
                predicate: #Predicate<ChatMessages> { $0.id == id }
            )
            if let record = try? ctx.fetch(desc).first,
               let assets = record.audioAssets,
               let asset = assets.first(where: { $0.modelName == selectedModel }) {
                // 命中缓存，直接播放
                DispatchQueue.main.async {
                    self.isAsking = false
                    self.isSpeaking = true
                }
                print("即将播放现存的\(selectedModel)音频")
                do {
                    let player = try AVAudioPlayer(data: asset.data)
                    self.audioPlayer = player
                    self.audioPlayer?.delegate = self
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                } catch {
                    print("播放缓存音频失败：\(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.isSpeaking = false
                    }
                }
                return
            }
        }
        
        print("请求新的\(selectedModel)音频")
        
        let ttsModels = getTTSModelList()
        guard let selected = ttsModels.first(where: { $0.name == selectedModel }) else {
            print("未找到匹配的语音模型")
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }
        
        guard let apiKey = getAPIKey(for: selected.company) else {
            print("缺少 \(selected.company) 的 API Key")
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }
        
        guard let url = URL(string: selected.requestURL) else {
            print("无效的 URL")
            DispatchQueue.main.async { self.isSpeaking = false }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var jsonBody: [String: Any] = [:]
        
        switch selected.company.uppercased() {
        case "OPENAI":
            jsonBody = [
                "model": selectedModel,
                "input": text,
                "voice": "coral",
                "instructions": "Speak in a cheerful and positive tone."
            ]
        case "SILICONCLOUD":
            jsonBody = [
                "model": selectedModel,
                "input": "Speak in a cheerful and positive tone.<|endofprompt|>\(text)",
                "voice": "\(selectedModel):anna",
                "stream": false,
            ]
        case "QWEN":
            jsonBody = [
                "model": selectedModel,
                "input": [
                    "text": text,
                    "voice": "Chelsie"
                ]
            ]
        default:
            print("暂不支持该语音服务厂商：\(selected.company)")
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isAsking = false
            }
            return
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        } catch {
            print("JSON 序列化失败：\(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isSpeaking = false
                self.isAsking = false
            }
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    print("语音合成请求失败：\(error.localizedDescription)")
                    self.isSpeaking = false
                    self.isAsking = false
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    print("语音数据为空")
                    self.isSpeaking = false
                    self.isAsking = false
                }
                return
            }
            
            // 解析返回
            do {
                if selected.company.uppercased() == "QWEN" {
                    try self.handleQwenAudioResponse(data)
                } else {
                    // 其他厂商直接播放返回的音频数据
                    DispatchQueue.main.async {
                        self.isSpeaking = true
                        self.isAsking = false
                    }
                    // 生成唯一文件名
                    let fileName = "\(selectedModel)_\(UUID().uuidString).m4a"
                    let player = try AVAudioPlayer(data: data)
                            let duration = player.duration
                    // 保存到 SwiftData
                    self.saveAudioAsset(
                        data,
                        fileName: fileName,
                        fileType: "m4a",
                        modelName: selectedModel,
                        duration: duration
                    )
                    // 播放
                    self.audioPlayer = try AVAudioPlayer(data: data)
                    self.audioPlayer?.delegate = self
                    self.audioPlayer?.prepareToPlay()
                    self.audioPlayer?.play()
                }
            } catch {
                DispatchQueue.main.async {
                    print("播放失败：\(error.localizedDescription)")
                    self.isSpeaking = false
                    self.isAsking = false
                }
            }
        }
        
        task.resume()
    }
    
    // 将新生成的音频保存到对应的 ChatMessages
    private func saveAudioAsset(_ data: Data, fileName: String, fileType: String, modelName: String, duration: TimeInterval?) {
        guard let id = messageId, let ctx = context else { return }
        let desc = FetchDescriptor<ChatMessages>(predicate: #Predicate<ChatMessages> { $0.id == id })
        do {
            if let record = try ctx.fetch(desc).first {
                var assets = record.audioAssets ?? []
                let asset = AudioAsset(
                    data: data,
                    fileName: fileName,
                    fileType: fileType,
                    modelName: modelName,
                    duration: duration
                )
                assets.append(asset)
                record.audioAssets = assets
                print("\(modelName)的音频保存成功")
            }
        } catch {
            print("保存音频失败：\(error.localizedDescription)")
        }
    }
    
    /// 解析 QWEN 的 JSON 响应，下载音频、缓存并播放
    private func handleQwenAudioResponse(_ data: Data) throws {
        // 1. 解析 JSON，提取 audio.url
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let output = json?["output"] as? [String: Any],
              let audio = output["audio"] as? [String: Any],
              var urlString = audio["url"] as? String
        else {
            throw NSError(domain: "解析失败，缺少 output 或 audio 或 url", code: -1)
        }
        // 确保使用 https
        if urlString.hasPrefix("http://") {
            urlString = urlString.replacingOccurrences(of: "http://", with: "https://")
        }
        guard let audioURL = URL(string: urlString) else {
            throw NSError(domain: "无效的音频链接", code: -1)
        }
        
        // 2. 下载、缓存并播放
        let downloadTask = URLSession.shared.dataTask(with: audioURL) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    print("音频下载失败：\(error.localizedDescription)")
                    self.isAsking = false
                    self.isSpeaking = false
                }
                return
            }
            guard let audioData = data else {
                DispatchQueue.main.async {
                    print("音频文件为空")
                    self.isAsking = false
                    self.isSpeaking = false
                }
                return
            }
            
            var duration: TimeInterval? = nil
            do {
                let tmpPlayer = try AVAudioPlayer(data: audioData)
                duration = tmpPlayer.duration
            } catch {
                print("无法读取音频时长：\(error)")
            }
            
            // 更新 UI 状态
            DispatchQueue.main.async {
                self.isAsking = false
                self.isSpeaking = true
            }
            
            // 缓存：生成唯一文件名并保存
            let fileName = "QWEN_\(UUID().uuidString).m4a"
            self.saveAudioAsset(
                audioData,
                fileName: fileName,
                fileType: "m4a",
                modelName: "Qwen-TTS",
                duration: duration
            )
            
            // 播放
            do {
                let player = try AVAudioPlayer(data: audioData)
                self.audioPlayer = player
                self.audioPlayer?.delegate = self
                self.audioPlayer?.prepareToPlay()
                self.audioPlayer?.play()
            } catch {
                DispatchQueue.main.async {
                    print("播放失败：\(error.localizedDescription)")
                    self.isSpeaking = false
                }
            }
        }
        downloadTask.resume()
    }
    
    func stopSpeech() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    
    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.interruptSpokenAudioAndMixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// 扩展使 TextToSpeech 遵循 AVAudioPlayerDelegate
extension TextToSpeech: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.isSpeaking = false }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
