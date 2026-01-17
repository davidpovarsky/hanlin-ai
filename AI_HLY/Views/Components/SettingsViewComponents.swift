//
//  SettingsViewComponents.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 11/2/25.
//

import SwiftUI
import SwiftData
import MarkdownUI
import Foundation
import MessageUI

// MARK: 用户信息界面
struct UserInfoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息

    @State private var name: String = ""
    @State private var userInfo: String = ""
    @State private var userRequirements: String = ""

    @State private var showToast = false
    @State private var showToastError = false

    var body: some View {
        Form {
            // MARK: 信息提示区
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "person")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text("设定个性化内容，使得模型在对话时了解你的需求与偏好，更好的进行回复。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            Section(header: Text("模型应该怎么称呼你？")) {
                TextField("请输入你的昵称", text: $name)
            }

            Section(header: Text("做一段自我介绍吧！")) {
                TextEditor(text: $userInfo)
                    .frame(height: 100)
            }

            Section(header: Text("模型需要注意什么？")) {
                TextEditor(text: $userRequirements)
                    .frame(height: 160)
            }

            Section(header: Text("注意：用户信息的设置会让模型的回复更符合你的习惯，但是会消耗更多的tokens。")) {
                Button("保存") {
                    saveUserInfo()
                }
            }
        }
        .navigationTitle("用户信息")
        .onAppear {
            loadUserInfo()
        }
        // 弹窗反馈
        .alert("保存成功", isPresented: $showToast) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("您的用户信息已成功更新。")
        }
        // 弹窗反馈
        .alert("保存失败", isPresented: $showToast) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("您的用户信息更新失败！")
        }
    }

    /// **加载数据库中的用户信息**
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.name = existingUser.name ?? ""
                self.userInfo = existingUser.userInfo ?? ""
                self.userRequirements = existingUser.userRequirements ?? ""
            }
        }
    }

    /// **保存用户信息**
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.name = name
            existingUser.userInfo = userInfo
            existingUser.userRequirements = userRequirements
            existingUser.timestamp = Date()
        } else {
            let newUser = UserInfo(name: name, userInfo: userInfo, userRequirements: userRequirements, timestamp: Date())
            modelContext.insert(newUser)
        }

        do {
            try modelContext.save()
            showToast = true
        } catch {
            showToastError = true
        }
    }
}

// MARK: 反馈设置界面
struct FeedBackView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [UserInfo] // 从数据库获取用户信息
    
    @State private var outPutFeedBack: Bool = true

    var body: some View {
        Form {
            Section {
                Toggle("文本内容生成反馈", isOn: Binding(
                    get: { outPutFeedBack },
                    set: { outPutFeedBack = $0 }))
                .tint(.hlBlue)
            }
        }
        .navigationTitle("触感反馈")
        .onAppear {
            loadUserInfo()
        }
        .onDisappear {
            saveUserInfo()
        }
    }
    
    /// **加载数据库中的用户信息**
    private func loadUserInfo() {
        if let existingUser = users.first {
            DispatchQueue.main.async {
                self.outPutFeedBack = existingUser.outPutFeedBack
            }
        }
    }
    
    private func saveUserInfo() {
        if let existingUser = users.first {
            existingUser.outPutFeedBack = outPutFeedBack
        } else {
            let newUser = UserInfo(outPutFeedBack: outPutFeedBack)
            modelContext.insert(newUser)
        }

        do {
            try modelContext.save()
        } catch {
            print("保存失败：\(error.localizedDescription)")
        }
    }
}

// MARK: 软件信息界面
struct VersionInfoView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.hlBlue.opacity(0.2), Color.hlPurple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                
                Spacer()
                
                Image("applogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .cornerRadius(20)
                    
                Text("AI翰林院")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.primary)
                
                Text("版本：\(getAppVersion())")
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Divider()
                    .frame(width: 200)
                    .background(Color.gray.opacity(0.5))
                
                Text("软件含有AI生成信息，请注意鉴别")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("本软件对生成结果不负有任何责任")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("感谢您使用 AI 翰林院")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                VStack(spacing: 8) {
                    Text("2025年2月·新加坡")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("© 2025 HLY 保留所有权利")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("软件信息")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// 获取 App 版本号
    private func getAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }
}

