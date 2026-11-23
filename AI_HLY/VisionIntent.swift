//
//  VisionIntent.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 13/2/25.
//

import AppIntents
import HanlinLocalization
import SwiftUI


public struct OpenVisionIntent: AppIntent {
    public static let openAppWhenRun: Bool = true
    public static let title = LocalizedStringResource("Open Hanlin Camera", bundle: .atURL(HanlinLocalization.bundle.bundleURL))
    public static let description = IntentDescription(LocalizedStringResource("Opens Hanlin’s camera and visual analysis.", bundle: .atURL(HanlinLocalization.bundle.bundleURL)))
    public static let supportsWidget: Bool = true
    public static let supportsForegroundExecution: Bool = true
    public static let suggestedInvocationPhrase: String? = "Open Hanlin Camera"
    
    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        
        if let url = URL(string: "chavrusachat://openVisionView") { // 自定义 URL Scheme
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        
        return .result()
    }
}
