//
//  AgentActivityPersistence.swift
//  AI_HLY
//

import Foundation

extension ChatMessages {
    var agentRun: AgentRun? {
        get {
            guard let agentRunJSON, let data = agentRunJSON.data(using: .utf8) else { return nil }
            guard let run = try? JSONDecoder().decode(AgentRun.self, from: data),
                  run.schemaVersion > 0,
                  run.schemaVersion <= AgentRun.currentSchemaVersion else { return nil }
            return run
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                agentRunJSON = nil
                return
            }
            agentRunJSON = json
        }
    }
}