// 选择向量模型
struct SelectEmbeddingModelView: View {
    // 查询用户信息记录（假设只有一个用户记录）
    @Query var userInfos: [UserInfo]
    // 查询 APIKeys 记录
    @Query var apiKeys: [APIKeys]
    @Environment(\.modelContext) private var modelContext
    
    // 获取支持的向量模型列表
    private var models: [EmbeddingModel] {
        getEmbeddingModelList()
    }
    
    @State private var loadingModel: String? = nil
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "compass.drawing")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text("向量模型将被用于知识背包文档索引的构建与知识背包查找功能，优秀的向量模型能带来精确、全面的查找效果，提高信息的召回率。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Section(header: Text("选择向量模型（仅启用一个）")) {
                ForEach(models, id: \.name) { model in
                    HStack {
                        
                        Image(getCompanyIcon(for: model.company))
                            .resizable()
                            .frame(width: 24, height: 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(model.displayName)
                                .font(.body)
                        }
                        
                        Spacer()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            if model.price > 0 {
                                Text("¥\(String(format: "%.4f", model.price))/Ktokens")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("免费")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(width: 50)
                        
                        if loadingModel == model.name {
                            ProgressView()
                        } else {
                            Toggle("", isOn: Binding(
                                get: {
                                    // 如果用户信息中的 chooseEmbeddingModel 等于当前模型名称，则为启用状态
                                    userInfos.first?.chooseEmbeddingModel == model.name
                                },
                                set: { newValue in
                                    toggleModel(model: model, newValue: newValue)
                                }
                            ))
                            .labelsHidden()
                            .tint(.hlBlue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("向量模型")
        .alert(errorMessage, isPresented: $showError) {
            Button("确定", role: .cancel) { }
        }
    }
    
    /// 切换当前向量模型启用状态，仅允许启用一个模型，并检查对应 APIKeys 是否配置有效 key
    private func toggleModel(model: EmbeddingModel, newValue: Bool) {
        loadingModel = model.name
        
        DispatchQueue.main.async {
            guard let user = userInfos.first else {
                errorMessage = "未找到用户信息"
                showError = true
                loadingModel = nil
                return
            }
            
            if newValue {
                // 检查对应厂商的 APIKeys 配置
                if let keyRecord = apiKeys.first(where: { $0.company == model.company }) {
                    if keyRecord.key?.isEmpty ?? true {
                        errorMessage = "\(model.displayName) 需要配置 API Key 才能启用。"
                        showError = true
                        loadingModel = nil
                        return
                    }
                } else {
                    errorMessage = "\(model.displayName) 需要配置 API Key 才能启用。"
                    showError = true
                    loadingModel = nil
                    return
                }
                // 启用当前模型
                user.chooseEmbeddingModel = model.name
            } else {
                if let defaultModel = models.first {
                    user.chooseEmbeddingModel = defaultModel.name
                }
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "保存失败: \(error.localizedDescription)"
                showError = true
            }
            loadingModel = nil
        }
    }
}

/// 选择语音模型界面
struct SelectTTSModelView: View {
    // 查询用户信息记录（假设只有一条 UserInfo 记录）
    @Query var userInfos: [UserInfo]
    // 查询 APIKeys 记录
    @Query var apiKeys: [APIKeys]
    @Environment(\.modelContext) private var modelContext
    
    // 获取支持的语音模型列表
    private var models: [EmbeddingModel] {
        getTTSModelList()
    }
    
    @State private var loadingModel: String? = nil
    @State private var errorMessage: String = ""
    @State private var showError: Bool = false
    
    var body: some View {
        List {
            // 顶部说明区域
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text("语音模型将用于合成语音。选择 Siri 模型可使用本地合成，而选择大模型合成将通过 API 请求生成语音，后者需要配置有效的 API Key。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            // 列表选择区域
            Section(header: Text("选择语音模型（仅启用一个）")) {
                ForEach(models, id: \.name) { model in
                    HStack {
                        
                        Image(getCompanyIcon(for: model.company))
                            .resizable()
                            .frame(width: 24, height: 24)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(model.displayName)
                                .font(.body)
                        }
                        
                        Spacer()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            if model.price > 0 {
                                Text("¥\(String(format: "%.4f", model.price))/分钟")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("免费")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(width: 50)
                        
                        if loadingModel == model.name {
                            ProgressView()
                        } else {
                            Toggle("", isOn: Binding(
                                get: {
                                    // 如果用户信息中的 textToSpeechModel 与当前模型名称匹配则视为启用状态
                                    userInfos.first?.textToSpeechModel == model.name
                                },
                                set: { newValue in
                                    toggleModel(model: model, newValue: newValue)
                                }
                            ))
                            .labelsHidden()
                            .tint(.hlBlue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("语音模型")
        .alert(errorMessage, isPresented: $showError) {
            Button("确定", role: .cancel) { }
        }
    }
    
    /// 切换当前语音模型启用状态，仅允许启用一个模型
    private func toggleModel(model: EmbeddingModel, newValue: Bool) {
        loadingModel = model.name
        
        DispatchQueue.main.async {
            guard let user = userInfos.first else {
                errorMessage = "未找到用户信息"
                showError = true
                loadingModel = nil
                return
            }
            
            if newValue {
                // 如果选择的是非 Siri 模型，则检查对应厂商 APIKeys 的配置
                if model.name.lowercased() != "siri" {
                    if let keyRecord = apiKeys.first(where: { $0.company == model.company }) {
                        if keyRecord.key?.isEmpty ?? true {
                            errorMessage = "\(model.displayName) 需要配置 API Key 才能启用。"
                            showError = true
                            loadingModel = nil
                            return
                        }
                    } else {
                        errorMessage = "\(model.displayName) 需要配置 API Key 才能启用。"
                        showError = true
                        loadingModel = nil
                        return
                    }
                }
                // 保存选择
                user.textToSpeechModel = model.name
            } else {
                if let defaultModel = models.first {
                    user.textToSpeechModel = defaultModel.name
                }
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "保存失败: \(error.localizedDescription)"
                showError = true
            }
            loadingModel = nil
        }
    }
}


// MARK: 更新信息界面
struct UpdateNote: Identifiable, Codable {
    var id = UUID()
    let version: String
    let releaseDate: String
    let content: String

    // 指定只解码 version、releaseDate、content 三个字段，忽略 id
    private enum CodingKeys: String, CodingKey {
        case version, releaseDate, content
    }
}

struct UpdateNotesView: View {
    
    @State private var updateNotes: [UpdateNote] = []
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.hlBlue.opacity(0.2), Color.hlPurple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(updateNotes) { note in
                        UpdateNoteCard(note: note)
                    }
                }
                .padding(.horizontal, 5)
            }
        }
        .navigationTitle("更新说明")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadUpdateNotes()
        }
    }
    
    // 解析 JSON 文件
    func loadUpdateNotes() {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        let languageKey = currentLanguage.hasPrefix("zh") ? "zh-Hans" : "en"
        
        // 读取 JSON 数据
        if let url = Bundle.main.url(forResource: "UpdateNotes", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let jsonResult = try JSONDecoder().decode([String: [UpdateNote]].self, from: data)
                updateNotes = jsonResult[languageKey] ?? []
            } catch {
                print("JSON 解析失败：\(error)")
            }
        }
    }
}

struct UpdateNoteCard: View {
    let note: UpdateNote
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { // 确保 VStack 内部左对齐
            Text(note.version)
                .font(.title3)
                .bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading) // 强制左对齐

            Text(note.releaseDate)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading) // 强制左对齐

            Markdown(note.content)
                .foregroundColor(.primary)
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading) // Markdown 文字左对齐
        }
        .padding()
        .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
        .background(.thinMaterial)
        .background(.background.opacity(0.2))
        .cornerRadius(20)
    }
}

// MARK: 软件介绍界面
// 数据模型
struct SoftwareSection: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}

