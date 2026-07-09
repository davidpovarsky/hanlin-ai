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

    init(
        name: String,
        title: String,
        summary: String,
        categories: [String] = [],
        keywords: [String] = [],
        examples: [String] = [],
        isSensitive: Bool = false
    ) {
        self.name = name
        self.title = title
        self.summary = summary
        self.categories = categories
        self.keywords = keywords
        self.examples = examples
        self.isSensitive = isSensitive
    }

    var compactCatalogText: String {
        ([name, title, summary] + categories + keywords + examples)
            .joined(separator: "\n")
            .lowercased()
    }
}

struct NativeToolSearchHit: Identifiable, Hashable {
    var id: String { entry.name }
    var entry: NativeToolCatalogEntry
    var score: Int
    var matchedTerms: [String]
}
