import Foundation
import SwiftData
import SwiftUI

// MARK: - 安全数组访问扩展
extension Collection {
    /// 安全下标访问，越界时返回 nil 而非崩溃
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension MutableCollection {
    /// 安全下标访问（可变集合），越界时返回 nil
    subscript(safe index: Index) -> Element? {
        get {
            return indices.contains(index) ? self[index] : nil
        }
        set {
            if indices.contains(index), let newValue = newValue {
                self[index] = newValue
            }
        }
    }
}

class AppDataManager: ObservableObject {
    let modelContainer: ModelContainer
    
    /// Canonical model identities stay in the AI_Hanlin module so existing stores migrate unchanged.
    static var modelTypes: [any PersistentModel.Type] {
        [ChatMessages.self, ChatSavedExcerpt.self, APIKeys.self, SearchKeys.self,
         AllModels.self, ChatRecords.self, UserInfo.self, PromptRepo.self,
         KnowledgeRecords.self, KnowledgeChunk.self, MemoryArchive.self,
         TranslationDic.self, ToolKeys.self]
    }

    static var schema: Schema { Schema(modelTypes) }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    convenience init() {
        do { self.init(modelContainer: try Self.makeDefaultModelContainer()) }
        catch { fatalError("无法初始化 ModelContainer: \(error)") }
    }

    /// Retains Hanlin's original CloudKit and isolated native-test storage policy.
    static func makeDefaultModelContainer() throws -> ModelContainer {
    let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["HANLIN_EXPO_E2E"] != nil
        || ProcessInfo.processInfo.environment["HANLIN_NATIVESCRIPT_E2E"] != nil
        || ProcessInfo.processInfo.environment["HANLIN_SCRIPTUI_E2E"] != nil
    let nativeAcceptance = HanlinNativeA2UIAcceptanceProvider.isEnabled
    let config: ModelConfiguration
    if let fixtureID = AgentRuntimeUIAcceptanceProvider.phase2StoreID {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Phase2Acceptance/" + fixtureID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        config = ModelConfiguration(url: root.appending(path: "Chat.store"), cloudKitDatabase: .none)
    } else {
        config = ModelConfiguration(isStoredInMemoryOnly: nativeAcceptance, cloudKitDatabase: (isTesting || nativeAcceptance) ? .none : .automatic)
    }
        return try ModelContainer(for: schema, configurations: [config])
    }

    // 异步预加载所有数据
    @MainActor func preloadDataIfNeeded() {
        let context = modelContainer.mainContext
        if HanlinNativeA2UIAcceptanceProvider.isEnabled {
            do { try HanlinNativeA2UIAcceptanceProvider.configureIfRequested(context: context) }
            catch { fatalError("Native A2UI isolated fixture bootstrap failed") }
            return
        }
        if AgentRuntimeUIAcceptanceProvider.phase2StoreID != nil {
            AgentRuntimeUIAcceptanceProvider.configureIfRequested(context: context)
            return
        }
        // 确保模型数据优先加载完成
        preloadModelDataIfNeeded(context: context)
        preloadAPIKeysIfNeeded(context: context)
        preloadSearchKeysIfNeeded(context: context)
        preloadToolKeysIfNeeded(context: context)
        preloadUserInfoIfNeeded(context: context)
        preloadPromptIfNeeded(context: context)
        clearOrphanData(context: context)
        AgentRuntimeUIAcceptanceProvider.configureIfRequested(context: context)
    }
}