struct SoftwareIntroView: View {
    
    let sections: [SoftwareSection] = [
        SoftwareSection(
            title: String(localized: "core_features_title"),
            content: String(localized: "core_features_content")
        )
    ]
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [Color.hlBlue.opacity(0.2), Color.hlPurple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // 软件 Logo & 标题
                    headerView()
                    
                    Divider()
                        .frame(width: 200)
                        .padding()
                    
                    // 主要内容部分
                    ForEach(sections) { section in
                        sectionCard(for: section)
                    }
                    
                    Divider()
                        .frame(width: 200)
                        .padding()
                    
                    // 加入内测
                    betaInvitationView()
                }
                .padding()
            }
        }
        .navigationTitle("软件介绍")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// **软件 Logo & 标题**
    @ViewBuilder
    private func headerView() -> some View {
        VStack(spacing: 8) {
            HStack {
                Image("applogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 45, height: 45)
                    .cornerRadius(20)
                    
                Text("AI翰林院")
                    .font(.largeTitle)
                    .bold()
            }
            
            Text("开启智能生活的次世代AI工作台")
                .font(.subheadline)
        }
        .padding(.top, 30)
    }
    
    /// **软件介绍的内容卡片**
    @ViewBuilder
    private func sectionCard(for section: SoftwareSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(section.title)
                .font(.headline)
                .bold()
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Markdown(section.content)
                .foregroundColor(.primary)
                .padding(.top, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: UIScreen.main.bounds.width * 0.9, alignment: .leading)
        .background(.thinMaterial)
        .background(.background.opacity(0.2))
        .cornerRadius(20)
    }
    
    /// **加入内测部分**
    @ViewBuilder
    private func betaInvitationView() -> some View {
        VStack(spacing: 10) {
            Text("「群智秒启，AI随行」")
                .font(.title3)
                .bold()
                .padding(.vertical)
            
            Text("百位AI翰林待诏候旨，作为智能时代的掌玺者，您将在21世纪最澎湃的算力浪潮中，见证思维内阁呈递的万方策论。而你，21世纪最富期待的科技革命的亲历者，AI翰林院诚邀您检阅百模智囊团，在史无前例的认知盛宴中，谱写您那属于数字时代的新华章！")
                .font(.body)
                .multilineTextAlignment(.leading)
        }
        .padding(.bottom, 40)
    }
}

