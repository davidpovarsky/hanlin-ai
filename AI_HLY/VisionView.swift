//
//  VisionView.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 12/2/25.
//

import SwiftUI
@preconcurrency import AVFoundation
@preconcurrency import Dispatch
import MarkdownUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct VisionView: View {
    @Binding var selectedTab: Int
    @StateObject private var cameraManager = CameraManager()
    @State private var capturedImage: UIImage? // 存储拍摄的照片
    @State private var followAsk = "" // 存储用户追问的文字
    @State private var currentAsk = ""
    @State private var showInput = false // 控制是否显示键盘
    @FocusState private var isInputActive: Bool // 控制是否显示键盘
    @State private var showModelSelection = false // 控制模型选择栏的显示
    @State private var selectedModelIndex = 0 // 选中的模型索引
    @State private var photoAnalysis: String? // 选中的模型索引
    @State private var currentModelName: String = "" // 当前输出模型
    @State private var currentModelCompany: String = "" // 当前输出模型
    @State private var currentModelIdentity: String = "" // 当前输出模型
    @State private var currentModelIcon: String = "" // 当前输出模型
    @State private var isProcessing = false // 是否正在处理
    @State private var isCopied = false // 是否已经复制
    @State private var isFeedBack = false // 是否需要震动
    @State private var isSelect = false // 是否需要震动
    @State private var isSuccess: Bool = false
    @State private var lastZoomFactor: CGFloat = 1.0 // 记录上次缩放值
    @State private var showImagePicker = false // 控制相册选择器
    @State private var isFlashOn = false
    @State private var isOutPut = false // 用于控制流式输出的振动
    @State private var lastUpdateTime = Date()
    let refreshInterval: TimeInterval = 0.1
    @State private var outPutFeedBackEnabled: Bool = true // 读取用户是否开启了振动反馈
    @State private var showSaveToast = false // 控制保存成功的提示
    @State private var isTextSelectionSheetPresented: Bool = false // 文本选择
    @State private var isCameraReady = false
    @State private var pulseEffect: Bool = false

    @State private var visionErrorMessage: String? = nil
    @State private var lastRequestImage: UIImage? = nil
    @State private var lastRequestFollowAsk: String = ""
    @State private var lastConversationContext: [(role: String, image: UIImage?, text: String?)] = []
    @State private var lastQueryKeyword: String = ""
    
    @State private var showNoModelAlert = false // 控制无多模态模型提示弹窗
    
    @State private var conversationContext: [(role: String, image: UIImage?, text: String?)] = [] //多轮对话管理
    
    // MARK: - 推理相关状态
    @State private var reasoning: String = ""              // 推理内容
    @State private var isReasoningExpanded: Bool = false   // 推理区域是否展开
    @State private var displayReasoningLines: [String] = [] // 收起时显示的最后3行
    
    @Environment(\.modelContext) private var context
    
    @Query var allModels: [AllModels] // 直接查询数据库
    
    // 动态获取模型
    private var multimodalModels: [(name: String, company: String, identity: String, icon: String)] {
        allModels
            .filter { $0.supportsMultimodal && !$0.isHidden } // 过滤 supportsMultimodal 为 true 且 isHidden 为 false
            .sorted { ($0.position ?? 0) < ($1.position ?? 0) }
            .map { ($0.displayName ?? "", $0.company ?? "", $0.identity ?? "", $0.icon ?? "circle.dotted.circle") }
    }
    
    var body: some View {
        ZStack {
            
            if showSaveToast {
                Text(String(localized: "✅ 图片已保存"))
                    .font(.body)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            VStack {
                topButtons
                
                // 当有正文内容或有推理内容时显示信息栏
                if photoAnalysis != nil || !reasoning.isEmpty || visionErrorMessage != nil {
                    topInfoBar
                        .animation(.easeInOut(duration: 0.4), value: showModelSelection)
                }
                Spacer()
                bottomControls
            }
        }
        .onAppear {
            // 检查是否有可用的多模态模型，没有则显示提示弹窗
            if multimodalModels.isEmpty {
                print("没有可用的多模态模型，显示提示弹窗")
                showNoModelAlert = true
                return
            }
            
            // 确保 selectedModelIndex 在有效范围内
            if selectedModelIndex >= multimodalModels.count {
                selectedModelIndex = 0
            }
            
            // 隐藏TabView
            NotificationCenter.default.post(name: .hideTabBar, object: true)
            
            DispatchQueue.global(qos: .userInitiated).async {
                cameraManager.startSession()
                outPutFeedBackEnabled = (try? context.fetch(FetchDescriptor<UserInfo>()).first?.outPutFeedBack) ?? true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isCameraReady = true
                }
            }
        }
        .onDisappear {
            // 显示TabView
            NotificationCenter.default.post(name: .hideTabBar, object: false)
            
            cameraManager.stopSession()
            isCameraReady = false
        }
        .background(
            ZStack {
                CameraPreview(session: cameraManager.session, showTorchBorder: isFlashOn && cameraManager.isUsingFrontCamera)
                    .ignoresSafeArea()
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .animation(.easeInOut(duration: 0.4), value: capturedImage) // 平滑切换
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let newZoom = lastZoomFactor * value
                                cameraManager.setZoomFactor(newZoom * 2)
                            }
                            .onEnded { _ in
                                lastZoomFactor = cameraManager.zoomFactor
                            }
                    )
                
                if let image = capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .animation(.easeInOut(duration: 0.4), value: capturedImage) // 添加动画
                }
            }
        )
        .alert(String(localized: "无法使用视觉功能"), isPresented: $showNoModelAlert) {
            Button(String(localized: "返回"), role: .cancel) {
                selectedTab = 0
            }
        } message: {
            Text(String(localized: "暂无启用的多模态模型，请前往“设置-模型-模型管理”添加并启用支持视觉的模型。"))
        }
    }
}

