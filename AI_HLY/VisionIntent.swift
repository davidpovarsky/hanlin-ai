//
//  VisionIntent.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 13/2/25.
//

import AppIntents
import SwiftUI


struct OpenVisionIntent: AppIntent {
    static var openAppWhenRun: Bool = true
    static var title: LocalizedStringResource = "启动视觉"
    static var description = IntentDescription(LocalizedStringResource("打开应用的视觉页面"))
    static var supportsWidget: Bool = true
    static var supportsForegroundExecution: Bool = true
    static var suggestedInvocationPhrase: String? = "启动视觉"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        
        if let url = URL(string: "AI-Hanlin://openVisionView") { // 自定义 URL Scheme
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        return .result()
    }
}