// 联系我们
struct ContactUsView: View {
    
    @State private var showMailCompose = false
    @State private var saveSuccess = false
    @State private var showSaveAlert = false
    @State private var showCopyAlert = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil

    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                gradient: Gradient(colors: [Color.hlBlue.opacity(0.2), Color.hlPurple.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                
                Spacer()
                
                Image("applogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(20)
                
                Text("如果您有任何问题或建议，可以通过邮件联系我们。此外，我们有一个微信社群，如果您感兴趣您可以邮件联系我，我将邀请您加入社群。")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Divider()
                    .frame(width: 200)
                    .background(Color.gray.opacity(0.5))
                
                HStack {
                    Text(verbatim: "ai.hanlin@outlook.com")
                        .font(.caption)
                        .foregroundColor(.hlBluefont)
                        .contextMenu {
                            Button(action: copyEmailToClipboard) {
                                Label("复制", systemImage: "doc.on.doc")
                            }
                        }
                }
                .padding(.top, 10)
                
                // 发送邮件按钮
                Button(action: {
                    if MFMailComposeViewController.canSendMail() {
                        showMailCompose = true
                    } else {
                        print("无法发送邮件，请检查您的邮件配置")
                    }
                }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                        Text("发送邮件")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 250)
                    .background(Color.hlBlue)
                    .cornerRadius(20)
                }
                .sheet(isPresented: $showMailCompose) {
                    MailView(result: $mailResult)
                }
                
                Spacer()
            }
            .padding()
            .alert(isPresented: $showCopyAlert) {
                Alert(title: Text("已复制"), message: Text("邮箱已复制到剪贴板"), dismissButton: .default(Text("确定")))
            }
        }
        .navigationTitle("联系我们")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    /// 保存二维码到相册
    private func saveQRCodeToAlbum() {
        guard let qrImage = UIImage(named: "community_qr") else {
            saveSuccess = false
            showSaveAlert = true
            return
        }
        
        UIImageWriteToSavedPhotosAlbum(qrImage, nil, nil, nil)
        saveSuccess = true
        showSaveAlert = true
    }
    
