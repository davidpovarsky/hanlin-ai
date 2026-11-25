import SwiftUI
import Observation
import HanlinChatPresentation
import HanlinPresentationKit
import HanlinChatUI

private struct LabMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
}

/// Deliberately offline, deterministic fixture. All visible chat chrome is
/// the original Hanlin SDK; this host only owns transcript, draft and replies.
@MainActor @Observable
private final class LabSession {
    let draft = HanlinComposerDraft()
    var messages: [LabMessage] = [
        .init(isUser: false, text: "שלום! אני Hanlin. אפשר לעבור בין חלונית הזכוכית ל־Inspector מבלי לאבד את השיחה או הטיוטה.")
    ]
    var isStreaming = false
    private var streamTask: Task<Void, Never>?

    func sendDraft() { send(draft.text) }
    func send(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isStreaming else { return }
        draft.text = ""
        messages.append(.init(isUser: true, text: value))
        messages.append(.init(isUser: false, text: ""))
        let responseID = messages[messages.count - 1].id
        isStreaming = true
        streamTask = Task { @MainActor [weak self] in
            let answer = "### Hanlin SDK\n\nזוהי תשובת הדגמה מקומית, המוזרמת בהדרגה כדי לבחון את השיחה האמיתית של ה־SDK. \n\nהחלף בין Sheet ל־Inspector בזמן הכתיבה: ההודעות והטיוטה נשארות באותו מודל."
            for part in answer.split(separator: " ", omittingEmptySubsequences: false) {
                guard !Task.isCancelled, let self,
                      let index = self.messages.firstIndex(where: { $0.id == responseID }) else { return }
                self.messages[index].text += part + " "
                try? await Task.sleep(for: .milliseconds(45))
            }
            self?.isStreaming = false
            self?.streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}

private enum LabModes: String, CaseIterable, Identifiable {
    case both, sheet, inspector
    var id: String { rawValue }
    var title: String {
        switch self {
        case .both: "שני המצבים"
        case .sheet: "Sheet בלבד"
        case .inspector: "Inspector בלבד"
        }
    }
    var modes: Set<HanlinChatPresentationMode> {
        switch self {
        case .both: [.sheet, .inspector]
        case .sheet: [.sheet]
        case .inspector: [.inspector]
        }
    }
}

@main
struct HanlinLauncherLabApp: App {
    var body: some Scene {
        WindowGroup { LabReader() }
    }
}

@MainActor
private struct LabReader: View {
    @State private var session = LabSession()
    @State private var presentation = HanlinChatPresentationController()
    @State private var style = HanlinLauncherStyle.toolbarCapsule
    @State private var modes = LabModes.both
    @State private var initialMode = HanlinChatPresentationMode.sheet
    @State private var zoom = false
    @State private var page = 1
    @State private var hebrew = true
    @Namespace private var launcherNamespace

    private var labels: HanlinLauncherLabels {
        hebrew ? .init(title: "Hanlin", ask: "שאל את Hanlin", placeholder: "מה תרצה לשאול?",
                       send: "שלח", close: "סגור", sheet: "חזור לחלונית", inspector: "פתח כחלונית צד") : .init()
    }
    private var transition: HanlinLauncherTransition? {
        zoom ? .init(namespace: launcherNamespace) : nil
    }
    private var draft: Binding<String> {
        Binding(get: { session.draft.text }, set: { session.draft.text = $0 })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("מעבדת Hanlin").font(.largeTitle.bold())
                        Text("שלוש כניסות Liquid Glass • חלונית מערכת ו־Inspector")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Picker("סגנון כניסה", selection: $style) {
                            Text("סרגל כלים").tag(HanlinLauncherStyle.toolbarCapsule)
                            Text("קפסולה צפה").tag(HanlinLauncherStyle.floatingCapsule)
                            Text("שאלה מהירה").tag(HanlinLauncherStyle.quickComposer)
                        }
                        .pickerStyle(.segmented)
                        Picker("מצבי הצגה", selection: $modes) {
                            ForEach(LabModes.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(presentation.isPresented)
                        if modes == .both {
                            Picker("פתיחה ראשונית", selection: $initialMode) {
                                Text("Sheet").tag(HanlinChatPresentationMode.sheet)
                                Text("Inspector").tag(HanlinChatPresentationMode.inspector)
                            }
                            .pickerStyle(.segmented)
                            .disabled(presentation.isPresented)
                        }
                        Toggle("מעבר Zoom מערכתי (ניסוי)", isOn: $zoom)
                            .disabled(presentation.isPresented)
                        Toggle("עברית ו־RTL", isOn: $hebrew)
                        Text("הדגמה מקומית, ללא חיבור לספק מודלים.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))

                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ספר הלימוד").font(.title.bold())
                            Text("פרק \(page)").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { page += 1 } label: { Label("הבא", systemImage: "arrow.left") }
                            .buttonStyle(.glass)
                    }
                    ForEach(0..<10) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(["לימוד ועיון", "מקור והסבר", "הרחבה ומחשבה"][i % 3])
                                .font(.headline)
                            Text("הטקסט נשאר פעיל גם כאשר עוזר הלימוד פתוח. אפשר לגלול, לעבור לפרק הבא, לשאול שאלה או להצמיד את Hanlin לצד הספר. החלפת צורת ההצגה אינה יוצרת שיחה חדשה.")
                                .font(.title3).lineSpacing(7)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 100)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Hanlin SDK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if style == .toolbarCapsule && presentation.showsLauncher {
                    ToolbarItem(placement: .topBarTrailing) {
                        launcher
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if style != .toolbarCapsule && presentation.showsLauncher {
                    launcher
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                }
            }
        }
        .hanlinChatPresentation(controller: presentation, labels: labels, transition: transition) { _ in
            LabChat(session: session, labels: labels)
        }
        .environment(\.layoutDirection, hebrew ? .rightToLeft : .leftToRight)
        .onChange(of: modes) { _, _ in reconfigure() }
        .onChange(of: initialMode) { _, _ in reconfigure() }
    }

    private var launcher: some View {
        HanlinLauncher(style: style, controller: presentation, draft: draft,
                       labels: labels, transition: transition, onQuickSubmit: session.send)
    }

    private func reconfigure() {
        presentation.configure(.init(modes: modes.modes, initialMode: initialMode,
                                     sheetAppearance: .clearGlass, placement: .leading))
    }
}

@MainActor
private struct LabChat: View {
    let session: LabSession
    let labels: HanlinLauncherLabels
    @State private var isExpanded = false
    @State private var activePage: String?
    @State private var editorHeight: CGFloat = 38
    @State private var toolbarHeight: CGFloat = 44

    private var draft: Binding<String> {
        Binding(get: { session.draft.text }, set: { session.draft.text = $0 })
    }

    var body: some View {
        GeometryReader { geo in
            let inputHeight = max(52, editorHeight + 16)
            HanlinChatView(shell: .init(id: "hanlin.standard", title: "Hanlin"),
                           showsComposerBackdrop: false) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(session.messages) { message in
                            if message.isUser {
                                HStack {
                                    Spacer(minLength: 10)
                                    HanlinUserMessageBubble(text: message.text, containerWidth: max(160, geo.size.width - 32))
                                }
                            } else {
                                HanlinAssistantMessageBubble(isResponding: session.isStreaming && message.id == session.messages.last?.id) {
                                    Label("Hanlin", systemImage: "sparkles").font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    if message.text.isEmpty {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        HanlinMarkdownView(text: message.text)
                                    }
                                }
                            }
                        }
                        if session.isStreaming {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("מנסח תשובה…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, inputHeight + (isExpanded ? 220 : 34))
                }
                .defaultScrollAnchor(.bottom)
            } composer: {
                HanlinMorphComposer(
                    isExpanded: $isExpanded, activePage: $activePage,
                    availableHeight: geo.size.height, accessoryHeight: 0,
                    inputHeight: inputHeight,
                    title: { _ in "Hanlin" },
                    subtitle: { _ in "Original SDK composer" },
                    backIdentifier: { _ in "lab-composer-back" },
                    onOpen: {}, onBackgroundTap: {}, onToolbarHeightChange: { toolbarHeight = $0 }
                ) {
                    Button { session.draft.text = "סכם את הקטע הנוכחי" } label: {
                        Label("סיכום הקטע", systemImage: "text.alignleft")
                    }
                    .buttonStyle(.glass)
                } detail: { _ in
                    Text("Hanlin")
                } input: {
                    HStack(alignment: .bottom, spacing: 6) {
                        NativeMultilineTextEditor(
                            text: draft, textHeight: $editorHeight,
                            placeholderText: labels.placeholder, minHeight: 38,
                            maxHeight: 110, onSendMessage: session.sendDraft,
                            readCurrentTextState: { session.draft.snapshot })
                            .frame(height: max(38, editorHeight))
                            .frame(maxWidth: .infinity)
                        Button {
                            if session.isStreaming { session.stop() } else { session.sendDraft() }
                        } label: {
                            Image(systemName: session.isStreaming ? "stop.fill" : "arrow.up")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(!session.isStreaming && session.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(labels.send)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}
