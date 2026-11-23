//
//  PreLoad.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 9/2/25.
//

import SwiftData
import Foundation

// MARK: - 模型数据预加载
@MainActor
func preloadModelDataIfNeeded(context: ModelContext) {
    var checkpointEstablished = false
    do {
        if context.hasChanges { try context.save() }
        checkpointEstablished = true
        let fetchDescriptor = FetchDescriptor<AllModels>()
        let existingData = try context.fetch(fetchDescriptor)

        // Model UUIDs, not equal routing/display names, identify stored rows.
        // Preserve custom and ambiguous legacy rows instead of selecting one by
        // fetch order. Only an unambiguous catalog-owned row may be refreshed.
        var validModelsMap: [String: [AllModels]] = [:]
        var modelsToDelete: [AllModels] = []
        for model in existingData {
            if HanlinAppleModelCatalogAdapter.isNative(model) { continue }
            if let name = model.name, !name.isEmpty {
                validModelsMap[name, default: []].append(model)
            } else if model.systemProvision {
                modelsToDelete.append(model)
            }
        }
        
        // 更新或插入预定义模型数据
        let predefinedModels = getModelList()  // 预定义模型列表
        for model in predefinedModels {
            if let name = model.name, let matches = validModelsMap[name] {
                guard matches.count == 1, let existingModel = matches.first else { continue }
                // 若记录已存在，则更新（系统预置的才更新部分字段）
                if existingModel.systemProvision {
//                    existingModel.displayName = model.displayName
                    existingModel.identity = model.identity
                    if model.identity == "agent" {
                        existingModel.displayName = model.displayName
                        existingModel.characterDesign = model.characterDesign
                        existingModel.icon = model.icon
                        existingModel.briefDescription = model.briefDescription
                    }
                    existingModel.price = model.price
                    existingModel.company = model.company
                    existingModel.supportsSearch = model.supportsSearch
                    existingModel.supportsTextGen = model.supportsTextGen
                    existingModel.supportsMultimodal = model.supportsMultimodal
                    existingModel.supportsReasoning = model.supportsReasoning
                    existingModel.supportReasoningChange = model.supportReasoningChange
                    existingModel.supportsImageGen = model.supportsImageGen
                    existingModel.supportsVoiceGen = model.supportsVoiceGen
                    existingModel.supportsToolUse = model.supportsToolUse
                }
            } else {
                // 插入记录
                context.insert(model)
                print("新增系统模型：\(model.name ?? "Unknown")")
            }
        }
        
        // 增加逻辑：确保所有本地模型的 systemProvision 设为 false
        for model in existingData {
            if model.company == "LOCAL" {
                model.systemProvision = false
                print("更新本地模型 systemProvision: \(model.name ?? "Unknown") -> false")
            }
        }
        
        // 删除数据库中多余的系统预置模型：
        // 如果记录是系统预置（systemProvision 为 true），
        // 且名称不在预定义列表中，且 company 不为 "LOCAL"，则删除
        let predefinedModelNames = Set(predefinedModels.map { $0.name })
        for model in existingData {
            if model.systemProvision,
               let name = model.name,
               validModelsMap[name]?.count == 1,
               !predefinedModelNames.contains(name),
               model.company != "LOCAL" {
                context.delete(model)
                print("删除冗余系统模型：\(name)")
            }
        }
        
        // 仅删除前面标记的无效系统数据
        for model in modelsToDelete {
            context.delete(model)
            print("删除无效系统模型：\(model.name ?? "Unknown")")
        }
        
        try context.save()
        try HanlinAppleModelCatalogAdapter.register(in: context)
        print("模型数据同步完成")
        
    } catch {
        if checkpointEstablished { context.rollback() }
        print("读取/更新/插入模型数据失败")
    }
}

