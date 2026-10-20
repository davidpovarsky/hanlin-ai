//
//  AutomaticSearchMigration.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation
import SwiftData

/// Manages database bootstrap, migration, and default provider selection for Automatic Web Search.
public enum AutomaticSearchMigration {
    public static let automaticKeyName = "AUTOMATIC_SEARCH_KEY"
    public static let automaticCompany = "AUTOMATIC_KEYLESS"
    public static let automaticDefaultURL = "https://api.you.com/v1/agents/search"
    
    /// Creates the standard preloaded SearchKeys model for the automatic provider.
    public static func makeAutomaticSearchKey(isUsing: Bool = true) -> SearchKeys {
        return SearchKeys(
            name: automaticKeyName,
            company: automaticCompany,
            key: "",
            requestURL: automaticDefaultURL,
            price: 0.0,
            isUsing: isUsing,
            help: "https://you.com"
        )
    }
    
    /// Evaluates current SearchKeys state in the given model context and ensures:
    /// 1. Fresh install -> AUTOMATIC_KEYLESS is enabled and active by default.
    /// 2. Existing install with a valid explicitly chosen manual provider -> preserved untouched.
    /// 3. Existing install with no valid or enabled search provider -> migrated to AUTOMATIC_KEYLESS.
    @MainActor
    public static func reconcileDefaultProvider(in context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<SearchKeys>()
            let allKeys = try context.fetch(descriptor)
            
            // Check if user has an explicitly chosen, configured manual provider
            let hasValidManualProvider = allKeys.contains { key in
                guard key.company != automaticCompany else { return false }
                guard key.isUsing else { return false }
                return !(key.key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            
            if hasValidManualProvider {
                // User has an active manual provider: ensure automatic is inactive so only 1 provider is active
                for key in allKeys where key.company == automaticCompany {
                    if key.isUsing {
                        key.isUsing = false
                    }
                }
            } else {
                // No valid manual active provider: ensure AUTOMATIC_KEYLESS is active
                var foundAutomatic = false
                for key in allKeys {
                    if key.company == automaticCompany {
                        key.isUsing = true
                        foundAutomatic = true
                    } else {
                        key.isUsing = false
                    }
                }
                
                if !foundAutomatic {
                    let autoKey = makeAutomaticSearchKey(isUsing: true)
                    context.insert(autoKey)
                }
            }
            
            try context.save()
        } catch {
            print("AutomaticSearchMigration reconciliation error: \(error.localizedDescription)")
        }
    }
}
