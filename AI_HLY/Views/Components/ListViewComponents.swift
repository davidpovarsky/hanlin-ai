import HanlinLocalization
//
//  ListViewComponents.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 11/2/25.
//

import SwiftUI
import SwiftData


/// One section projection shared by wide and compact history. Pinned records
/// occur once; date buckets use the user's calendar rather than 24-hour offsets.
@MainActor
enum HanlinConversationHistory {
    enum Period: String, CaseIterable {
        case pinned, today, yesterday, earlier
    }

    struct Section: Identifiable {
        let id: Period
        let records: [ChatRecords]

        var title: String {
            switch id {
            case .pinned: String(localized: "Pinned", bundle: HanlinLocalization.bundle)
            case .today: String(localized: "Today", bundle: HanlinLocalization.bundle)
            case .yesterday: String(localized: "Yesterday", bundle: HanlinLocalization.bundle)
            case .earlier: String(localized: "Earlier", bundle: HanlinLocalization.bundle)
            }
        }
    }

    static func sections(from records: [ChatRecords], now: Date = .now,
                         calendar: Calendar = .current) -> [Section] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var buckets: [Period: [ChatRecords]] = [:]
        for record in records {
            let period: Period
            if record.isPinned {
                period = .pinned
            } else if record.lastEdited >= today {
                period = .today
            } else if record.lastEdited >= yesterday {
                period = .yesterday
            } else {
                period = .earlier
            }
            buckets[period, default: []].append(record)
        }
        return Period.allCases.compactMap { period in
            guard let rows = buckets[period], !rows.isEmpty else { return nil }
            return Section(id: period, records: rows.sorted {
                if $0.lastEdited != $1.lastEdited { return $0.lastEdited > $1.lastEdited }
                return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
            })
        }
    }
}

struct ChatRowView: View {
    var record: ChatRecords
    var searchText: String
    var matchedSnippet: AttributedString?
    var isSelected: Bool

    private var selectedIcon: String { record.icon ?? "bubble.left.circle" }
    private var selectedColor: Color { Color.from(name: record.color ?? ".hlBlue") }

    init(record: ChatRecords, searchText: String, matchedSnippet: AttributedString? = nil,
         isSelected: Bool = false) {
        self.record = record
        self.searchText = searchText
        self.matchedSnippet = matchedSnippet
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedIcon)
                .font(HanlinTypography.body)
                .foregroundStyle(selectedColor)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    highlightedChatName()
                        // Match the custom pale selection fill even while the
                        // native sidebar supplies its focused selection style.
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    Text(formattedDate(record.lastEdited))
                        .font(HanlinTypography.caption2)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                // 如果存在匹配片段，则显示出来
                if let snippet = matchedSnippet {
                    Text(snippet)
                        .font(HanlinTypography.caption2)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .lineLimit(searchText.isEmpty ? 1 : 2)
                        .truncationMode(.tail)
                } else {
                    if let highlightedDescription = highlightedText(record.infoDescription ?? "", searchText: searchText) {
                        Text(highlightedDescription)
                            .font(HanlinTypography.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(searchText.isEmpty ? 1 : 2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(String(localized: "暂无消息", bundle: HanlinLocalization.bundle))
                            .font(HanlinTypography.caption2)
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .lineLimit(searchText.isEmpty ? 1 : 2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.hanlinHLSidebarSelection : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            // 如果是今天，显示具体时间
            dateFormatter.dateFormat = "HH:mm"
            return dateFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday", bundle: HanlinLocalization.bundle)
        } else if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: Date()),
                  calendar.isDate(date, inSameDayAs: twoDaysAgo) {
            return String(localized: "Two days ago", bundle: HanlinLocalization.bundle)
        } else {
            // 超过前天，显示“月-日”
            dateFormatter.dateFormat = "MM-dd"
            return dateFormatter.string(from: date)
        }
    }
    
    private func highlightedText(_ text: String, searchText: String) -> AttributedString? {
        // Older conversations persisted Chinese markers. Localize only those
        // exact leading markers for display, preserving the saved draft itself.
        let draftMarker = "[\(String(localized: "Draft", bundle: HanlinLocalization.bundle))]"
        let imageMarker = "[\(String(localized: "Image", bundle: HanlinLocalization.bundle))]"
        let displayText: String
        if text.hasPrefix("[草稿]") {
            displayText = draftMarker + text.dropFirst("[草稿]".count)
        } else if text.hasPrefix("[图像]") {
            displayText = imageMarker + text.dropFirst("[图像]".count)
        } else {
            displayText = text
        }
        var attributedString = AttributedString(displayText)
        attributedString.font = .caption2
        
        // 检查开头是否为 "[草稿]" 或 "[图像]" 并做颜色处理
        if displayText.hasPrefix(draftMarker) {
            if let draftRange = attributedString.range(of: draftMarker) {
                attributedString[draftRange].foregroundColor = .hanlinHLRed
            }
        } else if displayText.hasPrefix(imageMarker) {
            if let imageRange = attributedString.range(of: imageMarker) {
                attributedString[imageRange].foregroundColor = .hanlinHLGreen
            }
        }
        
        // 如果 searchText 非空，则对其中匹配的部分进行高亮
        if !searchText.isEmpty,
           let range = attributedString.range(of: searchText, options: .caseInsensitive) {
            attributedString[range].foregroundColor = Color(.hanlinHLBlue)
            attributedString[range].font = .systemFont(ofSize: UIFont.systemFontSize, weight: .bold)
        }
        
        return attributedString
    }
    
    private func highlightedChatName() -> Text {
        // 如果名称为空，则返回默认“Unknown”
        guard let name = record.name, !name.isEmpty else {
            return Text("Unknown", bundle: HanlinLocalization.bundle)
                .font(HanlinTypography.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))
        }
        
        // 去除搜索词前后空格，并提前处理空搜索
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return Text(name).font(HanlinTypography.subheadline.weight(.medium))
        }
        
        // 构建富文本对象
        var attributedName = AttributedString(name)
        // Unicode case conversion can change string length. Keep search and
        // conversion indices in the original title's coordinate space.
        var searchRange = name.startIndex..<name.endIndex
        while let foundRange = name.range(of: trimmedSearch, options: .caseInsensitive, range: searchRange) {
            let nsRange = NSRange(foundRange, in: name)
            if let attrRange = Range(nsRange, in: attributedName) {
                attributedName[attrRange].foregroundColor = .hanlinHLBlue
                attributedName[attrRange].font = .subheadline.bold()
            }
            searchRange = foundRange.upperBound..<name.endIndex
        }
        
        return Text(attributedName)
            .font(HanlinTypography.subheadline.weight(.medium))
    }
}

