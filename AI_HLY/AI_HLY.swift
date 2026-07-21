//
//  App.swift
//  AI_HLY
//
//  Created by zhiyuan20002 on 3/2/25.
//

import SwiftUI
import SwiftData
import AppIntents

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
    
    init() {
        do {
            // 配置 CloudKit 数据库（.automatic 自动选择）
            let config = ModelConfiguration(isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            modelContainer = try ModelContainer(
                for: ChatMessages.self,
                APIKeys.self,
                SearchKeys.self,
                AllModels.self,
                ChatRecords.self,
                UserInfo.self,
                PromptRepo.self,
                KnowledgeRecords.self,
                KnowledgeChunk.self,
                MemoryArchive.self,
                TranslationDic.self,
                ToolKeys.self,
                configurations: config
            )
        } catch {
            fatalError("无法初始化 ModelContainer: \(error)")
        }
    }
    
    // 异步预加载所有数据
    @MainActor func preloadDataIfNeeded() {
        let context = modelContainer.mainContext
        // 确保模型数据优先加载完成
        preloadModelDataIfNeeded(context: context)
        preloadAPIKeysIfNeeded(context: context)
        preloadSearchKeysIfNeeded(context: context)
        preloadToolKeysIfNeeded(context: context)
        preloadUserInfoIfNeeded(context: context)
        preloadPromptIfNeeded(context: context)
        clearOrphanData(context: context)
    }
}

@main
struct MyApp: App {
    @MainActor @StateObject private var appDataManager = AppDataManager()
    @State private var deepLinkTarget: String? = nil
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            MainTabView(deepLinkTarget: $deepLinkTarget)
                .modelContainer(appDataManager.modelContainer)
                .task {
                    appDataManager.preloadDataIfNeeded()
                    await RuntimeLifecycleBridge.prepareApplication()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task { await RuntimeLifecycleBridge.handleScenePhase(newPhase) }
                }
                .onOpenURL { url in
                    if url.host == "openVisionView" {
                        deepLinkTarget = "vision"
                    }
                }
        }

        WindowGroup("Mini App", for: NativeAppLaunchRequest.self) { $request in
            if let request {
                NativeAppSessionContainerView(request: request)
                    .modelContainer(appDataManager.modelContainer)
            } else {
                ContentUnavailableView(
                    "No App Selected",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a mini app from Hanlin.")
                )
                .modelContainer(appDataManager.modelContainer)
            }
        }
    }
}