// MARK: - APIKeys 预加载（以稳定的 company 标识同步预定义数据）
@MainActor
func preloadAPIKeysIfNeeded(context: ModelContext) {
    var checkpointEstablished = false
    do {
        // A failed catalog save must not leave partial mutations for a later host
        // save, or roll back host edits that preceded this refresh.
        if context.hasChanges { try context.save() }
        checkpointEstablished = true
        let existingData = try context.fetch(FetchDescriptor<APIKeys>())
        let byCompany = Dictionary(grouping: existingData.compactMap { key -> (String, APIKeys)? in
            guard let company = key.company, !company.isEmpty else { return nil }
            return (company, key)
        }, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        let predefinedAPIKeys = getKeyList()
        let predefinedCompanies = Set(predefinedAPIKeys.compactMap(\.company))

        for predefinedKey in predefinedAPIKeys {
            guard let company = predefinedKey.company, !company.isEmpty else { continue }
            guard let existing = byCompany[company] else {
                context.insert(predefinedKey)
                continue
            }
            // Display names are editable and need not be unique. Never choose or
            // delete a credential-bearing row to resolve an ambiguous legacy
            // routing identity; the normal duplicate-provider guard stays visible.
            guard existing.count == 1, let key = existing.first, key.from == .system else { continue }
            let routingCompany = company.uppercased()
            guard routingCompany != "LAN", routingCompany != "LOCAL" else { continue }
            // Only catalog-owned metadata follows a built-in update. The original
            // row, routing identity, name, credential, visibility and probe choice
            // remain intact. Explicit host request overrides are custom-owned.
            if let newURL = predefinedKey.requestURL, !newURL.isEmpty {
                key.requestURL = newURL
            }
            key.help = predefinedKey.help
            key.apiType = predefinedKey.apiType
        }

        // Retire only an unambiguous, unused catalog definition. Retain custom
        // rows, malformed legacy identities and every stored credential/reference;
        // refreshing a catalog is never a credential migration or erasure request.
        for (company, rows) in byCompany {
            guard rows.count == 1, let key = rows.first, key.from == .system,
                  !predefinedCompanies.contains(company),
                  company.uppercased() != "LAN", company.uppercased() != "LOCAL",
                  (key.key ?? "").isEmpty else { continue }
            context.delete(key)
        }
        try context.save()
        print("API 密钥同步完成")
    } catch {
        if checkpointEstablished { context.rollback() }
        // SwiftData errors may contain original row values. Do not print secrets.
        print("API 密钥同步失败")
    }
}

// MARK: - SearchKeys 预加载（去重时保留最新数据，删除旧数据，最后插入预定义数据）
func preloadSearchKeysIfNeeded(context: ModelContext) {
    do {
        // 1. 获取所有 SearchKeys 数据
        let fetchDescriptor = FetchDescriptor<SearchKeys>()
        var existingData = try context.fetch(fetchDescriptor)
        
        // 按 timestamp 升序排序，确保较早的数据先处理
        existingData.sort { $0.timestamp < $1.timestamp }
        
        // 使用字典记录每个 name 对应保留的记录
        var retainedMap: [String: SearchKeys] = [:]
        // 记录需要删除的记录
        var keysToDelete: [SearchKeys] = []
        
        for key in existingData {
            // 忽略 name 为空的数据
            guard let name = key.name, !name.isEmpty else { continue }
            
            if let oldRecord = retainedMap[name] {
                // 已经存在较早的记录 oldRecord
                if let oldKey = oldRecord.key, !oldKey.isEmpty {
                    // 情况：oldRecord 的 key 非空，则后来的全部删除
                    keysToDelete.append(key)
                } else {
                    // oldRecord 的 key 为空
                    if let newKey = key.key, !newKey.isEmpty {
                        // 情况：old为空，新非空 => 保留新的，删除老的
                        keysToDelete.append(oldRecord)
                        retainedMap[name] = key
                    } else {
                        // 情况：均为空 => 保留最老的（即 oldRecord），删除当前重复记录
                        keysToDelete.append(key)
                    }
                }
            } else {
                // 第一次遇到该 name，直接保存
                retainedMap[name] = key
            }
        }
        
        // 2. 删除重复数据
        for record in keysToDelete {
            context.delete(record)
            print("删除旧 SearchKey：\(record.name ?? "Unknown")")
        }
        
        // 3. 删除数据库中存在但预定义数据中不存在的记录
        let predefinedSearchKeys = getSearchKeyList()
        // 构建预定义名称的集合（忽略空 name 的数据）
        let predefinedNames = Set(predefinedSearchKeys.compactMap { ($0.name ?? "").isEmpty ? nil : $0.name })
        
        // 遍历保留数据，若 name 不在预定义集合中，则删除记录
        for name in Array(retainedMap.keys) {
            if !predefinedNames.contains(name) {
                if let record = retainedMap[name] {
                    context.delete(record)
                    print("删除 SearchKey：\(name) (不存在于预定义数据)")
                }
                retainedMap.removeValue(forKey: name)
            }
        }
        
        // 4. 比对预定义数据，更新或新增记录
        for predefinedKey in predefinedSearchKeys {
            guard let name = predefinedKey.name, !name.isEmpty else { continue }
            
            if let existingRecord = retainedMap[name] {
                // 仅在字段有变化时执行更新操作
                if existingRecord.requestURL != predefinedKey.requestURL ||
                   existingRecord.company != predefinedKey.company ||
                   existingRecord.price != predefinedKey.price ||
                    existingRecord.help != predefinedKey.help {
                    
                    existingRecord.requestURL = predefinedKey.requestURL
                    existingRecord.company = predefinedKey.company
                    existingRecord.price = predefinedKey.price
                    existingRecord.help = predefinedKey.help
                    print("更新 SearchKey：\(name)")
                }
            } else {
                // 数据库中不存在该 name 的记录，则插入新的预定义数据
                context.insert(predefinedKey)
                print("新增 SearchKey：\(name)")
            }
        }
        
        // 5. 迁移与默认激活协调（由单一权威 AutomaticSearchMigration 统一管理）
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)
        
        // 6. 保存所有更改
        try context.save()
        print("SearchKeys 同步完成")
    } catch {
        print("SearchKeys 同步失败：\(error)")
    }
}