struct ChatViewWrapper: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.hanlinAIReceivingWindowID) private var receivingWindowID
    private let splitCoordinator = HanlinAppSplitOriginCoordinator.shared
    var chatRecord: ChatRecords
    var matchedMessageID: UUID?

    var body: some View {
        ChatView(chatRecord: chatRecord, matchedMessageID: matchedMessageID)
            .task(id: splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID)?.id) {
                guard let request = splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID),
                      request.chat == chatRecord.id else { return }
                await Task.yield()
                let id = request.chat
                guard !Task.isCancelled,
                      splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID)?.id == request.id,
                      let rows = try? modelContext.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id })),
                      rows.count == 1, rows.first === chatRecord else { return }
                splitCoordinator.acknowledgeAcceptedOrigin(requestID: request.id, receivingWindowID: receivingWindowID)
            }
    }
}


struct IconAndColorPicker: View {
    @Binding var selectedIcon: String
    @Binding var selectedColor: Color
    @Binding var title: String
    
    let availableIcons = getIconList()
    let availableColors = getColorList()
    
    let iconColumns = [GridItem(.adaptive(minimum: 60), spacing: 12)]  // 图标：每行自适应
    let colorColumns = [GridItem(.adaptive(minimum: 40), spacing: 12)] // 颜色：每行自适应，最小宽度更小
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 预览消息栏
                HStack(spacing: 12) {
                    Image(systemName: selectedIcon)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(selectedColor)
                        .background(Circle().fill(Color(.clear)))
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        TextField(String(localized: "请输入标题", bundle: HanlinLocalization.bundle), text: $title)
                            .font(HanlinTypography.headline)
                            .foregroundColor(.primary)
                            .textFieldStyle(PlainTextFieldStyle())
                        
                        Text(String(localized: "这是一段示例消息内容...", bundle: HanlinLocalization.bundle))
                            .font(HanlinTypography.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.thinMaterial)
                        .shadow(color: Color.hanlinHLBlue, radius: 1)
                )
                .padding(.horizontal)
                
                // 图标选择
                VStack(alignment: .leading) {
                    ScrollView {
                        LazyVGrid(columns: iconColumns, spacing: 20) {
                            ForEach(availableIcons, id: \.self) { icon in
                                ZStack {
                                    Image(systemName: icon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 40, height: 40)
                                        .foregroundColor(selectedIcon == icon ? selectedColor : .gray)
                                        .background(Circle().fill(Color(.clear)))
                                        .clipShape(Circle())
                                }
                                .onTapGesture {
                                    selectedIcon = icon
                                }
                            }
                        }
                    }
                    .padding()
                    .cornerRadius(20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.thinMaterial)
                        .shadow(color: Color.hanlinHLBlue, radius: 1)
                )
                .padding(.horizontal)
                
                // 颜色选择
                VStack(alignment: .leading) {
                    ScrollView {
                        LazyVGrid(columns: colorColumns, spacing: 20) {
                            ForEach(availableColors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .onTapGesture {
                                        selectedColor = color
                                    }
                            }
                        }
                        .padding()
                    }
                    .padding()
                    .cornerRadius(20)
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.thinMaterial)
                        .shadow(color: Color.hanlinHLBlue, radius: 1)
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(.background)
            .navigationTitle(String(localized: "自定义", bundle: HanlinLocalization.bundle))
            .navigationBarItems(trailing: Button(String(localized: "完成", bundle: HanlinLocalization.bundle)) {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first {
                    window.rootViewController?.dismiss(animated: true)
                }
            })
        }
    }
}

