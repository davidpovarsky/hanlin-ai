//
//  NativeToolCatalogEntry.swift
//  AI_HLY
//

import Foundation

struct NativeToolCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var title: String
    var summary: String
    var categories: [String]
    var keywords: [String]
    var examples: [String]
    var isSensitive: Bool
    var systemImage: String
    var sourceAppID: String?
    var sourceAppTitle: String?
    var isEnabledByDefault: Bool
    var isVisibleInSettings: Bool
    var presentationProfile: ToolPresentationProfile

    init(
        name: String,
        title: String,
        summary: String,
        categories: [String] = [],
        keywords: [String] = [],
        examples: [String] = [],
        isSensitive: Bool = false,
        systemImage: String = "wrench.and.screwdriver",
        sourceAppID: String? = nil,
        sourceAppTitle: String? = nil,
        isEnabledByDefault: Bool = true,
        isVisibleInSettings: Bool = true,
        presentationProfile: ToolPresentationProfile
    ) {
        self.name = name
        self.title = title
        self.summary = summary
        self.categories = categories
        self.keywords = keywords
        self.examples = examples
        self.isSensitive = isSensitive
        self.systemImage = systemImage
        self.sourceAppID = sourceAppID
        self.sourceAppTitle = sourceAppTitle
        self.isEnabledByDefault = isEnabledByDefault
        self.isVisibleInSettings = isVisibleInSettings
        self.presentationProfile = presentationProfile
    }
}