// MARK: - ToolKeys 预加载（去重时保留最新数据，删除旧数据，最后插入预定义数据）
func preloadToolKeysIfNeeded(context: ModelContext) {
    do {
        // 1. 获取所有 ToolKeys 数据
        let fetchDescriptor = FetchDescriptor<ToolKeys>()
        var existingData = try context.fetch(fetchDescriptor)
        
        // 按 timestamp 升序排序（较早的排在前面）
        existingData.sort { $0.timestamp < $1.timestamp }
        
        // 用于记录每个 name 对应的保留记录
        var retainedMap: [String: ToolKeys] = [:]
        // 存放需要删除的重复记录
        var keysToDelete: [ToolKeys] = []
        
        // 2. 遍历已存在的数据，处理重复记录
        for tool in existingData {
            // 忽略 name 为空的数据
            if tool.name.isEmpty { continue }
            
            if let oldRecord = retainedMap[tool.name] {
                // 存在同名的较早记录 oldRecord
                if !oldRecord.key.isEmpty {
                    // 若老记录的 key 非空，直接删除当前重复记录
                    keysToDelete.append(tool)
                } else {
                    // 老记录的 key 为空
                    if !tool.key.isEmpty {
                        // 当前记录的 key 非空，则用当前记录替换老记录
                        keysToDelete.append(oldRecord)
                        retainedMap[tool.name] = tool
                    } else {
                        // 若两者均为空，保留较早记录，删除当前记录
                        keysToDelete.append(tool)
                    }
                }
            } else {
                // 第一次遇到该 name，直接保留
                retainedMap[tool.name] = tool
            }
        }
        
        // 3. 删除重复数据
        for tool in keysToDelete {
            context.delete(tool)
            print("删除旧 ToolKey: \(tool.name)")
        }
        
        // 4. 获取预定义数据并删除数据库中存在但预定义数据中不存在的数据
        let predefinedToolKeys = getToolKeyList()
        // 构建预定义名称的集合（忽略空 name 的数据）
        let predefinedNames = Set(predefinedToolKeys.compactMap { $0.name.isEmpty ? nil : $0.name })
        
        // 注意：遍历 retainedMap.keys 的一个副本，同时将删除的数据从 retainedMap 中移除
        for name in Array(retainedMap.keys) {
            if !predefinedNames.contains(name) {
                if let tool = retainedMap[name] {
                    context.delete(tool)
                    print("删除 ToolKey: \(name) (不存在于预定义数据)")
                }
                retainedMap.removeValue(forKey: name)
            }
        }
        
        // 5. 对预定义数据进行比对、更新或新增
        for predefined in predefinedToolKeys {
            // 忽略 name 为空的数据
            if predefined.name.isEmpty { continue }
            
            if let existingRecord = retainedMap[predefined.name] {
                // 判断需要更新的字段是否不同，只有不一致时才进行更新
                if existingRecord.requestURL != predefined.requestURL ||
                   existingRecord.company != predefined.company ||
                   existingRecord.price != predefined.price ||
                   existingRecord.toolClass != predefined.toolClass ||
                    existingRecord.help != predefined.help
                {
                    existingRecord.company = predefined.company
                    existingRecord.price = predefined.price
                    existingRecord.toolClass = predefined.toolClass
                    existingRecord.help = predefined.help
                    if existingRecord.toolClass != "weather" {
                        existingRecord.requestURL = predefined.requestURL
                    }
                    print("更新 ToolKey: \(predefined.name)")
                }
            } else {
                // 没有该 name 的记录，则插入预定义数据
                context.insert(predefined)
                print("新增 ToolKey: \(predefined.name)")
            }
        }
        
        // 6. 保存更改
        try context.save()
        print("ToolKeys 同步完成")
    } catch {
        print("ToolKeys 同步失败: \(error)")
    }
}