    private func copyEmailToClipboard() {
        UIPasteboard.general.string = "ai.hanlin@outlook.com"
        showCopyAlert = true
    }
}

/// **邮件发送视图**
struct MailView: UIViewControllerRepresentable {
    @Binding var result: Result<MFMailComposeResult, Error>?
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var parent: MailView
        
        init(parent: MailView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error = error {
                parent.result = .failure(error)
            } else {
                parent.result = .success(result)
            }
            controller.dismiss(animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(["ai.hanlin@outlook.com"]) // 客服邮箱
        
        // 获取当前设备语言
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        let isChinese = currentLanguage.contains("zh")
        
        // **主题自动适配**
        let subject = isChinese ? "用户反馈（\(getCurrentDate())）" : "User Feedback (\(getCurrentDate()))"
        vc.setSubject(subject)
        
        // **正文自动适配**
        let emailBody = isChinese ? """
            问题描述或建议描述：
            
            \(getCursorPlaceholder())
            
            ---
            设备信息：
            - iOS 版本：\(UIDevice.current.systemVersion)
            - 设备型号：\(getDeviceModel())
            - App 版本：\(getAppVersion())
            """ : """
            Issue description or suggestions:
            
            \(getCursorPlaceholder())
            
            ---
            Device Info:
            - iOS Version: \(UIDevice.current.systemVersion)
            - Device Model: \(getDeviceModel())
            - App Version: \(getAppVersion())
            """
        
        vc.setMessageBody(emailBody, isHTML: false)
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    /// 获取当前日期（格式：YYYY-MM-DD）
    private func getCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    /// 获取设备型号
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.compactMap { element in
            element.value as? Int8
        }
            .filter { $0 != 0 }
            .map { String(UnicodeScalar(UInt8($0))) }
            .joined()
        return identifier
    }
    
    /// 获取 App 版本号
    private func getAppVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "Unknown"
    }
    
    /// 让光标定位到合适的位置
    private func getCursorPlaceholder() -> String {
        return "\u{200B}" // 零宽空格，邮件打开时光标会自动定位到这里
    }
}

// 优化模型选择
struct SelectOptimizationModelView: View {
    @Environment(\.modelContext) private var modelContext
    
    // 查询所有基础模型
    @Query private var allModels: [AllModels]
    // 查询所有 APIKeys
    @Query private var allAPIKeys: [APIKeys]
    
    @State private var selectedTextModel: AllModels?
    @State private var selectedVisualModel: AllModels?
    
    // 控制保存成功弹窗
    @State private var showSaveSuccessAlert = false
    @State private var showSaveErrorAlert = false
    
    // 判断某个模型对应的公司是否存在有效的 APIKey
    private func hasValidAPIKey(for model: AllModels) -> Bool {
        guard let company = model.company, !company.isEmpty else { return false }
        return allAPIKeys.first(where: { ($0.company ?? "") == company && !($0.key?.isEmpty ?? true) }) != nil
    }
    
    // 过滤出符合文本优化要求的模型
    private var textOptimizationModels: [AllModels] {
        allModels.filter {
            ($0.identity == "model") &&
            ($0.company != "LOCAL") &&
            ($0.supportsTextGen == true) &&
            hasValidAPIKey(for: $0)
        }
    }

