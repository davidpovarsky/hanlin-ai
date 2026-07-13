//
//  NativeUIBlock.swift
//  AI_HLY
//
//  A small, Codable, provider-neutral native UI schema for chat tool results.
//  Keep this schema intentionally narrow. Tools may return these blocks; SwiftUI renders them natively.
//

import Foundation

enum NativeUIBlockType: String, Codable, Hashable {
    case text
    case markdown
    case card
    case searchResults
    case source
    case wikipediaSummary
    case calculation
    case keyValueList
    case error
    case activityTimeline
}

enum NativeUIActivityStatus: String, Codable, Hashable {
    case