// MARK: - 组件封装
extension VisionView {
    /// 顶部按钮（返回 & 重新拍照）
    private var topButtons: some View {
        
        HStack {
            // 返回按钮
            Button(action: {
                clearData()
                selectedTab = 0
            }) {
                Image(systemName: "chevron.down.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .padding(3)
                    .foregroundColor(Color(.systemBackground))
                    .opacity(0.6)
                    .background(
                        GlassView(style: .systemUltraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: Color(.systemBackground), radius: 1)
                    )
            }
            
            Spacer()
            
            // 关闭按钮
            if capturedImage != nil {
                HStack (spacing: 10) {
                    Button(action: {
                        isFeedBack.toggle()
                        saveImageToPhotos()
                    }) {
                        Image(systemName: showSaveToast ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .foregroundColor(showSaveToast ? .hlGreen : Color(.systemBackground))
                            .opacity(0.6)
                            .background(
                                GlassView(style: .systemUltraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: showSaveToast ? .hlGreen : Color(.systemBackground), radius: 1)
                            )
                    }
                    .sensoryFeedback(.success, trigger: isFeedBack) // 振动反馈
                    
                    Button(action: {
                        isFeedBack.toggle()
                        clearData()
                        cameraManager.startSession()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .foregroundColor(.hlRed)
                            .opacity(0.6)
                            .background(
                                GlassView(style: .systemUltraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .hlRed, radius: 1)
                            )
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                }
            } else {
                HStack (spacing: 10) {
                    Button(action: {
                        isFeedBack.toggle()
                        toggleFlash()
                    }) {
                        Image(systemName: isFlashOn ? "flashlight.on.circle.fill" : "flashlight.off.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(3)
                            .foregroundColor(isFlashOn ? .hlOrange : Color(.systemBackground))
                            .opacity(0.6)
                            .background(
                                GlassView(style: .systemUltraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: isFlashOn ? .hlOrange : Color(.systemBackground), radius: 1)
                            )
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    
                    // 显示焦距按钮
                    Button(action: {
                        isSelect.toggle()
                        toggleZoom()
                    }) {
                        HStack {
                            Text(String(format: "%.1fx", cameraManager.zoomFactor))
                                .font(.caption)
                        }
                        .frame(width: 40, height: 30)
                        .font(.system(size: 30))
                        .padding(3)
                        .foregroundColor(.primary)
                        .opacity(0.6)
                        .background(
                            GlassView(style: .systemUltraThinMaterial)
                                .clipShape(Capsule())
                                .shadow(color: Color(.systemBackground), radius: 1)
                        )
                    }
                    .sensoryFeedback(.selection, trigger: isSelect)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func clearData() {
        capturedImage = nil
        followAsk = ""
        currentAsk = ""
        showInput = false
        showModelSelection = false
        photoAnalysis = nil
        visionErrorMessage = nil
        lastZoomFactor = 1.0
        showImagePicker = false
        conversationContext.removeAll()
        lastConversationContext.removeAll()
        lastRequestImage = nil
        lastRequestFollowAsk = ""
        lastQueryKeyword = ""
        // 重置推理相关状态
        reasoning = ""
        isReasoningExpanded = false
        displayReasoningLines = []
        cameraManager.startSession()
    }
    
    private func toggleZoom() {
        let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 5.0, 10.0] // 预设焦距等级
        if let currentIndex = zoomLevels.firstIndex(of: cameraManager.zoomFactor) {
            let nextIndex = (currentIndex + 1) % zoomLevels.count // 计算下一个索引（循环）
            cameraManager.setZoomFactor(zoomLevels[nextIndex] * 2) // 切换焦距
            lastZoomFactor = zoomLevels[nextIndex]
        } else {
            cameraManager.setZoomFactor(1.0 * 2) // 如果当前焦距异常，则重置为 1x
            lastZoomFactor = 1.0
        }
    }
    
    private func saveImageToPhotos() {
        guard let image = capturedImage else { return }

        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        // 触发 Toast 显示
        showSaveToast = true
        
        // 2 秒后自动隐藏
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSaveToast = false
        }
    }
    
    private func toggleFlash() {
        isFlashOn.toggle() // 切换状态
        cameraManager.setFlash(isFlashOn) // 让 CameraManager 控制闪光灯
    }
    
    // MARK: - 更新推理显示行（按句断句）
    private func updateDisplayReasoningLines() {
        // 按句号、问号、感叹号、分号、换行符等断句
        let sentences = reasoning
            .split(whereSeparator: { [".", "。", "!", "！", "?", "？", ";", "；", "\n"].contains(String($0)) })
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // 取最后 3 句
        let last3 = Array(sentences.suffix(3))
        // 不足 3 条时在前面补空
        if !last3.isEmpty && last3.count < 3 {
            displayReasoningLines = Array(repeating: " ", count: 3 - last3.count) + last3
        } else {
            displayReasoningLines = last3
        }
    }
    
    // MARK: - 推理过程视图
    @ViewBuilder
    private func visionReasoningView() -> some View {
        if !reasoning.isEmpty {
            VStack(alignment: .leading) {
                // 折叠按钮
                Button(action: {
                    withAnimation { isReasoningExpanded.toggle() }
                }) {
                    HStack {
                        Text(String(localized: "reasoning_chain"))
                            .font(.caption)
                            .foregroundColor(Color(.systemGray))
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color(.systemGray))
                            .rotationEffect(.degrees(isReasoningExpanded ? 180 : 0))
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 5)
                }
                
                if isReasoningExpanded {
                    // 展开：显示完整推理内容
                    Text(reasoning)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .transition(.opacity.combined(with: .scale))
                        .textSelection(.enabled)
                        .padding(.bottom, 5)
                } else {
                    // 收起 + 正在处理：显示最后3行滚动效果
                    if isProcessing {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(displayReasoningLines.enumerated()), id: \.offset) { idx, line in
                                Text(line)
                                    .id(String(line.prefix(1)))
                                    .font(.system(size: idx == 2 ? 10 : (idx == 1 ? 9 : 8)))
                                    .lineLimit(1)
                                    .truncationMode(.head)
                                    .foregroundColor(idx == 2 ? .hlBluefont : .gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .opacity(idx == 0 ? 0.4 : idx == 1 ? 0.7 : 1.0)
                                    .blur(radius: idx == 0 ? 1 : 0)
                                    .padding(.horizontal, 5)
                                    .transition(
                                        .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)
                                        )
                                    )
                            }
                        }
                        .padding(.bottom, 5)
                        .animation(
                            .spring(response: 0.8, dampingFraction: 0.95, blendDuration: 0.5),
                            value: displayReasoningLines
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private var visionErrorView: some View {
        return VStack(alignment: .leading) {
            Text(visionErrorMessage ?? "")
                .font(.caption)
                .foregroundColor(.hlOrange)
                .multilineTextAlignment(.leading)

            Button(action: {
                isFeedBack.toggle()
                retryLastRequest()
            }) {
                Text(String(localized: "重新请求"))
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.hlOrange)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
            .sensoryFeedback(.impact, trigger: isFeedBack)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.hlOrange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.hlOrange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(20)
    }
    
    // 顶部信息
    private var topInfoBar: some View {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        return ScrollViewReader { proxy in
            ScrollView (.vertical, showsIndicators: false) {
                if let errorMessage = visionErrorMessage, !errorMessage.isEmpty {
                    VStack {
                        if !currentAsk.isEmpty {
                            HStack {
                                Image(systemName: "pencil.line")
                                Text(currentAsk)
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundColor(Color(.systemGray))
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, 5)
                        }
                        visionErrorView
                    }
                    .id("bottom")
                    .padding()
                } else if reasoning.isEmpty && photoAnalysis == "" {
                    VStack {
                        if !currentAsk.isEmpty {
                            HStack {
                                Image(systemName: "pencil.line")
                                Text(currentAsk)
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundColor(Color(.systemGray))
                            .multilineTextAlignment(.leading)
                        }
                        HStack {
                            if currentModelIdentity == "agent" {
                                Image(systemName: currentModelIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                    .overlay(
                                        Group {
                                            gradient(for: 0)
                                                .mask(
                                                    Image(systemName: currentModelIcon)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(width: 20, height: 20)
                                                )
                                        }
                                    )
                            } else {
                                Image(getCompanyIcon(for: currentModelCompany))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            }
                            
                            Text("\(currentModelName)")
                                .font(.body)
                            ProgressView()
                                .frame(width: 20, height: 20)
                        }
                        .id("bottom")
                    }
                    .padding()
                    
                } else {
                    // 有推理内容或有正文内容时显示
                    
                    VStack {
                        if !currentAsk.isEmpty {
                            HStack {
                                Image(systemName: "pencil.line")
                                Text(currentAsk)
                                Spacer()
                            }
                            .font(.caption)
                            .foregroundColor(Color(.systemGray))
                            .multilineTextAlignment(.leading)
                            .padding(.bottom, 5)
                        }
                        
                        // 推理过程展示区
                        visionReasoningView()
                        
                        // 正文内容区域
                        if let analysis = photoAnalysis, !analysis.isEmpty {
                            Markdown(analysis)
                                .font(.body)
                                .multilineTextAlignment(.leading) // 文本左对齐
                                .fixedSize(horizontal: false, vertical: true) // 允许文本高度自适应
                                .sensoryFeedback(.increase, trigger: isOutPut)
                        } else if isProcessing && !reasoning.isEmpty {
                            // 正在思考中，还没有正文内容
                            HStack {
                                Image(systemName: "sparkle")
                                    .foregroundColor(.hlBluefont)
                                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous))
                                Text(String(localized: "thinking"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 5)
                        }
                        
                        if !isProcessing {
                            HStack {
                                if currentModelIdentity == "agent" {
                                    Image(systemName: currentModelIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .clipShape(Circle())
                                        .overlay(
                                            Group {
                                                gradient(for: 0)
                                                    .mask(
                                                        Image(systemName: currentModelIcon)
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 20, height: 20)
                                                    )
                                            }
                                        )
                                    Text("内容由代理“\(currentModelName)”生成")
                                } else {
                                    Image(getCompanyIcon(for: currentModelCompany))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                    Text("内容由AI模型“\(currentModelName)”生成")
                                }
                                
                                Spacer()
                                
                                // 选择文本按钮
                                Button(action: {
                                    isTextSelectionSheetPresented = true
                                }) {
                                    Image(systemName: "text.redaction")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14, height: 14)
                                        .padding(5)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .foregroundColor(.primary)
                                }
                                .buttonStyle(.plain)
                                .sheet(isPresented: $isTextSelectionSheetPresented) {
            TextSelectionView(text: photoAnalysis ?? String(localized: "无文本"))
                                }
                                
                                // 复制按钮
                                Button(action: {
                                    isSuccess.toggle()
                                    UIPasteboard.general.string = photoAnalysis
                                    isCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        isCopied = false
                                    }
                                }) {
                                    Image(systemName: isCopied ? "checkmark.circle.fill" : "square.on.square")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 14, height: 14)
                                        .padding(5)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .foregroundColor(isCopied ? .green : .primary)
                                }
                                .sensoryFeedback(.success, trigger: isSuccess)
                                
                                // 继续对话按钮
                                Button(action: {
                                    isSelect.toggle()
                                    showInput = true
                                    isInputActive = true
                                }) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 16, height: 16)
                                        .padding(4)
                                        .background(Color(.systemGray5))
                                        .clipShape(Circle())
                                        .foregroundColor(isInputActive ? .green : .hlBluefont)
                                }
                                .sensoryFeedback(.selection, trigger: isSelect)
                            }
                            .font(.caption)
                            .foregroundColor(Color(.systemGray))
                            .multilineTextAlignment(.leading)
                        }
                    }
                    .id("bottom")
                    .padding()
                }
            }
            .frame(maxWidth: screenWidth * 0.9)
            .background(Color(.systemBackground))
            .opacity(0.7)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(maxHeight: screenHeight * 0.35, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .padding(6)
            .onChange(of: photoAnalysis) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: visionErrorMessage) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: reasoning) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(
            GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .shadow(color: Color(.systemBackground), radius: 1)
        )
        .background(
            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                let timeInterval = timeline.date.timeIntervalSinceReferenceDate
                let hueValue = (timeInterval.truncatingRemainder(dividingBy: 12)) / 12
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hue: hueValue, saturation: 1, brightness: 1),
                        Color(hue: (hueValue + 0.3).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1),
                        Color(hue: (hueValue + 0.6).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1),
                        Color(hue: (hueValue + 0.9).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .opacity(pulseEffect ? 0.7 : 0.3) // 呼吸灯透明度变化
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: pulseEffect)
            }
        )
        .onAppear {
            pulseEffect = true // 触发动画
        }
        .padding(.horizontal)
        .padding(.top, 5)
    }
    
    /// 底部拍照按钮 & 轮播选择
    private var bottomControls: some View {
        
        HStack {
            if showInput {
                HStack {
                    TextField(String(localized: "消息"), text: $followAsk)
                        .padding(.leading, 12)
                        .frame(height: 44)
                        .focused($isInputActive) // 绑定焦点状态
                        .submitLabel(.send)
                        .onSubmit {
                            isFeedBack.toggle()
                            sendImageToAPI()
                            currentAsk = followAsk
                            followAsk = ""
                            isInputActive = false
                        }
                        .disabled(isProcessing)
                        .background(Color(.systemBackground))
                        .cornerRadius(20)
                        .padding(.vertical, 6)
                        .padding(.leading, 6)
                        .opacity(0.7)
                    
                    Button(action: {
                        if isProcessing {
                            
                        } else {
                            isFeedBack.toggle()
                            sendImageToAPI()
                            currentAsk = followAsk
                            followAsk = ""
                            isInputActive = false
                        }
                    }) {
                        Image(systemName: "arrowtriangle.up.circle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(isProcessing ? .gray : Color(.systemBackground))
                            .symbolEffect(.breathe, isActive: isProcessing)
                    }
                    .disabled( followAsk.isEmpty || isProcessing)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isProcessing)
                    .padding(.vertical, 6)
                    .padding(.trailing, 6)
                    .opacity(0.7)
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                }
                .background(
                    GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .shadow(color: Color(.systemBackground), radius: 1)
                )
                
            } else {
                
                Spacer()
                
                if showModelSelection {
                    modelCarouselView
                        .transition(.move(edge: .leading))
                        .animation(.easeInOut(duration: 0.3), value: showModelSelection)
                    Spacer()
                }
                
                if capturedImage == nil {
                    Button(action: {
                        isFeedBack.toggle()
                        showImagePicker = true
                    }) {
                        Image(systemName: "photo.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 45, height: 45)
                            .padding(6)
                            .opacity(0.6)
                            .foregroundColor(Color(.systemBackground))
                            .background(
                                GlassView(style: .systemUltraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: Color(.systemBackground), radius: 1)
                            )
                    }
                    .animation(.easeInOut(duration: 0.3), value: capturedImage)
                    .sheet(isPresented: $showImagePicker) {
                        VisionImagePicker(selectedImage: $capturedImage, showModelSelection: $showModelSelection)
                            .ignoresSafeArea()
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    Spacer()
                }
                
                Button(action: {
                    isFeedBack.toggle()
                    if capturedImage == nil {
                        cameraManager.capturePhoto { image in
                            withAnimation {
                                capturedImage = image
                                showModelSelection = true // 显示模型选择轮播盘
                            }
                        }
                    } else {
                        sendImageToAPI()
                    }
                }) {
                    Image(systemName: capturedImage != nil ? "arrowtriangle.up.circle.fill" : "circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .padding(6)
                        .opacity(0.7)
                        .foregroundColor(Color(.systemBackground))
                        .symbolEffect(.pulse.byLayer, options: .repeat(.continuous), isActive: capturedImage != nil && !isProcessing)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))
                        .background(
                            GlassView(style: .systemUltraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: Color(.systemBackground), radius: 1)
                        )
                        .background(
                            TimelineView(.animation(minimumInterval: 0.05)) { timeline in
                                let timeInterval = timeline.date.timeIntervalSinceReferenceDate
                                let hueValue = (timeInterval.truncatingRemainder(dividingBy: 12)) / 12

                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(hue: hueValue, saturation: 1, brightness: 1),
                                                Color(hue: (hueValue + 0.3).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1),
                                                Color(hue: (hueValue + 0.6).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1),
                                                Color(hue: (hueValue + 0.9).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .opacity(pulseEffect ? 0.8 : 0.4) // 呼吸灯透明度变化
                                    .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: pulseEffect)
                            }
                        )
                        .onAppear {
                            pulseEffect = true // 触发动画
                        }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: capturedImage)
                .sensoryFeedback(.impact, trigger: isFeedBack)
                
                Spacer()
                
                if capturedImage == nil {
                    Button(action: {
                        isFeedBack.toggle()
                        if isFlashOn {
                            toggleFlash()
                        }
                        cameraManager.switchCamera()
                    }) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 45, height: 45)
                            .padding(6)
                            .opacity(0.6)
                            .foregroundColor(Color(.systemBackground))
                            .background(
                                GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                                    .clipShape(Circle())
                                    .shadow(color: Color(.systemBackground), radius: 1)
                            )
                    }
                    .animation(.easeInOut(duration: 0.3), value: capturedImage)
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func sendImageToAPI(useLastRequest: Bool = false) {

        guard let image = useLastRequest ? (lastRequestImage ?? capturedImage) : capturedImage else {
            print("无法获取图片数据")
            return
        }
        
        // 边界检查：确保有可用的多模态模型
        guard !multimodalModels.isEmpty, selectedModelIndex < multimodalModels.count else {
            print("没有可用的多模态模型")
            photoAnalysis = String(localized: "⚠️ 没有可用的多模态模型，请先在设置中添加支持视觉的模型。")
            return
        }
        
        isProcessing = true
        photoAnalysis = ""
        currentAsk = ""
        visionErrorMessage = nil
        // 重置推理状态
        reasoning = ""
        isReasoningExpanded = false
        displayReasoningLines = []
        
        currentModelName = multimodalModels[selectedModelIndex].name
        currentModelCompany = multimodalModels[selectedModelIndex].company
        currentModelIdentity = multimodalModels[selectedModelIndex].identity
        currentModelIcon = multimodalModels[selectedModelIndex].icon
        isCopied = false
        showImagePicker = false
        
        if useLastRequest {
            conversationContext = lastConversationContext
        } else {
            if conversationContext.isEmpty {
                conversationContext.append((role: "user", image: image, text: nil))
            } else if !followAsk.isEmpty {
                conversationContext.append((role: "user", image: nil, text: followAsk))
            } else {
                conversationContext.removeAll()
                conversationContext.append((role: "user", image: image, text: nil))
            }
            lastConversationContext = conversationContext
        }

        if !useLastRequest {
            lastRequestImage = image
            lastRequestFollowAsk = followAsk
        }

        // 构建记忆检索关键词（使用用户追问或默认关键词）
        let queryKeyword = useLastRequest ? lastQueryKeyword : (followAsk.isEmpty ? "图片分析 视觉" : followAsk)
        if !useLastRequest {
            lastQueryKeyword = queryKeyword
        }
        
        print(conversationContext)
        
        Task {
            do {
                let visionAPIManager = VisionAPIManager(context: context)
                
                let stream = try await visionAPIManager.sendPhotoStreamRequest(
                    message: conversationContext,
                    modelDisplayName: multimodalModels[selectedModelIndex].name,
                    query: queryKeyword
                )
                
                for try await streamData in stream {
                    await MainActor.run {
                        // 处理推理内容
                        if let reasoningText = streamData.reasoning {
                            reasoning.append(reasoningText)
                            updateDisplayReasoningLines()
                        }
                        
                        // 处理正文内容
                        if let contentText = streamData.content {
                            photoAnalysis?.append(contentText)
                        }
                        
                        // 仅在用户启用了振动时触发
                        let currentTime = Date()
                        if outPutFeedBackEnabled, currentTime.timeIntervalSince(lastUpdateTime) > refreshInterval {
                            isOutPut.toggle()
                            lastUpdateTime = currentTime
                        }
                    }
                }
                
                await MainActor.run {
                    visionErrorMessage = nil
                    conversationContext.append((role: "assistant", image: nil, text: photoAnalysis))
                    isProcessing = false
                }

            } catch {
                await MainActor.run {
                    let isZh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true
                    let message = error.localizedDescription
            visionErrorMessage = String(format: String(localized: "⚠️ 识别失败：%@"), message)
                    photoAnalysis = nil
                    isProcessing = false
                }
            }
        }
    }

    private func retryLastRequest() {
        guard !isProcessing else { return }
        visionErrorMessage = nil
        sendImageToAPI(useLastRequest: true)
    }
    
    /// 轮播式模型选择
    @ViewBuilder
    private var modelCarouselView: some View {
        if !multimodalModels.isEmpty {
            TabView(selection: $selectedModelIndex) {
                ForEach(multimodalModels.indices, id: \.self) { index in
                    modelItem(for: index)
                        .tag(index)
                        .padding(6)
                        .sensoryFeedback(.selection, trigger: isSelect) // 触发轻微振动
                }
            }
            .frame(width: 180, height: 80)
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .background(
                GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                    .clipShape(Capsule()) // 胶囊形
                    .shadow(color: Color(.systemBackground), radius: 1)
            )
            .clipShape(Capsule())
            .onChange(of: selectedModelIndex) {
                isSelect.toggle()
            }
        }
    }
    
    /// 单个模型的 UI（根据选中状态调整大小和透明度）
    private func modelItem(for index: Int) -> some View {
        
        let scaleFactor: CGFloat = index == selectedModelIndex ? 1.0 : 0.6
        let opacityFactor: Double = index == selectedModelIndex ? 1.0 : 0.4
        
        // 边界检查
        let model = index < multimodalModels.count ? multimodalModels[index] : (name: String(localized: "未知"), company: "", identity: "model", icon: "circle.dotted.circle")
        
        return VStack {
            Spacer()
            HStack {
                Spacer()
                if model.identity == "model" {
                    Image(getCompanyIcon(for: model.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25 * scaleFactor, height: 25 * scaleFactor)
                        .opacity(opacityFactor)
                        .animation(.easeInOut(duration: 0.3), value: selectedModelIndex)
                } else {
                    Image(systemName: model.icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 25 * scaleFactor, height: 25 * scaleFactor)
                        .clipShape(Circle())
                        .overlay(
                            Group {
                                gradient(for: 0)
                                .mask(
                                    Image(systemName: model.icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 25 * scaleFactor, height: 25 * scaleFactor)
                                )
                            }
                        )
                        .opacity(opacityFactor)
                        .animation(.easeInOut(duration: 0.3), value: selectedModelIndex)
                }
                Text(model.name)
                    .font(.caption)
                    .foregroundColor(index == selectedModelIndex ? .hlBluefont : Color(.systemGray))
                    .opacity(opacityFactor)
                    .animation(.easeInOut(duration: 0.3), value: selectedModelIndex)
                Spacer()
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.7))
        .clipShape(Capsule())
    }
}

// 负责管理相机的类
final class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "cameraQueue", qos: .userInitiated)
    private var isConfigured = false
    private var completionHandler: (@MainActor (UIImage?) -> Void)?
    
    @Published var zoomFactor: CGFloat = 1.0
    private var minZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat = 100.0
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var currentDevice: AVCaptureDevice?
    
    override init() {
        super.init()
        configureSession()
    }
    
    /// **初始化摄像头**
    private func configureSession() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        
        session.sessionPreset = .photo
        
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, // iPhone Pro 机型
            .builtInDualWideCamera, // iPhone 双摄
            .builtInWideAngleCamera // 单摄
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: currentCameraPosition
        )
        
        guard let newDevice = discoverySession.devices.first else {
            print("无法获取摄像头输入")
            session.commitConfiguration()
            return
        }
        
        // **如果当前设备未更改，则不重新配置**
        if let currentDevice = currentDevice, currentDevice.uniqueID == newDevice.uniqueID {
            session.commitConfiguration()
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: newDevice)
            
            // **移除旧的输入**
            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }
            
            // **添加新的输入**
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            currentDevice = newDevice
            session.commitConfiguration()
            isConfigured = true
        } catch {
            print("无法配置相机: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }
    
    /// **平滑设置变焦 (0.5x - 15x)**
    @MainActor
    func setZoomFactor(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        
        let clampedZoomFactor = max(minZoomFactor, min(factor, maxZoomFactor))
        
        do {
            try device.lockForConfiguration()
            
            // 使用平滑动画调整 Zoom
            UIView.animate(withDuration: 0.2) {
                device.videoZoomFactor = clampedZoomFactor
            }
            
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.zoomFactor = clampedZoomFactor / 2
            }
            
        } catch {
            print("无法调整缩放: \(error.localizedDescription)")
        }
    }
    
    /// **切换前/后摄像头**
    func switchCamera() {
        guard AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.count > 1 else {
            print("当前设备不支持前后摄像头切换")
            return
        }
        
        // **切换摄像头方向**
        currentCameraPosition = (currentCameraPosition == .back) ? .front : .back
        
        // **异步重新配置摄像头**
        queue.async {
            self.session.beginConfiguration()
            
            // **移除现有的输入**
            if let currentInput = self.session.inputs.first as? AVCaptureDeviceInput {
                self.session.removeInput(currentInput)
            }
            
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
                mediaType: .video,
                position: self.currentCameraPosition
            )
            
            guard let newDevice = discoverySession.devices.first else {
                print("无法找到新的摄像头设备")
                self.session.commitConfiguration()
                return
            }
            
            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                }
                self.currentDevice = newDevice
            } catch {
                print("无法添加新的摄像头输入: \(error.localizedDescription)")
            }
            
            self.session.commitConfiguration()
            
            self.isConfigured = true
        }
    }
    
    var isUsingFrontCamera: Bool {
        return currentCameraPosition == .front
    }
    
    /// **开始摄像头**
    func startSession() {
        let session = session
        let shouldStart = isConfigured
        queue.async {
            if shouldStart, !session.isRunning {
                session.startRunning()
            } else {
                return
            }
        }
    }
    
    /// **停止摄像头**
    func stopSession() {
        let session = session
        queue.async {
            if session.isRunning {
                session.stopRunning()
            } else {
                return
            }
        }
    }
    
    /// **拍照**
    func capturePhoto(completion: @escaping @MainActor (UIImage?) -> Void) {
        // 检查相机会话是否正在运行
        guard session.isRunning else {
            print("相机会话未运行，无法拍照")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let settings = AVCapturePhotoSettings()
            self.completionHandler = completion
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
    
    /// **处理照片**
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let imageData = photo.fileDataRepresentation()
        let completion = completionHandler
        completionHandler = nil
        // 确保在主线程回调
        DispatchQueue.main.async {
            guard let imageData, let image = UIImage(data: imageData) else {
                print("无法获取照片")
                completion?(nil)
                return
            }
            completion?(image)
        }
        stopSession()
    }
    
    /// **手电筒模式**
    func setFlash(_ isOn: Bool) {
        guard let device = currentDevice else { return }
        
        if isUsingFrontCamera {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ToggleScreenTorch"), object: isOn)
            }
        } else {
            // **后置摄像头使用物理闪光灯**
            if device.hasTorch {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = isOn ? .on : .off
                    device.unlockForConfiguration()
                } catch {
                    print("无法切换闪光灯: \(error.localizedDescription)")
                }
            }
        }
    }
}

// SwiftUI 视图，显示摄像头预览
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let showTorchBorder: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        // **添加白色边框**
        if showTorchBorder {
            let borderLayer = createWhiteBorder(frame: view.bounds)
            view.layer.addSublayer(borderLayer)
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // **检查是否需要白色边框**
        if let borderLayer = uiView.layer.sublayers?.first(where: { $0.name == "TorchBorder" }) {
            borderLayer.isHidden = !showTorchBorder
        } else if showTorchBorder {
            let borderLayer = createWhiteBorder(frame: uiView.bounds)
            uiView.layer.addSublayer(borderLayer)
        }
    }
    
    /// **创建白色边框**
    private func createWhiteBorder(frame: CGRect) -> CALayer {
        let borderLayer = CAShapeLayer()
        borderLayer.name = "TorchBorder"
        
        // **创建矩形遮罩**
        let path = UIBezierPath(rect: frame)
        let cutoutRect = CGRect(
            x: frame.width * 0.18,   // **左右各 18% 光圈，增强照明**
            y: frame.height * 0.18,  // **上下各 18% 透明**
            width: frame.width * 0.64, // **中间 64% 透明**
            height: frame.height * 0.64  // **中间 64% 透明**
        )
        let cutoutPath = UIBezierPath(roundedRect: cutoutRect, cornerRadius: 20)
        path.append(cutoutPath.reversing())
        
        borderLayer.path = path.cgPath
        borderLayer.fillColor = UIColor.white.withAlphaComponent(0.9).cgColor
        return borderLayer
    }
}


struct VisionImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var showModelSelection: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1 // 允许选择 1 张图片
        config.filter = .images // 仅限图片
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: VisionImagePicker

        init(_ parent: VisionImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
            
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor [weak self] in
                    guard let self, let image = UIImage(data: data) else { return }
                    self.parent.selectedImage = image
                    self.parent.showModelSelection = true
                }
            }
        }
    }
}
