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
    static let title: LocalizedStringResource = "Open Hanlin Camera"
    static let description = IntentDescription("Opens Hanlin’s camera and visual analysis.")
    static let supportsWidget: Bool = true
    static let supportsForegroundExecution: Bool = true
    static let suggestedInvocationPhrase: String? = "Open Hanlin Camera"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        
        if let url = URL(string: "chavrusachat://openVisionView") { // 自定义 URL Scheme
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        return .result()
    }
}
