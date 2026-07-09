//
//  APISettingView.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 24/3/25.
//

import SwiftUI
import SwiftData

// MARK: 大模型 API 与厂商设置界面
struct APIKeysView: View {
    // 查询所有 APIKeys、所有模型与模型信息
    @Query var apiKeys: [APIKeys]
    @Query var allModels: [AllModels]
    
    // 环境中的 SwiftData 上下文
    @Environment(\.modelContext) private var modelContext
    
    // APIKey 编辑状态
    @State private var selectedKey: APIKeys?
    @State private var testResult: Bool? = nil
    @State private var isTesting = false
    @State private var testErrorMessage: String? = nil
    @State private var isInquiring = false
    @State private var inquiryResult: Double? = nil

    // 错误提示及加载状态
    @State private var errorMessage: String = ""
    @State private var showAPIKeyError: Bool = false
    @State private var loadingCompany: String? = nil

    // 新增自定义供应商状态
    @State private var showAddCustomProvider = false
    
    // 按完整拼音排序 APIKeys（过滤掉 LOCAL、HANLIN、HANLIN_OPEN 类型）
    private var sortedApiKeys: [APIKeys] {
        apiKeys
            .filter {
                let company = ($0.company ?? "").uppercased()
                return company != "LOCAL" && company != "HANLIN" && company != "HANLIN_OPEN"
            }
            .sorted { key1, key2 in
                let pinyin1 = getPinyin(for: getCompanyName(for: key1))
                let pinyin2 = getPinyin(for: getCompanyName(for: key2))
                return pinyin1 < pinyin2
            }
    }