    // 过滤出符合视觉优化要求的模型
    private var visualOptimizationModels: [AllModels] {
        allModels.filter {
            ($0.identity == "model") &&
            ($0.supportsMultimodal == true) &&
            ($0.supportsTextGen == true) &&
            ($0.company != "LOCAL") &&
            hasValidAPIKey(for: $0)
        }
    }
    
    var body: some View {
        Form {
            Section(header: Text("文本优化模型")) {
                
                VStack(alignment: .center) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text("文本优化模型将被广泛用于软件的提示词优化、文章内容优化、联网搜索提问优化、知识背包检索优化、图片生成提示词优化、自动生成群聊标题、自动生成智能体设定、翻译文本等功能上，优秀的文本优化模型能带来更好的产品体验。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                Picker("选择文本优化模型", selection: $selectedTextModel) {
                    ForEach(textOptimizationModels, id: \.id) { model in
                        Text(model.displayName ?? "Unknown")
                            .tag(model as AllModels?)
                    }
                }
                
                if let model = selectedTextModel {
                    HStack {
                        Image(getCompanyIcon(for: model.company ?? "UNKNOWN"))
                            .resizable()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(model.displayName ?? "Unknown")
                            }
                            HStack {
                                if model.supportsMultimodal {
                                    Text("视觉")
                                        .font(.caption)
                                        .foregroundColor(.teal)
                                } else {
                                    Text("文本")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Text(priceText(for: model.price))
                                    .font(.caption)
                                    .foregroundColor(priceColor(for: model.price))
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            
            Section(header: Text("视觉优化模型")) {
                VStack(alignment: .center) {
                    Image(systemName: "paintbrush")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text("视觉优化模型将被广泛用于软件的联网搜索提问优化、知识背包检索优化、图片生成提示词优化、OCR扫描文本、文本及推理模型分析图片等功能上，优秀的视觉优化模型能带来更好的产品体验。")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                Picker("选择视觉优化模型", selection: $selectedVisualModel) {
                    ForEach(visualOptimizationModels, id: \.id) { model in
                        Text(model.displayName ?? "Unknown")
                            .tag(model as AllModels?)
                    }
                }
                if let model = selectedVisualModel {
                    HStack {
                        Image(getCompanyIcon(for: model.company ?? "UNKNOWN"))
                            .resizable()
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(model.displayName ?? "Unknown")
                            }
                            HStack {
                                Text("视觉")
                                    .font(.caption)
                                    .foregroundColor(.teal)
                                
                                Text(priceText(for: model.price))
                                    .font(.caption)
                                    .foregroundColor(priceColor(for: model.price))
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
        .navigationTitle("优化模型")
        .onAppear {
            // 从 UserInfo 中加载已保存的模型名称，并在当前模型列表中查找对应模型
            if let user = try? modelContext.fetch(FetchDescriptor<UserInfo>()).first {
                if let textModel = textOptimizationModels.first(where: { $0.name == user.optimizationTextModel }) {
                    selectedTextModel = textModel
                }
                if let visualModel = visualOptimizationModels.first(where: { $0.name == user.optimizationVisualModel }) {
                    selectedVisualModel = visualModel
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    // 保存选择到 UserInfo 中
                    if let user = try? modelContext.fetch(FetchDescriptor<UserInfo>()).first {
                        user.optimizationTextModel = selectedTextModel?.name ?? user.optimizationTextModel
                        user.optimizationVisualModel = selectedVisualModel?.name ?? user.optimizationVisualModel
                        try? modelContext.save()
                        showSaveSuccessAlert = true
                    } else {
                        showSaveErrorAlert = true
                    }
                }
            }
        }
        // 弹窗反馈
        .alert("保存成功", isPresented: $showSaveSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("您的优化模型已成功更新。")
        }
        // 弹窗反馈
        .alert("保存失败", isPresented: $showSaveErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("您的优化模型更新失败！")
        }
    }
}
