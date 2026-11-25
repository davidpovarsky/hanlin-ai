//
//  NativeToolCatalogEntry.swift
//  AI_HLY
//

import Foundation
import HanlinPlatformContracts

struct NativeToolCatalogEntry: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var title: String
    var summary: String
    var categories: [String]
    var keywords: [String]
    var examples: [String]
    var isSensitive: Bool
    var requiredCapabilities: [String]
    var approval: HanlinToolApprovalDescriptor?
    var systemImage: String
    var sourceAppID: String?
    var sourceAppTitle: String?
    var isEnabledByDefault: Bool
    var isVisibleInSettings: Bool
    var presentationProfile: ToolPresentationProfile
    var composerConfiguration: HanlinComposerConfiguration?

    init(
        name: String,
        title: String,
        summary: String,
        categories: [String] = [],
        keywords: [String] = [],
        examples: [String] = [],
        isSensitive: Bool = false,
        requiredCapabilities: [String] = [],
        approval: HanlinToolApprovalDescriptor? = nil,
        systemImage: String = "wrench.and.screwdriver",
        sourceAppID: String? = nil,
        sourceAppTitle: String? = nil,
        isEnabledByDefault: Bool = true,
        isVisibleInSettings: Bool = true,
        presentationProfile: ToolPresentationProfile,
        composerConfiguration: HanlinComposerConfiguration? = nil
    ) {
        self.name = name
        self.title = title
        self.summary = summary
        self.categories = categories
        self.keywords = keywords
        self.examples = examples
        self.isSensitive = isSensitive
        self.requiredCapabilities = requiredCapabilities
        self.approval = approval
        self.systemImage = systemImage
        self.sourceAppID = sourceAppID
        self.sourceAppTitle = sourceAppTitle
        self.isEnabledByDefault = isEnabledByDefault
        self.isVisibleInSettings = isVisibleInSettings
        self.presentationProfile = presentationProfile
        self.composerConfiguration = composerConfiguration
    }
}