    // 获取唯一厂商，并按完整拼音排序
    private var sortedCompanies: [(company: String, key: APIKeys)] {
        let uniqueCompanies = Dictionary(grouping: apiKeys, by: { $0.company })
            .compactMapValues { $0.first } // 每个厂商只取一条数据
        return uniqueCompanies.values.sorted { key1, key2 in
            let pinyin1 = getPinyin(for: getCompanyName(for: key1))
            let pinyin2 = getPinyin(for: getCompanyName(for: key2))
            return pinyin1 < pinyin2
        }.map { ( ($0.company ?? "Unknown"), $0) }
    }
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "key.2.on.ring")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "点击名称或钥匙设置厂商密钥，并打开厂商开关以使用该厂商的模型"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            ForEach(sortedCompanies, id: \.company) { company, key in
                HStack {
                    // 按钮部分：只有允许配置 API 的才可点击进入编辑界面
                    Button {
                        // 仅当允许设置 API 时响应点击
                        if isAPISettingAllowed(for: key) {
                            // 重置相关状态并进入编辑界面
                            inquiryResult = nil
                            testResult = nil
                            isTesting = false
                            isInquiring = false
                            selectedKey = key
                        }
                    } label: {
                        HStack {
                            // 自定义供应商使用 defaultIcon，系统供应商使用资源图片
                            if key.from == .custom {
                                Image("defaultIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(getCompanyIcon(for: company))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }

                            // 使用重载函数自动处理自定义供应商名称
                            Text(getCompanyName(for: key))
                            Spacer()
                            if isAPISettingAllowed(for: key) {
                                Image(systemName: "key")
                                    .foregroundColor(.hlBluefont)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Toggle 控件：如果当前厂商正在加载，则显示加载动画
                    if loadingCompany == company {
                        ProgressView()
                    } else {
                        Toggle("", isOn: Binding(
                            get: { !key.isHidden },
                            set: { newValue in
                                toggleVendor(key: key, company: company, newValue: newValue)
                            }
                        ))
                        .labelsHidden()
                        .tint(.hlBlue)
                        // 当 API Key 无效时，不允许通过 Toggle 开启厂商
                        .disabled(!hasValidAPIKey(for: key))
                    }
                }
            }
        }
        .navigationTitle(String(localized: "模型厂商"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddCustomProvider = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.hlBluefont)
                }
            }
        }
        .sheet(item: $selectedKey) { key in
            editKeyView(for: key)
        }
        .sheet(isPresented: $showAddCustomProvider) {
            addCustomProviderView()
        }
        .alert(String(localized: "无法开启厂商"), isPresented: $showAPIKeyError) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: API Key 编辑界面
    @ViewBuilder
    private func editKeyView(for key: APIKeys) -> some View {
        NavigationView {
            EditKeyContent(
                key: key,
                modelContext: modelContext,
                allModels: allModels,
                selectedKey: $selectedKey
            )
        }
    }
}

// MARK: - 密钥编辑内容视图
private struct EditKeyContent: View {
    let key: APIKeys
    let modelContext: ModelContext
    let allModels: [AllModels]
    @Binding var selectedKey: APIKeys?

    @State private var testResult: Bool? = nil
    @State private var isTesting = false
    @State private var testErrorMessage: String? = nil
    @State private var isInquiring = false
    @State private var inquiryResult: Double? = nil
    @State private var showModelManagement = false
    @State private var selectedTestModelName: String = ""

    private var isZh: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") ?? true
    }

    // 获取当前厂商支持文本生成的模型（用于API测试）
    private var testableModels: [AllModels] {
        allModels.filter { model in
            // 必须支持文本生成
            guard model.supportsTextGen else { return false }
            // 检查是否是当前厂商的模型
            if let modelCompany = model.company, modelCompany == key.company {
                return true
            }
            // 检查是否是通过 _repeat_ 添加的当前厂商模型
            if let modelName = model.name,
               modelName.contains("_repeat_\(key.company ?? "")") {
                return true
            }
            return false
        }.sorted { model1, model2 in
            // 系统预置的模型排在前面
            if model1.systemProvision != model2.systemProvision {
                return model1.systemProvision
            }
            // 按名称排序
            return (model1.displayName ?? model1.name ?? "") < (model2.displayName ?? model2.name ?? "")
        }
    }

    // 获取当前厂商的所有模型（包括系统预置和用户添加的）
    private var currentCompanyModels: [AllModels] {
        allModels.filter { model in
            // 检查是否是当前厂商的模型
            if let modelCompany = model.company, modelCompany == key.company {
                return true
            }
            // 检查是否是通过 _repeat_ 添加的当前厂商模型
            if let modelName = model.name,
               modelName.contains("_repeat_\(key.company ?? "")") {
                return true
            }
            return false
        }.sorted { model1, model2 in
            // 系统预置的模型排在前面
            if model1.systemProvision != model2.systemProvision {
                return model1.systemProvision
            }
            // 按名称排序
            return (model1.displayName ?? model1.name ?? "") < (model2.displayName ?? model2.name ?? "")
        }
    }

    var body: some View {
            Form {
                Section {
                    VStack(alignment: .center) {
                        // 自定义供应商使用 defaultIcon
                        if key.from == .custom {
                            Image("defaultIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .padding()
                        } else {
                            Image(getCompanyIcon(for: key.company ?? "Unknown"))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .padding()
                        }

                        Text("设置 \(getCompanyName(for: key)) API密钥，以启用该厂商的模型")
                            .font(.footnote)
                            .multilineTextAlignment(.center)

                        // 自定义供应商不显示获取API密钥的链接
                        if key.from != .custom {
                            if let url = URL(string: key.help) {
                            Link(String(format: String(localized: "🔗 点此获取 %@ API密钥"), getCompanyName(for: key)), destination: url)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom)
                            } else {
                                // 当 URL 无效时可以提供一个备用视图
                                Text(String(localized: "建议进入其开放平台获取API密钥"))
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Section(header: Text("API Key")) {
                    SecureField(String(localized: "请输入密钥"), text: Binding(
                        get: { key.key ?? "" },
                        set: { key.key = $0 }
                    ))
                }
                // 自定义供应商或LAN供应商显示请求地址设置
                if key.company == "LAN" || key.from == .custom {
                    Section(header: Text(String(localized: "请求地址（URL）"))) {
                        Text(verbatim: String(localized: "例如：http://127.0.0.1:1234/v1/chat/completions"))
                            .font(.caption)
                        TextField(String(localized: "请输入请求地址"), text: Binding(
                            get: { key.requestURL ?? "" },
                            set: { key.requestURL = $0 }
                        ))
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    }
                }
                // 测试 API 按钮及状态显示（局域网模型和自定义供应商不显示）
                if key.company != "LAN" && key.from != .custom {
                    Section(header: Text(String(localized: "API 测试"))) {
                        // 模型选择器（如果有可测试的模型）
                        if !testableModels.isEmpty {
                            Picker(String(localized: "测试模型"), selection: $selectedTestModelName) {
                                ForEach(testableModels, id: \.name) { model in
                                    Text(model.displayName ?? model.name ?? String(localized: "未知模型"))
                                        .tag(model.name ?? "")
                                }
                            }
                        }
                        
                        // 测试按钮
                        HStack {
                            Button(String(localized: "测试 API")) {
                                testAPI(for: key)
                            }
                            .disabled(isTesting || testableModels.isEmpty)
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let result = testResult {
                                Text(result ? String(localized: "测试通过") : String(localized: "测试失败"))
                                    .foregroundColor(result ? .green : .red)
                            } else if testableModels.isEmpty {
                                Text(String(localized: "无可用模型"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let errorMessage = testErrorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.hlOrange)
                        }
                    }
                }
                if key.company == "DEEPSEEK" || key.company == "SILICONCLOUD" {
                    // 余额查询及状态显示
                    Section {
                        HStack {
                            Button(String(localized: "查询 API 余额")) {
                                queryBalance(for: key)
                            }
                            .disabled(isInquiring)
                            Spacer()
                            if isInquiring {
                                ProgressView()
                            } else if let result = inquiryResult {
                                Text(result == -999 ? String(localized: "该厂商暂未支持") : "¥\(result)")
                                    .foregroundColor(result < 10 ? .red : .green)
                            }
                        }
                    }
                }
                // 刷新模型列表按钮和已添加模型展示（仅对支持的厂商显示）
                if shouldShowModelRefresh(for: key) {
                    Section(header: Text(String(localized: "模型管理"))) {
                        // 刷新模型列表按钮
                        Button {
                            showModelManagement = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.hlBluefont)
                                Text(String(localized: "刷新模型列表"))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Section {
                    Text(String(localized: "⚠️ 注意：配置API后，厂商将自动开启，如需修改，可以在菜单中关闭厂商"))
                        .font(.footnote)
                }
            }
            .navigationTitle(String(localized: "编辑密钥"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        selectedKey = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        key.timestamp = Date()
                        key.isHidden = false
                        try? modelContext.save()
                        selectedKey = nil
                    }
                }
            }
            .onAppear {
                testResult = nil
                testErrorMessage = nil
                // 初始化选中的测试模型为第一个可用模型
                if selectedTestModelName.isEmpty, let firstModel = testableModels.first {
                    selectedTestModelName = firstModel.name ?? ""
                }
            }
            .sheet(isPresented: $showModelManagement) {
                ModelManagementView(apiKey: key)
            }
    }
    
    /// 判断是否应该显示模型刷新按钮
    private func shouldShowModelRefresh(for key: APIKeys) -> Bool {
        // 自定义供应商和 LAN 不显示
        if key.from == .custom || key.company == "LAN" {
            return false
        }
        // 本地、翰林等特殊厂商不显示
        guard let company = key.company?.uppercased() else { return false }
        if company == "LOCAL" || company == "HANLIN" || company == "HANLIN_OPEN" {
            return false
        }
        // 支持 OpenAI 兼容接口的厂商
        return true
    }

    // MARK: - API 测试与查询
    /// 点击测试 API 时调用，使用选中的模型进行测试
    private func testAPI(for key: APIKeys) {
        isTesting = true
        testResult = nil
        testErrorMessage = nil
        
        // 使用选中的模型，如果没有选中则使用第一个可用模型
        let modelToTest = selectedTestModelName.isEmpty 
            ? (testableModels.first?.name ?? "") 
            : selectedTestModelName
        
        Task {
            let result = await testAIAPIWithModel(
                apiKey: key.key ?? "",
                requestURL: key.requestURL ?? "",
                company: key.company ?? "",
                modelName: modelToTest
            )
            testResult = result.0
            testErrorMessage = result.1
            isTesting = false
        }
    }
    
    /// 点击查询 API 余额时调用
    private func queryBalance(for key: APIKeys) {
        isInquiring = true
        inquiryResult = nil
        Task {
            defer { isInquiring = false }
            guard let company = key.company?.uppercased(),
                  let token = key.key, !token.isEmpty else { return }
            do {
                switch company {
                case "DEEPSEEK":
                    inquiryResult = try await fetchDeepSeekBalance(token: token)
                case "SILICONCLOUD":
                    inquiryResult = try await fetchSiliconFlowBalance(token: token)
                default:
                    inquiryResult = -999
                }
            } catch {
                print("余额查询失败：\(error)")
                inquiryResult = nil
            }
        }
    }
}

// MARK: - APIKeysView 扩展方法
extension APIKeysView {
    // MARK: - 厂商隐藏/显示处理
    /// 处理厂商开关逻辑，并增加加载状态
    private func toggleVendor(key: APIKeys, company: String, newValue: Bool) {
        loadingCompany = company
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                if !newValue {
                    // 关闭厂商
                    key.isHidden = true
                    updateModelVisibility(for: company, isHidden: true)
                } else if hasValidAPIKey(for: key) {
                    // 开启厂商（API Key 有效）
                    key.isHidden = false
                } else {
                    // API Key 为空时阻止开启，并显示错误提示
            errorMessage = String(format: String(localized: "%@ 需要有效的 API Key，请先设置密钥。"), getCompanyName(for: key))
                    showAPIKeyError = true
                }
                saveChanges()
                loadingCompany = nil
            }
        }
    }
    
    /// 检查 APIKey 是否有效（非空即可）
    private func hasValidAPIKey(for key: APIKeys) -> Bool {
        return !(key.key?.isEmpty ?? true)
    }
    
    /// 保存数据
    private func saveChanges() {
        DispatchQueue.main.async {
            do {
                try modelContext.save()
            } catch {
                print("保存失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 将文本转换为拼音（大写），用于排序
    private func getPinyin(for text: String) -> String {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String).uppercased()
    }
    
    /// 更新 AllModels 与 ModelsInfo 数据库中该厂商的所有模型的 isHidden 状态
    private func updateModelVisibility(for company: String, isHidden: Bool) {
        for model in allModels where model.company == company {
            model.isHidden = isHidden
        }
    }
    
    /// 判断是否允许进入 API Key 编辑（即允许设置 API），此处根据公司名称过滤
    private func isAPISettingAllowed(for key: APIKeys) -> Bool {
        guard let company = key.company?.uppercased() else { return false }
        return !(company == "LOCAL" || company == "HANLIN" || company == "HANLIN_OPEN")
    }

    /// 判断是否应该显示模型刷新按钮
    private func shouldShowModelRefresh(for key: APIKeys) -> Bool {
        // 自定义供应商和 LAN 不显示
        if key.from == .custom || key.company == "LAN" {
            return false
        }
        // 本地、翰林等特殊厂商不显示
        guard let company = key.company?.uppercased() else { return false }
        if company == "LOCAL" || company == "HANLIN" || company == "HANLIN_OPEN" {
            return false
        }
        // 支持 OpenAI 兼容接口的厂商
        return true
    }

    // MARK: 新增自定义供应商界面
    @ViewBuilder
    private func addCustomProviderView() -> some View {
        NavigationView {
            AddCustomProviderForm(modelContext: modelContext, isPresented: $showAddCustomProvider)
        }
    }
}

// MARK: - 新增自定义供应商表单视图
struct AddCustomProviderForm: View {
    let modelContext: ModelContext
    @Binding var isPresented: Bool

    @State private var providerName: String = ""
    @State private var apiKey: String = ""
    @State private var requestURL: String = ""
    @State private var showValidationError = false
    @State private var validationMessage = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image("defaultIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .padding()

                    Text(String(localized: "添加自定义 API 供应商，使用兼容 OpenAI 格式的 API 服务"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Section(header: Text(String(localized: "供应商名称"))) {
                TextField(String(localized: "请输入供应商名称"), text: $providerName)
            }

            Section(header: Text("API Key")) {
                SecureField(String(localized: "请输入 API 密钥"), text: $apiKey)
            }

            Section(header: Text(String(localized: "请求地址（URL）"))) {
                Text(String(localized: "例如：https://api.example.com/v1/chat/completions"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField(String(localized: "请输入请求地址"), text: $requestURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                if !requestURL.isEmpty && !requestURL.hasSuffix("/v1/chat/completions") {
                    Button(String(localized: "补全 /v1/chat/completions")) {
                        completeURL()
                    }
                    .font(.caption)
                    .foregroundColor(.hlBluefont)
                }
            }

            Section {
                Text(String(localized: "💡 提示：此功能适用于兼容 OpenAI API 格式的服务，如 LocalAI、Ollama 等本地部署服务，或其他第三方 API 服务"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(String(localized: "新增自定义供应商"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "取消")) {
                    isPresented = false
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "保存")) {
                    saveCustomProvider()
                }
                .disabled(!isFormValid)
            }
        }
        .alert(String(localized: "验证失败"), isPresented: $showValidationError) {
            Button(String(localized: "确定"), role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
    }

    private var isFormValid: Bool {
        !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (requestURL.hasPrefix("http://") || requestURL.hasPrefix("https://"))
    }

    private func completeURL() {
        var trimmedURL = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // 移除末尾的斜杠
        while trimmedURL.hasSuffix("/") {
            trimmedURL.removeLast()
        }

        // 补全标准路径
        if !trimmedURL.hasSuffix("/v1/chat/completions") {
            trimmedURL += "/v1/chat/completions"
        }

        requestURL = trimmedURL
    }

    private func saveCustomProvider() {
        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // 验证
        guard !trimmedName.isEmpty else {
                validationMessage = String(localized: "供应商名称不能为空")
            showValidationError = true
            return
        }

        guard !trimmedKey.isEmpty else {
                validationMessage = String(localized: "API Key 不能为空")
            showValidationError = true
            return
        }

        guard !trimmedURL.isEmpty else {
                validationMessage = String(localized: "请求地址不能为空")
            showValidationError = true
            return
        }

        guard trimmedURL.hasPrefix("http://") || trimmedURL.hasPrefix("https://") else {
                validationMessage = String(localized: "请求地址必须以 http:// 或 https:// 开头")
            showValidationError = true
            return
        }

        // 创建自定义供应商
        let customProvider = APIKeys(
            name: trimmedName,
            company: "CUSTOM_\(UUID().uuidString.prefix(8).uppercased())", // 使用唯一标识避免冲突
            key: trimmedKey,
            requestURL: trimmedURL,
            isHidden: false, // 默认启用
            help: "自定义 API 供应商",
            apiType: .openAI,
            from: .custom,
            timestamp: Date()
        )

        modelContext.insert(customProvider)

        do {
            try modelContext.save()
            isPresented = false
        } catch {
            validationMessage = String(format: String(localized: "保存失败：%@"), error.localizedDescription)
            showValidationError = true
        }
    }
}

// MARK: 搜索设置（API 配置、厂商选择、双语检索配置）界面
struct SearchSettingView: View {
    // 从数据库中获取搜索密钥配置
    @Query var searchKeys: [SearchKeys]
    // 从数据库中获取用户信息（用于双语检索配置）
    @Query private var users: [UserInfo]
    @Environment(\.modelContext) private var modelContext
    
    // SearchKeysView 部分状态
    // 用于编辑 API 配置状态
    @State private var selectedKey: SearchKeys?
    // API 测试相关状态
    @State private var testResult: Bool? = nil
    @State private var isTesting = false
    // 切换厂商启用状态时的加载与错误提示状态
    @State private var loadingCompany: String? = nil
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    // 双语检索配置状态
    @State private var bilingualSearch: Bool = true
    @State private var searchCount: Int = 10
    @State private var searchEnable: Bool = true
    
    // SearchKeysView 排序（按照公司名称拼音排序）
    private var sortedSearchKeys: [SearchKeys] {
        searchKeys.sorted { key1, key2 in
            let pinyin1 = getPinyin(for: getCompanyName(for: key1.company ?? "Unknown"))
            let pinyin2 = getPinyin(for: getCompanyName(for: key2.company ?? "Unknown"))
            return pinyin1 < pinyin2
        }
    }
    
    var body: some View {
        Form {
            // 顶部说明区域：统一介绍搜索配置的意义
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "magnifyingglass")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置搜索功能，以便在聊天对话时获取互联网内容，提升回答效果。个性化的设置能最大程度的平衡你的需求与检索带来的成本消耗"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // 检索设置部分
            Section(header: Text(String(localized: "模型在需要时主动搜索"))) {
                Toggle(String(localized: "启用主动搜索"), isOn: Binding(
                    get: { searchEnable },
                    set: { searchEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "搜索结果数量（范围：5-20）"))) {
                Stepper(value: $searchCount, in: 5...20) {
                    Text("搜索结果数量：\(searchCount)")
                }
            }
            
            Section(header: Text(String(localized: "搜索时同时搜索中英文内容"))) {
                Toggle(String(localized: "中英文双语检索"), isOn: $bilingualSearch)
                    .tint(.hlBlue)
            }
            
            // 搜索 API 配置及厂商选择部分
            Section(header: Text(String(localized: "搜索引擎选择（最多只能开启一个）"))) {
                ForEach(sortedSearchKeys) { key in
                    HStack {
                        // 点击左侧区域进入编辑 API 配置界面
                        Button {
                            selectedKey = key
                        } label: {
                            HStack {
                                Image(getCompanyIcon(for: key.company ?? "Unknown"))
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                Text(getCompanyName(for: key.company ?? "Unknown"))
                                    .foregroundColor(.primary)
                                
                                // 显示各厂商的计费或免费说明
                                switch key.company?.uppercased() {
                                case "GOOGLE_SEARCH":
                                    Text(String(localized: "100次免费/日"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                case "TAVILY":
                                    Text(String(localized: "1000免费积分/月"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                case "LANGSEARCH":
                                    Text(String(localized: "免费"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                case "BRAVE":
                                    Text(String(localized: "2000次免费/月"))
                                        .font(.caption)
                                        .foregroundColor(.green)
                                default:
                                    if let price = key.price {
                                        Text(String(format: String(localized: "¥%.4f/次"), price))
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "key")
                                    .foregroundColor(.hlBluefont)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 右侧区域：显示加载指示或 Toggle 控件切换启用状态
                        if loadingCompany == key.company {
                            ProgressView()
                        } else {
                            Toggle("", isOn: Binding(
                                get: { key.isUsing },
                                set: { newValue in
                                    toggleVendor(for: key, newValue: newValue)
                                }
                            ))
                            .labelsHidden()
                            .tint(.hlBlue)
                        }
                    }
                }
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "联网信息检索"), systemImage: "network")
                Label(String(localized: "学术论文检索"), systemImage: "graduationcap")
                Label(String(localized: "网页信息阅读"), systemImage: "text.and.command.macwindow")
                Label(String(localized: "网络文件阅读"), systemImage: "text.document")
            }
        }
        .navigationTitle(String(localized: "联网搜索"))
        // 编辑 API 配置界面（SearchKeysView 部分）的弹出 sheet
        .sheet(item: $selectedKey) { key in
            editKeyView(for: key)
        }
        // 出现错误时弹出警告
        .alert(errorMessage, isPresented: $showError) {
            Button(String(localized: "确定"), role: .cancel) { }
        }
        // 加载/保存双语检索相关的用户信息
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    // 加载数据库中的用户信息（双语检索设置）
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.bilingualSearch = existingUser.bilingualSearch
                self.searchCount = existingUser.searchCount
                self.searchEnable = existingUser.useSearch
            }
        }
    }
    
    // 保存双语检索设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.bilingualSearch = bilingualSearch
            existingUser.searchCount = searchCount
            existingUser.useSearch = searchEnable
        } else {
            let newUser = UserInfo(
                bilingualSearch: bilingualSearch,
                useSearch: searchEnable,
                searchCount: searchCount,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
    
    // 编辑搜索 API 密钥界面（SearchKeysView 部分）
    @ViewBuilder
    private func editKeyView(for key: SearchKeys) -> some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .center) {
                        Image(getCompanyIcon(for: key.company ?? "Unknown"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .padding()

                        Text(String(format: String(localized: "设置 %@ API密钥，以开启该搜索引擎"), getCompanyName(for: key.company ?? "Unknown")))
                            .font(.footnote)
                            .multilineTextAlignment(.center)

                        if let url = URL(string: key.help) {
                            Link(String(format: String(localized: "🔗 点此获取 %@ API密钥"), getCompanyName(for: key.company ?? "Unknown")), destination: url)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                        } else {
                            Text(String(localized: "建议进入其开放平台获取API密钥"))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                Section(header: Text(String(localized: "密钥"))) {
                    SecureField(String(localized: "请输入密钥"), text: Binding(
                        get: { key.key ?? "" },
                        set: { key.key = $0 }
                    ))
                }
                // 测试 API 部分
                Section {
                    HStack {
                        Button(String(localized: "测试 API")) {
                            testAPI(for: key)
                        }
                        .disabled(isTesting)
                        
                        Spacer()
                        
                        if isTesting {
                            ProgressView()
                        } else if let result = testResult {
                            Text(result ? String(localized: "测试通过") : String(localized: "测试失败"))
                                .foregroundColor(result ? .green : .red)
                        }
                    }
                }
                Section {
                    Text(String(localized: "⚠️ 注意：配置 API 后，请在菜单中打开您要使用的搜索引擎"))
                        .font(.footnote)
                }
            }
            .navigationTitle(String(localized: "编辑密钥"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        selectedKey = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        key.timestamp = Date()
                        try? modelContext.save()
                        selectedKey = nil
                    }
                }
            }
            .onAppear {
                testResult = nil
            }
        }
    }
    
    // 测试搜索 API
    private func testAPI(for key: SearchKeys) {
        isTesting = true
        testResult = nil
        
        Task {
            // 根据 key.company 获取对应的搜索引擎，默认使用 .LANGSEARCH
            let engine = SearchEngine(rawValue: key.company?.uppercased() ?? "") ?? .LANGSEARCH
            let result = await testSearchAPI(
                apiKey: key.key ?? "",
                requestURL: key.requestURL ?? "",
                engine: engine
            )
            testResult = result
            isTesting = false
        }
    }
    
    // 切换搜索厂商启用状态
    /// 仅允许一个厂商启用。若开启当前厂商，则关闭其它所有厂商。
    private func toggleVendor(for key: SearchKeys, newValue: Bool) {
        loadingCompany = key.company
        
        DispatchQueue.main.async {
            if newValue {
                // 开启前检查是否已配置 API Key
                if key.key?.isEmpty ?? true {
            errorMessage = String(format: String(localized: "%@ 需要配置 API Key 才能启用。"), getCompanyName(for: key.company ?? "Unknown"))
                    showError = true
                    loadingCompany = nil
                    return
                }
                // 开启当前厂商，同时关闭其它厂商
                for vendor in searchKeys {
                    vendor.isUsing = (vendor.id == key.id)
                }
            } else {
                // 关闭当前厂商
                key.isUsing = false
            }
            
            do {
                try modelContext.save()
            } catch {
            errorMessage = String(format: String(localized: "保存失败: %@"), error.localizedDescription)
                showError = true
            }
            loadingCompany = nil
        }
    }
    
    // 获取公司名称的拼音（用于排序）
    private func getPinyin(for text: String) -> String {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String).uppercased()
    }
}

// MARK: - 知识背包配置界面
struct KnowledgeSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var knowledgeEnable: Bool = true
    @State private var knowledgeCount: Int = 10
    @State private var knowledgeSimilarity: Double = 0.5
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "backpack")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置知识功能，以便在聊天对话时翻找知识背包，获取私有知识库内容，提升回答效果。"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section(header: Text(String(localized: "模型在需要时主动翻找知识背包"))) {
                Toggle(String(localized: "启用主动翻找"), isOn: Binding(
                    get: { knowledgeEnable },
                    set: { knowledgeEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "翻找结果数量（范围：5-20）"))) {
                Stepper(value: $knowledgeCount, in: 5...20) {
                    Text("翻找结果数量：\(knowledgeCount)")
                }
            }
            
            Section(header: Text(String(localized: "匹配度阈值（范围：0.05 - 1.0）"))) {
                Stepper(value: $knowledgeSimilarity, in: 0.05...1.0, step: 0.05) {
                    Text(String(format: String(localized: "匹配度阈值：%.2f"), knowledgeSimilarity))
                }
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "知识背包翻找"), systemImage: "backpack")
                Label(String(localized: "知识文档撰写"), systemImage: "text.document")
            }
        }
        .navigationTitle(String(localized: "知识背包"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.knowledgeEnable = existingUser.useKnowledge
                self.knowledgeCount = existingUser.knowledgeCount
                self.knowledgeSimilarity = existingUser.knowledgeSimilarity
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useKnowledge = knowledgeEnable
            existingUser.knowledgeCount = knowledgeCount
            existingUser.knowledgeSimilarity = knowledgeSimilarity
        } else {
            let newUser = UserInfo(
                useKnowledge: knowledgeEnable,
                knowledgeCount: knowledgeCount,
                knowledgeSimilarity: knowledgeSimilarity
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 地图配置界面
struct MapSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    // 查询 toolClass 为 "map" 的 ToolKeys 数据
    @Query(filter: #Predicate<ToolKeys> { key in
        key.toolClass == "map"
    })
    var mapKeys: [ToolKeys]
    
    @State private var mapEnable: Bool = true
    
    // 用于地图引擎配置相关状态
    @State private var selectedMapKey: ToolKeys?
    @State private var loadingMapCompany: String? = nil
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    // 根据需求对 mapKeys 排序，此处按公司名称排序
    private var sortedMapKeys: [ToolKeys] {
        mapKeys.sorted { $0.company < $1.company }
    }
    
    var body: some View {
        
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置地图功能，以便在与支持工具的模型对话时，更好的获取位置相关的信息并让模型向你展示地图"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            }
            
            Section {
                Toggle(String(localized: "启用地图"), isOn: Binding(
                    get: { mapEnable },
                    set: { mapEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "地图引擎选择（最多只能开启一个）"))) {
                ForEach(sortedMapKeys) { key in
                    HStack {
                        // 左侧区域：点击可进入 API 配置界面（APPLEMAPP 不可配置 API）
                        Button {
                            if key.company.uppercased() != "APPLEMAP" {
                                selectedMapKey = key
                            }
                        } label: {
                            HStack {
                                Image(getCompanyIcon(for: key.company))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                Text(getCompanyName(for: key.company))
                                    .foregroundColor(.primary)
                                Spacer()
                                // 对于默认的 APPLEMAP，显示"默认"标识
                                if key.company.uppercased() == "APPLEMAP" {
                                    Text(String(localized: "默认"))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    Image(systemName: "key")
                                        .foregroundColor(.hlBluefont)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 右侧区域：切换启用状态（仅一个引擎能启用）
                        if loadingMapCompany == key.company {
                            ProgressView()
                        } else {
                            Toggle("", isOn: Binding(
                                get: { key.isUsing },
                                set: { newValue in
                                    toggleMapEngine(for: key, newValue: newValue)
                                }
                            ))
                            .labelsHidden()
                            .tint(.hlBlue)
                        }
                    }
                }
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "用户定位查询"), systemImage: "location")
                Label(String(localized: "特定位置搜索"), systemImage: "mappin.and.ellipse")
                Label(String(localized: "附近兴趣搜索"), systemImage: "mecca")
                Label(String(localized: "自动路线规划"), systemImage: "point.bottomleft.forward.to.point.topright.filled.scurvepath")
            }
        }
        .navigationTitle(String(localized: "地图规划"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
        // 弹出编辑 API 配置界面
        .sheet(item: $selectedMapKey) { key in
            editMapKeyView(for: key)
        }
        .alert(errorMessage, isPresented: $showError) {
            Button(String(localized: "确定"), role: .cancel) { }
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.mapEnable = existingUser.useMap
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useMap = mapEnable
        } else {
            let newUser = UserInfo(
                useMap: mapEnable,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
    
    // 仅允许一个引擎启用；启用非 AppleMap 时需确保 API Key 已配置
    private func toggleMapEngine(for key: ToolKeys, newValue: Bool) {
        loadingMapCompany = key.company
        DispatchQueue.main.async {
            if newValue {
                // 对于非 AppleMap 必须配置 API Key 才能启用
                if key.company.uppercased() != "APPLEMAP" && key.key.isEmpty {
            errorMessage = String(format: String(localized: "%@ 需要配置 API Key 才能启用。"), getCompanyName(for: key.company))
                    showError = true
                    loadingMapCompany = nil
                    return
                }
                // 启用当前引擎，同时关闭其它引擎
                for engine in mapKeys {
                    engine.isUsing = (engine.id == key.id)
                }
            } else {
                // 禁用当前引擎
                key.isUsing = false
            }
            
            do {
                try modelContext.save()
            } catch {
            errorMessage = String(format: String(localized: "保存失败: %@"), error.localizedDescription)
                showError = true
            }
            ensureDefaultEngine()
            loadingMapCompany = nil
        }
    }
    
    /// 如果没有任何引擎被启用，就自动启用系统 AppleMap
    private func ensureDefaultEngine() {
        // 只在整体“启用地图”是开的情况下才做
        guard mapEnable else { return }
        // 如果一个都没被 isUsing
        if !mapKeys.contains(where: { $0.isUsing }) {
            if let apple = mapKeys.first(where: { $0.company.uppercased() == "APPLEMAP" }) {
                apple.isUsing = true
                do {
                    try modelContext.save()
                } catch {
                    print("默认启用 AppleMap 失败：\(error)")
                }
            }
        }
    }
    
    // MARK: 编辑 API 配置视图
    @ViewBuilder
    private func editMapKeyView(for key: ToolKeys) -> some View {
        NavigationView {
            Form {
                // APPLEMAP 无需配置 API
                if key.company.uppercased() == "APPLEMAP" {
                    Section {
                        Text(String(localized: "APPLEMAP 不需要配置 API Key"))
                            .foregroundColor(.gray)
                    }
                } else {
                    Section {
                        VStack(alignment: .center) {
                            Image(getCompanyIcon(for: key.company))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .padding()

                            Text("设置 \(getCompanyName(for: key.company)) API密钥，以开启该地图引擎")
                                .font(.footnote)
                                .multilineTextAlignment(.center)

                            if let url = URL(string: key.help) {
                            Link(String(format: String(localized: "🔗 点此获取 %@ API密钥"), getCompanyName(for: key.company)), destination: url)
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom)
                            } else {
                                // 当 URL 无效时可以提供一个备用视图
                                Text(String(localized: "建议进入其开放平台获取API密钥"))
                                    .font(.footnote)
                                    .multilineTextAlignment(.center)
                                    .padding(.bottom)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    
                    Section(header: Text(String(localized: "密钥"))) {
                        SecureField(String(localized: "请输入 API Key"), text: Binding(
                            get: { key.key },
                            set: { key.key = $0 }
                        ))
                    }
                }
            }
            .navigationTitle(String(localized: "编辑密钥"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        selectedMapKey = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        key.timestamp = Date()
                        try? modelContext.save()
                        selectedMapKey = nil
                    }
                }
            }
        }
    }
}


// MARK: - 日历配置界面
struct CalendarSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var calendarEnable: Bool = true
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置日历功能，以便在与支持工具的模型对话时，获取日历日程、提醒事项信息或者让模型写入日历日程、提醒事项"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section {
                Toggle(String(localized: "启用日历"), isOn: Binding(
                    get: { calendarEnable },
                    set: { calendarEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "查找日历事件"), systemImage: "calendar.badge.checkmark")
                Label(String(localized: "查找提醒事项"), systemImage: "checklist")
                Label(String(localized: "新增日历事件"), systemImage: "calendar.badge.plus")
                Label(String(localized: "新增提醒事项"), systemImage: "text.badge.plus")
            }
        }
        .navigationTitle(String(localized: "日历提醒"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.calendarEnable = existingUser.useCalendar
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useCalendar = calendarEnable
        } else {
            let newUser = UserInfo(
                useCalendar: calendarEnable,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 网页配置界面
struct CodeSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var CodeEnable: Bool = true
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "apple.terminal")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置代码功能，以便在与支持工具的模型对话时，模型为你运行Python代码，或查看模型为你制作网页内容，并与其交互。"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section {
                Toggle(String(localized: "启用代码"), isOn: Binding(
                    get: { CodeEnable },
                    set: { CodeEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "渲染网页内容"), systemImage: "macwindow.badge.plus")
                Label(String(localized: "运行程序代码"), systemImage: "apple.terminal")
            }
        }
        .navigationTitle(String(localized: "代码执行"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.CodeEnable = existingUser.useCode
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useCode = CodeEnable
        } else {
            let newUser = UserInfo(
                useCode: CodeEnable,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 健康配置界面
struct HealthSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var healthEnable: Bool = true
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "heart")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置健康功能，以便在与支持工具的模型对话时，模型能够获取你的健康信息或帮你记录健康、饮食等信息。"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section {
                Toggle(String(localized: "启用健康"), isOn: Binding(
                    get: { healthEnable },
                    set: { healthEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "查询步数距离"), systemImage: "figure.walk")
                Label(String(localized: "查询能量消耗"), systemImage: "flame")
                Label(String(localized: "查询营养摄入"), systemImage: "bubbles.and.sparkles")
                Label(String(localized: "写入营养摄入"), systemImage: "pencil.and.list.clipboard")
            }
        }
        .navigationTitle(String(localized: "健康生活"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.healthEnable = existingUser.useHealth
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useHealth = healthEnable
        } else {
            let newUser = UserInfo(
                useHealth: healthEnable,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 健康配置界面
struct CanvasSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var canvasEnable: Bool = true
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "pencil.and.outline")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置画布功能，以便在与支持工具的模型对话时，模型能够使用画布工具，带来更好的长文本、大段落或结构化内容的输出编辑体验。"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section {
                Toggle(String(localized: "启用画布"), isOn: Binding(
                    get: { canvasEnable },
                    set: { canvasEnable = $0 }))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "创建信息画布"), systemImage: "pencil.and.outline")
                Label(String(localized: "编辑画布内容"), systemImage: "pencil.and.scribble")
                Label(String(localized: "运行画布代码"), systemImage: "play.circle")
                Label(String(localized: "渲染画布网页"), systemImage: "macwindow")
            }
        }
        .navigationTitle(String(localized: "信息画布"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// 加载数据库中的用户信息
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.canvasEnable = existingUser.useCanvas
            }
        }
    }
    
    /// 保存当前设置到数据库
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.useCanvas = canvasEnable
        } else {
            let newUser = UserInfo(
                useCanvas: canvasEnable,
            )
            modelContext.insert(newUser)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: - 天气配置界面
struct WeatherSettingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo]                   // 从数据库获取用户信息
    // 查询 toolClass 为 "weather" 的 ToolKeys 数据
    @Query(filter: #Predicate<ToolKeys> { key in
        key.toolClass == "weather"
    })
    var weatherKeys: [ToolKeys]
    
    @State private var weatherEnable: Bool = true
    
    // 用于天气服务商配置相关状态
    @State private var selectedWeatherKey: ToolKeys?
    @State private var loadingWeatherCompany: String? = nil
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    // 对 weatherKeys 按公司名称排序
    private var sortedWeatherKeys: [ToolKeys] {
        weatherKeys.sorted { $0.company < $1.company }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "cloud.sun")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "设置天气功能，以便在与支持工具的模型对话时，获取实时天气信息和未来天气预报"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section {
                Toggle(String(localized: "启用天气"), isOn: Binding(
                    get: { weatherEnable },
                    set: { weatherEnable = $0 }
                ))
                .tint(.hlBlue)
            }
            
            Section(header: Text(String(localized: "天气服务商选择（最多只能开启一个）"))) {
                ForEach(sortedWeatherKeys) { key in
                    HStack {
                        // 点击进入 API 配置界面
                        Button {
                            selectedWeatherKey = key
                        } label: {
                            HStack {
                                Image(getCompanyIcon(for: key.company))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                                Text(getCompanyName(for: key.company))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "key")
                                    .foregroundColor(.hlBluefont)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 切换启用状态（仅一个服务商能启用）
                        if loadingWeatherCompany == key.company {
                            ProgressView()
                        } else {
                            Toggle("", isOn: Binding(
                                get: { key.isUsing },
                                set: { newValue in
                                    toggleWeatherService(for: key, newValue: newValue)
                                }
                            ))
                            .labelsHidden()
                            .tint(.hlBlue)
                        }
                    }
                }
            }
            
            Section(header: Text(String(localized: "功能列表"))) {
                Label(String(localized: "查询实时天气"), systemImage: "cloud.sun")
                Label(String(localized: "未来天气预报"), systemImage: "calendar")
            }
        }
        .navigationTitle(String(localized: "天气查询"))
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
        // 弹出编辑 API 配置界面
        .sheet(item: $selectedWeatherKey) { key in
            editWeatherKeyView(for: key)
        }
        .alert(errorMessage, isPresented: $showError) {
            Button(String(localized: "确定"), role: .cancel) { }
        }
    }
    
    // MARK: 加载/保存 用户的天气启用状态
    private func loadUserInfo() {
        if let existing = users.first {
            DispatchQueue.main.async {
                self.weatherEnable = existing.useWeather
            }
        }
    }
    
    private func saveUserInfo() {
        if let existing = users.first {
            existing.useWeather = weatherEnable
        } else {
            let newUser = UserInfo(useWeather: weatherEnable)
            modelContext.insert(newUser)
        }
        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
    
    /// 仅允许一个服务启用；启用时需确保 API Key 已配置
    private func toggleWeatherService(for key: ToolKeys, newValue: Bool) {
        loadingWeatherCompany = key.company
        DispatchQueue.main.async {
            if newValue {
                if key.key.isEmpty {
                    errorMessage = "\(getCompanyName(for: key.company)) 需要配置 API Key 才能启用。"
                    showError = true
                    loadingWeatherCompany = nil
                    return
                }
                if key.requestURL.isEmpty {
                    errorMessage = "\(getCompanyName(for: key.company)) 需要配置 API Host 才能启用。"
                    showError = true
                    loadingWeatherCompany = nil
                    return
                }
                for service in weatherKeys {
                    service.isUsing = (service.id == key.id)
                }
            } else {
                key.isUsing = false
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "保存失败: \(error.localizedDescription)"
                showError = true
            }
            loadingWeatherCompany = nil
        }
    }
    
    // MARK: 编辑 API 配置视图
    @ViewBuilder
    private func editWeatherKeyView(for key: ToolKeys) -> some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .center) {
                        Image(getCompanyIcon(for: key.company))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .padding()

                        Text("设置 \(getCompanyName(for: key.company)) API 密钥，以开启该天气服务")
                            .font(.footnote)
                            .multilineTextAlignment(.center)

                        if let url = URL(string: key.help) {
                            Link("🔗 点此获取 \(getCompanyName(for: key.company)) API 密钥", destination: url)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                        } else {
                            Text(String(localized: "建议进入其开放平台获取 API 密钥"))
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding(.bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                
                Section(header: Text(String(localized: "密钥"))) {
                    SecureField(String(localized: "请输入 API Key"), text: Binding(
                        get: { key.key },
                        set: { key.key = $0 }
                    ))
                }
                
                Section(header: Text(String(localized: "请求地址"))) {
                    TextField(String(localized: "请输入 API Host"), text: Binding(
                        get: { key.requestURL },
                        set: { key.requestURL = $0 }
                    ))
                }
            }
            .navigationTitle(String(localized: "编辑密钥"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        selectedWeatherKey = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        key.timestamp = Date()
                        try? modelContext.save()
                        selectedWeatherKey = nil
                    }
                }
            }
        }
    }
}
