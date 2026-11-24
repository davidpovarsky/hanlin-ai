import HanlinLocalization
//
//  ListViewComponents.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 11/2/25.
//

import SwiftUI
import SwiftData


struct ChatRowView: View {
    @Environment(\.modelContext) private var modelContext
    var record: ChatRecords
    var searchText: String
    var matchedSnippet: AttributedString?

    @State private var selectedIcon: String
    @State private var selectedColor: Color
    @ScaledMetric(relativeTo: .body) var size_48: CGFloat = 48

    init(record: ChatRecords, searchText: String, matchedSnippet: AttributedString? = nil) {
        self.record = record
        self.searchText = searchText
        self.matchedSnippet = matchedSnippet
        self._selectedIcon = State(initialValue: record.icon ?? "bubble.left.circle")
        self._selectedColor = State(initialValue: Color.from(name: record.color ?? ".hlBlue"))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedIcon)
                .font(HanlinTypography.fixed(size: 18))
                .foregroundColor(selectedColor)
                .frame(width: 36, height: 36)
                .background(selectedColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading) {
                HStack {
                    highlightedChatName()
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Spacer()
                    
                    Text(formattedDate(record.lastEdited))
                        .font(HanlinTypography.caption)
                        .foregroundColor(.gray)
                }
                
                // 如果存在匹配片段，则显示出来
                if let snippet = matchedSnippet {
                    Text(snippet)
                        .font(HanlinTypography.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    if let highlightedDescription = highlightedText(record.infoDescription ?? "", searchText: searchText) {
                        Text(highlightedDescription)
                            .font(HanlinTypography.caption)
                            .foregroundColor(Color(.systemGray))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text(String(localized: "暂无消息", bundle: HanlinLocalization.bundle))
                            .font(HanlinTypography.caption)
                            .foregroundColor(Color(.systemGray))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .padding(.vertical, 8)
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
        attributedString.font = .caption
        
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
                .font(HanlinTypography.headline)
                .foregroundColor(.primary)
        }
        
        // 去除搜索词前后空格，并提前处理空搜索
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return Text(name).font(HanlinTypography.headline)
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
                attributedName[attrRange].font = .headline.bold()
            }
            searchRange = foundRange.upperBound..<name.endIndex
        }
        
        return Text(attributedName)
            .font(HanlinTypography.headline)
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

