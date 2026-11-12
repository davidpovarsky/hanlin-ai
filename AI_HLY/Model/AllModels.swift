//
//  AllModels.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 10/2/25.
//

import Foundation
import SwiftData

@Model
class AllModels {
    var catalogMetadataJSON: String? = nil
    var id = UUID()
    var name: String?
    var displayName: String?
    var identity: String? = "model"
    var position: Int?
    var company: String?
    var price: Int16 = 0
    var isHidden: Bool = false
    var supportsSearch: Bool = false
    var supportsTextGen: Bool = true
    var supportsMultimodal: Bool = false
    var supportsReasoning: Bool = false
    var supportReasoningChange: Bool = false
    var supportsImageGen: Bool = false
    var supportsVoiceGen: Bool = false
    var supportsToolUse: Bool = false
    var systemProvision: Bool = true
    var icon: String? = ""
    var briefDescription: String? = ""
    var characterDesign: String? = ""
    var relatedKnowledge: String? = ""
    
    // 初始化方法
    public init(
        id: UUID = UUID(),
        name: String?,
        displayName: String?,
        identity: String? = "model",
        position: Int?,
        company: String?,
        price: Int16 = 0,
        isHidden: Bool = false,
        supportsSearch: Bool = false,
        supportsTextGen: Bool = true,
        supportsMultimodal: Bool = false,
        supportsReasoning: Bool = false,
        supportReasoningChange: Bool = false,
        supportsImageGen: Bool = false,
        supportsVoiceGen: Bool = false,
        supportsToolUse: Bool = false,
        systemProvision: Bool = true,
        icon: String? = "",
        briefDescription: String? = "",
        characterDesign: String? = "",
        relatedKnowledge: String? = ""
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.position = position
        self.company = company
        self.price = price
        self.isHidden = isHidden
        self.supportsSearch = supportsSearch
        self.supportsTextGen = supportsTextGen
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.supportsImageGen = supportsImageGen
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsToolUse = supportsToolUse
        self.systemProvision = systemProvision
        self.icon = icon
        self.briefDescription = briefDescription
        self.characterDesign = characterDesign
        self.relatedKnowledge = relatedKnowledge
    }
}

extension AllModels {
    var catalogMetadata: ProviderModelCatalogMetadata? {
        guard let data = catalogMetadataJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProviderModelCatalogMetadata.self, from: data)
    }
    var catalogPriceTier: Int16 {
        guard company?.uppercased() == "OPENROUTER" else { return price }
        guard let metadata = catalogMetadata, metadata.isFresh else { return -1 }
        switch metadata.priceStatus { case .free: return 0; case .paid: return 4; case .unknown: return -1 }
    }
    var hasVerifiedImageOutput: Bool {
        guard company?.uppercased() == "OPENROUTER" else { return supportsImageGen }
        return supportsImageGen && (catalogMetadata.map { $0.isFresh && $0.hasImageOutput } ?? false)
    }
    var catalogPriceDescription: String? {
        guard company?.uppercased() == "OPENROUTER" else { return nil }
        guard let metadata = catalogMetadata, metadata.isFresh else { return String(localized: "Price unknown") }
        switch metadata.priceStatus {
        case .free: return String(localized: "Free")
        case .paid: return metadata.rateDescription
        case .unknown: return String(localized: "Price unknown")
        }
    }
}
