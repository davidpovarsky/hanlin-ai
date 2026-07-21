//
//  SettingsView.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 10/2/25.
//

import SwiftUI
import SwiftData
import SafariServices

@MainActor
struct SettingsView: View {
    
    @State private var isPushed: Bool = false  // 监听是否进入子页面
    @State private var showSafariGuide: Bool = false
    @State private var showSafariCost: Bool = false
    @State private var nativeAssistantToolGroups: [NativeAssistantToolGroup] = []
    
    @Query var apiKeys: [APIKeys]
    @Query var searchKeys: [SearchKeys]
    @Query var userInfos: [UserInfo]
    
    var body: some View {
        
        let noAPIKeys = apiKeys
            .filter { $0.company != "LOCAL" }
            .allSatisfy { $0.isHidden || ($0.key?.isEmpty ?? true) }
        
        let noSearchKeys = searchKeys
            .allSatisfy { $0.key?.isEmpty ?? true }

        // 检测是否缺少优化模型
        let userInfo = userInfos.first
        let noOptimizationModel = (userInfo?.optimizationTextModel.isEmpty ?? true) ||
                                  (userInfo?.optimizationVisualModel.isEmpty ?? true)

        // 检测是否缺少向量模型
        let noEmbeddingModel = userInfo?.chooseEmbeddingModel?.isEmpty ?? true

        NavigationStack {
            List {
                Section(header: Text(String(localized: "个性化"))) {
                    NavigationLink(destination: UserInfoView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "用户信息"), systemImage: "person")
                    }
                    NavigationLink(destination: PromptRepoView().onAppear { isPushed = true }.onDisappear { isPushed = false}.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "提示词库"), systemImage: "tray.full")
                    }
                    NavigationLink(destination: MemoryArchiveView().onAppear { isPushed = true }.onDisappear { isPushed = false}.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "记忆档案"), systemImage: "archivebox")
                    }
                    NavigationLink(destination: TranslationDicView().onAppear { isPushed = true }.onDisappear { isPushed = false}.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "翻译词典"), systemImage: "character.book.closed")
                    }
                }
                if noAPIKeys {
                    Section {
                        Text(String(localized: "指引：暂无开启的大模型厂商，点击下方“模型”中的“模型密钥”设置大模型密钥和厂商的启用状态"))
                            .font(.caption)
                            .foregroundColor(.hlRed)
                    }
                }
                if noOptimizationModel {
                    Section {
                        Text(String(localized: "指引：点击下方“优化模型”设置文本优化模型和视觉优化模型，以启用提示词优化、系统消息优化、图片内容识别等功能"))
                            .font(.caption)
                            .foregroundColor(.hlRed)
                    }
                }
                if noEmbeddingModel {
                    Section {
                        Text(String(localized: "指引：点击下方“向量模型“设置向量嵌入模型，以启用知识背包检索功能"))
                            .font(.caption)
                            .foregroundColor(.hlRed)
                    }
                }
                Section(header: Text(String(localized: "模型"))) {
                    NavigationLink(destination: APIKeysView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "模型厂商"), systemImage: "key.2.on.ring")
                    }
                    NavigationLink(destination: SelectEmbeddingModelView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "向量模型"), systemImage: "compass.drawing")
                    }
                    NavigationLink(destination: SelectOptimizationModelView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "优化模型"), systemImage: "hammer")
                    }
                    NavigationLink(destination: SelectTTSModelView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "语音模型"), systemImage: "waveform")
                    }
                }
                if noSearchKeys {
                    Section {
                        Text(String(localized: "指引：点击下方“工具”中的“联网搜索”设置搜索引擎密钥和需要使用的搜索引擎"))
                            .font(.caption)
                            .foregroundColor(.hlRed)
                    }
                }
                Section(header: Text(String(localized: "工具"))) {
                    NavigationLink(destination: MCPServersSettingsView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(MCPL10n.string("MCP Servers"), systemImage: "server.rack")
                    }
                    NavigationLink(destination: RuntimeCenterView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(RuntimeL10n.string("Runtimes & Packages"), systemImage: "shippingbox.and.arrow.backward")
                    }
                    NavigationLink(destination: SearchSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "联网搜索"), systemImage: "magnifyingglass")
                    }
                    NavigationLink(destination: KnowledgeSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "知识背包"), systemImage: "backpack")
                    }
                    NavigationLink(destination: CanvasSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "信息画布"), systemImage: "pencil.and.outline")
                    }
                    NavigationLink(destination: MapSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "地图规划"), systemImage: "map")
                    }
                    NavigationLink(destination: WeatherSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "天气查询"), systemImage: "cloud.sun")
                    }
                    NavigationLink(destination: CalendarSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "日历提醒"), systemImage: "calendar")
                    }
                    NavigationLink(destination: HealthSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "健康生活"), systemImage: "heart")
                    }
                    NavigationLink(destination: CodeSettingView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "代码执行"), systemImage: "apple.terminal")
                    }
                    ForEach(nativeAssistantToolGroups) { group in
                        NavigationLink {
                            NativeAssistantToolGroupSettingsView(groupID: group.id)
                                .onAppear { isPushed = true }
                                .onDisappear { isPushed = false }
                                .toolbar(.hidden, for: .tabBar)
                        } label: {
                            Label(group.title, systemImage: group.systemImage)
                        }
                    }
                }
                Section(header: Text(String(localized: "通用"))) {
                    NavigationLink(destination: GeneralSettingsView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "通用"), systemImage: "gearshape")
                    }
                }
                Section(header: Text(String(localized: "Developer / Diagnostics"))) {
                    NavigationLink {
                        AgentDiagnosticsView()
                            .onAppear { isPushed = true }
                            .onDisappear { isPushed = false }
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        Label(String(localized: "Agent Diagnostics"), systemImage: "stethoscope")
                    }
                }
                Section(header: Text(String(localized: "帮助"))) {
                    Button(action: {
                        showSafariGuide = true
                    }) {
                        Label {
                            Text(String(localized: "软件指南"))
                                .foregroundColor(.primary)
                        } icon: {
                            Image(systemName: "text.rectangle.page")
                        }
                    }
                    Button(action: {
                        showSafariCost = true
                    }) {
                        Label {
                            Text(String(localized: "成本参考"))
                                .foregroundColor(.primary)
                        } icon: {
                            Image(systemName: "creditcard")
                        }
                    }
                }
                Section(header: Text(String(localized: "软件"))) {
                    NavigationLink(destination: SoftwareIntroView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "软件介绍"), systemImage: "text.book.closed")
                    }
                    NavigationLink(destination: UpdateNotesView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "更新说明"), systemImage: "newspaper")
                    }
                    NavigationLink(destination: VersionInfoView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "软件信息"), systemImage: "info.circle")
                    }
                    NavigationLink(destination: ContactUsView().onAppear { isPushed = true }.onDisappear { isPushed = false }.toolbar(.hidden, for: .tabBar)) {
                        Label(String(localized: "联系我们"), systemImage: "envelope")
                    }
                }
            }
            .navigationTitle(String(localized: "设置"))
            .onAppear {
                nativeAssistantToolGroups = NativeToolCatalog.shared.settingsGroups()
                NativeToolTraceLogger.shared.log(
                    "native_assistant_tool_groups_shown_in_settings",
                    [
                        "groupCount": nativeAssistantToolGroups.count,
                        "groupIDs": nativeAssistantToolGroups.map(\.id),
                        "toolsByGroup": nativeAssistantToolGroups.map {
                            "\($0.id):\($0.toolEntries.map(\.name).joined(separator: ","))"
                        },
                        "groupStates": nativeAssistantToolGroups.map {
                            "\($0.id):\(NativeToolCatalog.shared.isGroupEnabled($0))"
                        }
                    ]
                )
            }
            .onChange(of: isPushed) {
                NotificationCenter.default.post(name: .hideTabBar, object: isPushed)  // 发送通知，控制TabBar显示/隐藏
            }
            .safeAreaInset(edge: .bottom) { // 额外填充底部一个灰色区域
                Color(.clear)
                    .frame(height: 70)
            }
        }
        .fullScreenCover(isPresented: $showSafariGuide) {
            SafariView(url: URL(string: "https://docs.qq.com/aio/DT2pMUFRVWVNsZmtj")!)
                .background(BlurView(style: .systemThinMaterial))
                .edgesIgnoringSafeArea(.all)
        }
        .fullScreenCover(isPresented: $showSafariCost) {
            SafariView(url: URL(string: "https://docs.qq.com/smartsheet/DT3dzT1JlSFVvU05n?viewId=vUQPXH&tab=db_KULEGz")!)
                .background(BlurView(style: .systemThinMaterial))
                .edgesIgnoringSafeArea(.all)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        print("加载的 URL: \(url.absoluteString)") // 调试日志
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
