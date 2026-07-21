//
//  VisionIntent.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 13/2/25.
//

import AppIntents
import SwiftUI


struct OpenVisionIntent: AppIntent {
    static let openAppWhenRun: Bool = true
    static let title: LocalizedStringResource = "启动视觉"
    static let description = IntentDescription(LocalizedStringResource("打开应用的视觉页面"))
    static let supportsWidget: Bool = true
    static let supportsForegroundExecution: Bool = true
    static let suggestedInvocationPhrase: String? = "启动视觉"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        
        if let url = URL(string: "AI-Hanlin://openVisionView") { // 自定义 URL Scheme
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        return .result()
    }
}
