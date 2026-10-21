//
//  AutomaticSearchMigration.swift
//  AI_HLY
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation
import SwiftData

/// Manages database bootstrap, migration, and default provider selection for Automatic Web Search.
enum AutomaticSearchMigration {
    static let automaticKeyName = "AUTOMATIC_SEARCH_KEY"
    static let automaticCompany = "AUTOMATIC_KEYLESS"
    static let automaticDefaultURL = "https://api.you.com/v1/agents/search"
    
    /// Creates the standard preloaded SearchKeys model for the automatic provider.
    static func makeAutomaticSearchKey(isUsing: Bool = false) -> SearchKeys {
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
    /// 1. Fresh / unconfigured install -> AUTOMATIC_KEYLESS is enabled and active by default.
    /// 2. Existing install with a valid explicitly chosen manual provider -> preserved untouched.
    /// 3. Explicit manual disable (user configured a key but turned it off) -> preserved as inactive.
    /// 4. Invariant: At most one provider is active at any time.
    static func reconcileDefaultProvider(in context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<SearchKeys>()
            let allKeys = try context.fetch(descriptor)
            
            // Deduplicate if multiple automatic keys exist
            let automaticKeys = allKeys.filter { $0.company == automaticCompany }
            let anyAutomaticUsing = automaticKeys.contains { $0.isUsing }
            if automaticKeys.count > 1 {
                for duplicate in automaticKeys.dropFirst() {
                    context.delete(duplicate)
                }
            }
            
            let effectiveAutomatic = automaticKeys.first
            if anyAutomaticUsing {
                effectiveAutomatic?.isUsing = true
            }
            let manualKeys = allKeys.filter { $0.company != automaticCompany }
            
            // Check manual providers
            let activeManual = manualKeys.first { key in
                key.isUsing && !(key.key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            
            let hasConfiguredManualKeys = manualKeys.contains { key in
                !(key.key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            }
            
            if let activeManual = activeManual {
                // User has an explicitly active configured manual provider -> keep it, ensure automatic is off
                if let auto = effectiveAutomatic, auto.isUsing {
                    auto.isUsing = false
                }
                // Enforce single active provider
                for other in manualKeys where other.id != activeManual.id && other.isUsing {
                    other.isUsing = false
                }
            } else if hasConfiguredManualKeys {
                // User has configured manual keys, but NONE are active: user explicitly turned providers off!
                // Do NOT force-enable automatic behind the user's back.
                if let auto = effectiveAutomatic {
                    if auto.isUsing {
                        auto.isUsing = false
                    }
                } else {
                    let auto = makeAutomaticSearchKey(isUsing: false)
                    context.insert(auto)
                }
            } else {
                // No manual keys are configured at all (Fresh install or clean legacy install).
                // Ensure AUTOMATIC_KEYLESS is active as the default out-of-the-box provider.
                if let auto = effectiveAutomatic {
                    if !auto.isUsing && !allKeys.contains(where: { $0.isUsing }) {
                        auto.isUsing = true
                    }
                } else {
                    let auto = makeAutomaticSearchKey(isUsing: true)
                    context.insert(auto)
                }
            }
            
            try context.save()
        } catch {
            print("AutomaticSearchMigration reconciliation error: \(error.localizedDescription)")
        }
    }
}