// MARK: - UserInfo 预加载（保证仅存在一条记录，保留最早数据）
func preloadUserInfoIfNeeded(context: ModelContext) {
    do {
        let fetchDescriptor = FetchDescriptor<UserInfo>()
        let existingData = try context.fetch(fetchDescriptor)

        if existingData.count > 1 {
            print("发现多个 UserInfo，执行去重...")
            // 将数据按时间从早到晚排序
            let sortedData = existingData.sorted { $0.timestamp < $1.timestamp }

            // 默认保留最早创建的那一条记录
            let kept = sortedData.first

            for info in sortedData where info != kept {
                context.delete(info)
            }
        }

        // 如果数据库中没有 UserInfo，则插入默认值
        if existingData.isEmpty {
            let defaultUserInfo = UserInfo(
                name: "",
                userInfo: "",
                userRequirements: "",
                outPutFeedBack: false,
                timestamp: Date()
            )
            context.insert(defaultUserInfo)
            print("新增默认 UserInfo")
        }

        // 清理含有 hanlin（不区分大小写）的模型配置
        if let userInfo = existingData.first {
            // 检测 chooseEmbeddingModel
            if let embeddingModel = userInfo.chooseEmbeddingModel,
               embeddingModel.lowercased().contains("hanlin") {
                userInfo.chooseEmbeddingModel = ""
                print("清除 chooseEmbeddingModel（含有 hanlin）: \(embeddingModel)")
            }
            // 检测 optimizationTextModel
            if userInfo.optimizationTextModel.lowercased().contains("hanlin") {
                let oldValue = userInfo.optimizationTextModel
                userInfo.optimizationTextModel = ""
                print("清除 optimizationTextModel（含有 hanlin）: \(oldValue)")
            }
            // 检测 optimizationVisualModel
            if userInfo.optimizationVisualModel.lowercased().contains("hanlin") {
                let oldValue = userInfo.optimizationVisualModel
                userInfo.optimizationVisualModel = ""
                print("清除 optimizationVisualModel（含有 hanlin）: \(oldValue)")
            }
        }

        try context.save()
        print("UserInfo 同步完成")

    } catch {
        print("UserInfo 同步失败：\(error)")
    }
}

// MARK: - PromptRepo 预加载（仅当数据库为空时插入预置数据）
func preloadPromptIfNeeded(context: ModelContext) {
    do {
        let fetchDescriptor = FetchDescriptor<PromptRepo>()
        let existingPrompts = try context.fetch(fetchDescriptor)

        // 如果数据库已存在数据，则不插入预置内容
        if !existingPrompts.isEmpty {
            print("PromptRepo 已存在数据，跳过预加载")
            return
        }

        // 预置 prompt 数据
        let defaultPrompts: [PromptRepo] = [
            PromptRepo(name: "专业写作改进", content: "改进下面文本的用词、语法、清晰、简洁和整体可读性，同时分解长句，减少重复，并提供改进建议。请只提供文本的更正版本，避免包括解释。请从编辑以下文本开始：", position: 0),
            PromptRepo(name: "英语润色翻译", content: "我希望你能充当英语翻译、拼写纠正者和改进者。我将用任何语言与你交谈，你将检测语言，翻译它，并在我的文本的更正和改进版本中用英语回答。我希望你用更漂亮、更优雅、更高级的英语单词和句子来取代我的简化 A0 级单词和句子。保持意思不变，但让它们更有文学性。我希望你只回答更正，改进，而不是其他，不要写解释。我的第一句话是：", position: 1),
        ]

        for prompt in defaultPrompts {
            context.insert(prompt)
        }

        try context.save()
        print("PromptRepo 已插入预置数据")

    } catch {
        print("PromptRepo 预加载失败：\(error)")
    }
}

// MARK: - 清理孤立数据（ChatMessages、ModelsInfo、KnowledgeChunk）
func clearOrphanData(context: ModelContext) {
    // MARK: 1. 清理没有关联 ChatRecords 的 ChatMessages
    let messagesFetchDescriptor = FetchDescriptor<ChatMessages>(
        predicate: #Predicate { chatMessage in
            chatMessage.record == nil
        }
    )
    // 使用 try? 避免在此处写 do/catch，若失败则返回空数组
    let orphanMessages = (try? context.fetch(messagesFetchDescriptor)) ?? []
    for message in orphanMessages {
        context.delete(message)
        print("删除孤立的 ChatMessage: \(message.id)")
    }
    print("孤立的 ChatMessages 清理完成")

    // MARK: 3. 清理没有关联 KnowledgeRecords 的 KnowledgeChunk
    let chunkFetchDescriptor = FetchDescriptor<KnowledgeChunk>(
        predicate: #Predicate { chunk in
            chunk.knowledgeRecord == nil
        }
    )
    let orphanChunks = (try? context.fetch(chunkFetchDescriptor)) ?? []
    for chunk in orphanChunks {
        context.delete(chunk)
        print("删除孤立的 KnowledgeChunk: \(chunk.id)")
    }
    print("孤立的 KnowledgeChunk 清理完成")

    // MARK: 4. 保存更改
    do {
        try context.save()
        print("孤立数据清理保存成功")
    } catch {
        print("保存孤立数据清理结果失败：\(error)")
    }
}
