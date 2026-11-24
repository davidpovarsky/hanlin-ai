import HanlinLocalization
//
//  MainTabView.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 10/2/25.
//

import SwiftUI
import SwiftData
import HanlinProductSplit

struct MainTabView: View {
    @Binding var deepLinkTarget: String?
    @Environment(\.hanlinAIReceivingWindowID) private var receivingWindowID
    @Environment(\.openURL) private var openURL
    private let splitCoordinator = HanlinAppSplitOriginCoordinator.shared
    @ObservedObject private var torahRouter = TorahStudyNavigationRouter.shared
    @State private var selectedTab = 0
    @State private var requestedConversation: HanlinConversationSelection?
    @State private var showsVision = false
    @State private var companionUnavailable = false
    @State private var modal: WorkspaceModal? = {
        #if DEBUG || (HANLIN_TESTING && targetEnvironment(simulator))
        let env = ProcessInfo.processInfo.environment
        if env["HANLIN_RUNTIME_INSTALL_ACCEPTANCE"] != nil { return .profile }
        // Existing engine-specific component probes still exercise the original
        // host. Product navigation uses the separate companion in every build.
        if ["HANLIN_SCRIPT_RESTART_REPRO_PHASE", "HANLIN_NATIVESCRIPT_E2E",
            "HANLIN_EXPO_E2E", "HANLIN_SCRIPTUI_E2E"].contains(where: { env[$0] != nil }) {
            return .runtimeComponent
        }
        #endif
        return nil
    }()

    private enum WorkspaceModal: String, Identifiable {
        case profile
        #if DEBUG || (HANLIN_TESTING && targetEnvironment(simulator))
        case runtimeComponent
        #endif
        var id: String { rawValue }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ListView(requestedSelection: $requestedConversation,
                onOpenProfile: { modal = .profile }, onOpenMiniApps: openCompanion,
                onOpenVision: { showsVision = true })
                .tabItem {
                    Label(String(localized: "Chat", bundle: HanlinLocalization.bundle), systemImage: "bubble.left.and.bubble.right")
                        .accessibilityIdentifier("hanlin-home-tab")
                }
                .tag(0)
            HanlinPersonalLibraryView(onOpenProfile: { modal = .profile },
                onOpenMiniApps: openCompanion, onOpenVision: { showsVision = true },
                onOpenConversation: { request in
                    requestedConversation = request
                    selectedTab = 0
                })
                .tabItem {
                    Label(hanlin: "Library", systemImage: "books.vertical")
                        .accessibilityIdentifier("hanlin-library-tab")
                }
                .tag(2)
        }
        .sheet(item: $modal) { destination in
            switch destination {
            case .profile:
                SettingsView(onDone: { modal = nil })
            #if DEBUG || (HANLIN_TESTING && targetEnvironment(simulator))
            case .runtimeComponent:
                NativeAppsHubView()
            #endif
            }
        }
        .fullScreenCover(isPresented: $showsVision) {
            VisionView(selectedTab: Binding(get: { 1 }, set: { if $0 != 1 { showsVision = false } }))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVisionView)) { _ in
            showsVision = true
        }
        .onChange(of: splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID)?.id, initial: true) {
            if splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID) != nil { selectedTab = 0 }
        }
        .onChange(of: deepLinkTarget) {
            if deepLinkTarget == "vision" {
                showsVision = true
                deepLinkTarget = nil
            }
        }
        .alert(Text("MiniApps unavailable", bundle: HanlinLocalization.bundle), isPresented: $companionUnavailable) {
            Button(hanlin: "OK", role: .cancel) {}
        } message: {
            Text("Install Hanlin MiniApps to open its catalog. Your conversation stays here.", bundle: HanlinLocalization.bundle)
        }
        .alert(Text("Mini App result unavailable", bundle: HanlinLocalization.bundle), isPresented: Binding(
            get: { splitCoordinator.failure(forReceivingWindowID: receivingWindowID) != nil },
            set: { if !$0 { splitCoordinator.dismissFailure(forReceivingWindowID: receivingWindowID) } }
        )) { Button(hanlin: "OK") { splitCoordinator.dismissFailure(forReceivingWindowID: receivingWindowID) } }
        message: { Text("Open the original conversation to check this request. Its result could not be returned to this window.", bundle: HanlinLocalization.bundle) }
        .background(Color(.systemBackground))
        .sheet(isPresented: $torahRouter.isPresentingReader) {
            if let link = torahRouter.activeDeepLink {
                TorahSourceReaderView(deepLink: link)
            }
        }
    }

    private func openCompanion() {
        openURL(SplitCompanionCatalogRoute.url) { accepted in
            if !accepted { companionUnavailable = true }
        }
    }
}

extension Notification.Name {
    static let openVisionView = Notification.Name("openVisionView")
    static let hideTabBar = Notification.Name("hideTabBar")
}

// Shared native material used by existing screens.
struct BlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style
    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

struct GlassView: View {
    let style: UIBlurEffect.Style
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .glassEffect(in: .rect(cornerRadius: 26))
            .allowsHitTesting(false)
    }
}
