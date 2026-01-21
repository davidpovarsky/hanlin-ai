//
//  ModelManagementView.swift
//  AI_HLY
//
//  Created by Claude on 2025/1/17.
//

import SwiftUI
import SwiftData

// MARK: - 模型管理视图
struct ModelManagementView: View {
    let apiKey: APIKeys
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allModels: [AllModels]

    @State private var apiModels: [APIModelResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchText = ""
    @ScaledMetric(relativeTo: .body) private var size_30: CGFloat = 30
    @State private var showAPIKeyError = false
    @State private var apiKeyErrorMessage = ""
    @State private var showProbeSheet = false
    @State private var probeItems: [CapabilityProbeItem] = []
    @State private var isAddedModelsExpanded = true  // 已添加模型折叠状态

    // 获取该厂商已添加的模型
    private var companyModels: [AllModels] {
        allModels.filter { model in
            model.company == apiKey.company &&
            model.identity?.lowercased() == "model"
        }
    }

    // 过滤后的 API 模型列表
    private var filteredAPIModels: [APIModelResponse] {
        if searchText.isEmpty {
            return apiModels
        }
        return apiModels.filter { model in
            model.id.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // 过滤后的已添加模型列表
    private var filteredCompanyModels: [AllModels] {
        if searchText.isEmpty {
            return companyModels
        }
        return companyModels.filter { model in
            let displayName = model.displayName ?? model.name ?? ""
            let name = model.name ?? ""
            return displayName.localizedCaseInsensitiveContains(searchText) ||
                   name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // 总模型数量（用于判断是否显示搜索栏）
    private var totalModelCount: Int {
        companyModels.count + apiModels.count
    }

    // 检查模型是否已添加
    private func isModelAdded(_ modelId: String) -> Bool {
        let fullName = modelId + "_repeat_" + (apiKey.company ?? "")
        let normalizedId = restoreBaseModelName(from: modelId)
        return allModels.contains { model in
            guard model.company == apiKey.company else { return false }
            guard model.identity?.lowercased() == "model" else { return false }
            let modelName = model.name ?? ""
            let displayName = model.displayName ?? modelName
            if modelName == fullName {
                return true
            }
            let normalizedModelName = restoreBaseModelName(from: modelName)
            let normalizedDisplayName = restoreBaseModelName(from: displayName)
            return normalizedModelName == normalizedId || normalizedDisplayName == normalizedId
        }
    }

    // 获取已添加模型的完整名称
    private func getAddedModelName(_ modelId: String) -> String? {
        let fullName = modelId + "_repeat_" + (apiKey.company ?? "")
        let normalizedId = restoreBaseModelName(from: modelId)
        return allModels.first { model in
            guard model.company == apiKey.company else { return false }
            guard model.identity?.lowercased() == "model" else { return false }
            let modelName = model.name ?? ""
            let displayName = model.displayName ?? modelName
            if modelName == fullName {
                return true
            }
            let normalizedModelName = restoreBaseModelName(from: modelName)
            let normalizedDisplayName = restoreBaseModelName(from: displayName)
            return normalizedModelName == normalizedId || normalizedDisplayName == normalizedId
        }?.name
    }

    private func displayNameForAddedModel(_ model: AllModels) -> String {
        let displayName = model.displayName ?? model.name ?? "Unknown"
        if model.identity == "agent" {
            let baseName = restoreBaseModelName(from: model.name ?? displayName)
            return "\(displayName)(\(baseName))"
        }
        return restoreBaseModelName(from: displayName)
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    // 加载状态
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在获取模型列表...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if apiModels.isEmpty {
                    // 空状态
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("暂无可用模型")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("刷新模型列表") {
                            Task {
                                await fetchModels()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.hlBlue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 模型列表
                    List {
                        // 搜索栏（已添加模型 + 可用模型总数 > 10 时显示）
                        if totalModelCount > 10 {
                            Section {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.secondary)
                                    TextField("搜索模型...", text: $searchText)
                                        .textFieldStyle(.plain)
                                    if !searchText.isEmpty {
                                        Button {
                                            searchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        Section(footer: Text("注意：自动模型能力探测中可能有一定的API费用消耗")) {
                            Toggle("自动模型能力探测", isOn: Binding(
                                get: { apiKey.autoProbeCapabilities },
                                set: { newValue in
                                    apiKey.autoProbeCapabilities = newValue
                                    saveChanges()
                                }
                            ))
                            .tint(.hlBlue)
                        }

                        // 已添加的模型（支持折叠）
                        if !filteredCompanyModels.isEmpty || (!searchText.isEmpty && !companyModels.isEmpty) {
                            Section(header: 
                                HStack {
                                    Text("已添加的模型 (\(filteredCompanyModels.count))")
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isAddedModelsExpanded.toggle()
                                        }
                                    } label: {
                                        Image(systemName: isAddedModelsExpanded ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                            ) {
                                if isAddedModelsExpanded {
                                    ForEach(filteredCompanyModels, id: \.id) { model in
                                        ModelRowView(
                                            model: model,
                                            size_30: size_30,
                                            highlightDisplayName: highlightDisplayName(for:),
                                            priceText: priceText(for:),
                                            priceColor: priceColor(for:),
                                            hasValidAPIKey: hasValidAPIKey(for:),
                                            saveChanges: { saveChanges() },
                                            onDelete: {
                                                removeModel(model)
                                            },
                                            showAPIKeyError: $showAPIKeyError,
                                            errorMessage: $apiKeyErrorMessage
                                        )
                                    }
                                }
                            }
                        }

                        // 可添加的模型
                        Section(header: Text("可用模型 (\(filteredAPIModels.count))")) {
                            ForEach(filteredAPIModels, id: \.id) { model in
                                let providerName = (model.owned_by?.isEmpty == false)
                                    ? model.owned_by ?? ""
                                    : getCompanyName(for: apiKey)
                                let iconName = apiKey.from == .custom
                                    ? "defaultIcon"
                                    : getCompanyIcon(for: apiKey.company ?? "Unknown")

                                HStack(spacing: 12) {
                                    Image(iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: size_30, height: size_30)

                                    VStack(alignment: .leading, spacing: 4) {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            Text(model.id)
                                                .font(.subheadline)
                                        }
                                        Text("提供者: \(providerName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()

                                    if isModelAdded(model.id) {
                                        // 已添加状态
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Button {
                                                if let modelName = getAddedModelName(model.id) {
                                                    removeModelByName(modelName)
                                                }
                                            } label: {
                                                Text("删除")
                                                    .foregroundColor(.red)
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    } else {
                                        // 可添加状态
                                        Button {
                                            Task {
                                                await addModel(model)
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus.circle")
                                                Text("添加")
                                            }
                                            .font(.caption)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.hlBlue)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("模型管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await fetchModels()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .alert("API Key 缺失", isPresented: $showAPIKeyError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(apiKeyErrorMessage)
        }
        .sheet(isPresented: $showProbeSheet) {
            CapabilityProbeSheet(
                items: probeItems,
                onClose: { showProbeSheet = false }
            )
        }
        .onAppear {
            Task {
                await fetchModels()
            }
        }
    }

    private func updateProbeItem(step: ModelCapabilityProbeStep, status: ModelCapabilityProbeStatus, message: String?) {
        if let index = probeItems.firstIndex(where: { $0.step == step }) {
            probeItems[index].status = status
            probeItems[index].message = message
        }
    }

    private func highlightDisplayName(for model: AllModels) -> AnyView {
        AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                Text(displayNameForAddedModel(model))
                    .font(.subheadline)
            }
        )
    }

    private func hasValidAPIKey(for model: AllModels) -> Bool {
        if model.company?.uppercased() == "LOCAL" {
            return true
        }
        guard let company = model.company, let key = apiKey.key else {
            return false
        }
        return !company.isEmpty && !key.isEmpty
    }

    private func priceText(for price: Int16) -> String {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        if currentLanguage.hasPrefix("zh") {
            switch price {
            case 0: return "免费"
            case 1: return "廉价"
            case 2: return "适中"
            default: return "昂贵"
            }
        } else {
            switch price {
            case 0: return "Free"
            case 1: return "Cheap"
            case 2: return "Moderate"
            default: return "Expensive"
            }
        }
    }

    private func priceColor(for price: Int16) -> Color {
        switch price {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("保存更改失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 获取模型列表
    private func fetchModels() async {
        isLoading = true
        errorMessage = nil

        do {
            apiModels = try await ModelRefreshService.fetchModelsFromAPI(apiKey: apiKey)
            // 按字母顺序排序
            apiModels.sort { $0.id < $1.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    // MARK: - 添加模型
    private func addModel(_ model: APIModelResponse) async {
        guard let company = apiKey.company else {
            errorMessage = "添加失败: 无效的厂商"
            showError = true
            return
        }

        if apiKey.autoProbeCapabilities {
            showProbeSheet = true
            probeItems = ModelCapabilityProbeStep.allCases.map { step in
                CapabilityProbeItem(step: step, status: .pending, message: nil)
            }
            do {
                let result = try await ModelRefreshService.probeModelCapabilities(
                    modelId: model.id,
                    company: company,
                    context: modelContext,
                    update: { step, status, message in
                        updateProbeItem(step: step, status: status, message: message)
                    }
                )
                try ModelRefreshService.addModelToDatabase(
                    modelId: model.id,
                    displayName: model.id,
                    company: company,
                    context: modelContext,
                    capabilities: result.capabilities
                )
            } catch {
                errorMessage = "添加失败: \(error.localizedDescription)"
                showError = true
            }
        } else {
            do {
                try ModelRefreshService.addModelToDatabase(
                    modelId: model.id,
                    displayName: model.id,
                    company: company,
                    context: modelContext
                )
            } catch {
                errorMessage = "添加失败: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - 删除模型（通过模型对象）
    private func removeModel(_ model: AllModels) {
        // 只能删除非系统预置的模型
        if !model.systemProvision {
            modelContext.delete(model)
            do {
                try modelContext.save()
            } catch {
                errorMessage = "删除失败: \(error.localizedDescription)"
                showError = true
            }
        } else {
            errorMessage = "系统预置模型无法删除"
            showError = true
        }
    }

    // MARK: - 删除模型（通过名称）
    private func removeModelByName(_ modelName: String) {
        do {
            try ModelRefreshService.removeModelFromDatabase(
                modelName: modelName,
                context: modelContext
            )
        } catch {
            errorMessage = "删除失败: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - 快速模型刷新按钮
struct QuickModelRefreshButton: View {
    let apiKey: APIKeys
    @State private var showModelManagement = false

    var body: some View {
        Button {
            showModelManagement = true
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("刷新模型列表")
            }
        }
        .sheet(isPresented: $showModelManagement) {
            ModelManagementView(apiKey: apiKey)
        }
    }
}

struct CapabilityProbeItem: Identifiable, Equatable {
    let id = UUID()
    let step: ModelCapabilityProbeStep
    var status: ModelCapabilityProbeStatus
    var message: String?
}

struct CapabilityProbeSheet: View {
    let items: [CapabilityProbeItem]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("模型能力自动探测")
                .font(.headline)
                .padding(.top, 16)

            VStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        statusView(for: item.status)
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.step.title)
                                .font(.subheadline)
                            if let message = item.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal)

            Button("完成") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(.hlBlue)
            .padding(.bottom, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func statusView(for status: ModelCapabilityProbeStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .semibold))
        case .running:
            ProgressView()
                .scaleEffect(0.8)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 16, weight: .semibold))
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}
