//
//  TranslationDicView.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 8/4/25.
//

import SwiftUI
import SwiftData

extension TranslationDic: Identifiable { }

struct TranslationDicView: View {
    @Environment(\.modelContext) private var modelContext
    
    // 采用 SwiftData @Query 获取所有翻译记录，按更新时间降序排列
    @Query(sort: [SortDescriptor(\TranslationDic.timestamp, order: .reverse)])
    private var translationEntries: [TranslationDic]
    
    // 当前选择的语言索引、翻译内容
    @State private var contentOne: String = ""
    @State private var contentTwo: String = ""
    
    // Toast 提示相关状态
    @State private var showToast = false
    @State private var toastMessage = ""
    
    // 编辑词条
    @State private var editingTranslation: TranslationDic? = nil
    
    var body: some View {
        List {
            // MARK: 信息提示区
            Section {
                VStack(alignment: .center) {
                    Image(systemName: "character.book.closed")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.hlBluefont)
                        .padding()
                    
                    Text(String(localized: "自定义翻译词典将使得“即时翻译”的翻译结果变得更加个性化，特别是对于某些私有化的翻译知识而言，在翻译词典中添加搭配能最快速的优化你的翻译结果。"))
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            // MARK: 翻译输入区
            Section(header: Text(String(localized: "输入翻译词汇"))) {
                
                TextField(String(localized: "内容1"), text: $contentOne)
                
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.hlBluefont)
                        .bold()
                    Spacer()
                }
                
                TextField(String(localized: "内容2"), text: $contentTwo)
                
                Button(action: {
                    addTranslation()
                }, label: {
                    HStack {
                        Spacer()
                        Text(String(localized: "保存翻译搭配"))
                            .foregroundColor(.hlBluefont)
                            .bold()
                        Spacer()
                    }
                })
                .padding(.vertical, 4)
            }
            
            // MARK: 翻译词典列表
            Section(header: Text(String(localized: "翻译词典"))) {
                if translationEntries.isEmpty {
                    Text(String(localized: "暂无翻译记录"))
                        .foregroundColor(.gray)
                } else {
                    ForEach(translationEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.contentOne ?? "")
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(entry.contentTwo ?? "")
                            Text("更新时间：\(entry.timestamp, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingTranslation = entry
                            } label: {
                                Label(String(localized: "编辑"), systemImage: "paintbrush")
                            }
                            .tint(.hlGreen)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                if let index = translationEntries.firstIndex(where: { $0.id == entry.id }) {
                                    deleteTranslation(at: IndexSet(integer: index))
                                }
                            } label: {
                                Label(String(localized: "删除"), systemImage: "trash")
                            }
                            .tint(.hlRed)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)    // 原生分组列表风格
        .navigationTitle(String(localized: "翻译词典"))
        .overlay(toastOverlay)
        .sheet(item: $editingTranslation) { translation in
            EditTranslationView(translation: translation)
        }
    }
    
    /// 新增翻译记录
    private func addTranslation() {
        
        // 校验内容不能为空
        guard !contentOne.isEmpty, !contentTwo.isEmpty else {
            toastMessage = "内容不能为空"
            withAnimation { showToast = true }
            return
        }
        
        let newTranslation = TranslationDic(
            contentOne: contentOne,
            contentTwo: contentTwo,
            timestamp: Date()
        )
        
        modelContext.insert(newTranslation)
        do {
            try modelContext.save()
            contentOne = ""
            contentTwo = ""
            toastMessage = "保存成功！"
            withAnimation { showToast = true }
        } catch {
            toastMessage = "保存失败：\(error.localizedDescription)"
            withAnimation { showToast = true }
        }
    }
    
    /// 删除翻译记录
    private func deleteTranslation(at offsets: IndexSet) {
        for index in offsets {
            let item = translationEntries[index]
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
        } catch {
            toastMessage = "删除失败"
            withAnimation { showToast = true }
        }
    }
    
    /// 日期格式化器用于展示更新时间
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter
    }()
    
    /// Toast 提示视图
    @ViewBuilder
    private var toastOverlay: some View {
        VStack {
            if showToast {
                Text(toastMessage)
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { showToast = false }
                        }
                    }
            }
            Spacer()
        }
        .padding(.top, 50)
    }
}

struct EditTranslationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var translation: TranslationDic
    
    // 当前编辑选项
    @State private var contentOne: String = ""
    @State private var contentTwo: String = ""
    
    // Toast 提示相关状态
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text(String(localized: "编辑翻译词汇"))) {
                    TextField(String(localized: "内容1"), text: $contentOne)
                    
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.hlBluefont)
                            .bold()
                        Spacer()
                    }
                    
                    TextField(String(localized: "内容2"), text: $contentTwo)
                }
            }
            .navigationTitle(String(localized: "编辑翻译"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        saveEdits()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // 初始化编辑内容
                contentOne = translation.contentOne ?? ""
                contentTwo = translation.contentTwo ?? ""
            }
            .overlay(
                VStack {
                    if showToast {
                        Text(toastMessage)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .padding(.top, 50)
            )
        }
    }
    
    private func saveEdits() {
        
        guard !contentOne.isEmpty, !contentTwo.isEmpty else {
            toastMessage = "内容不能为空"
            withAnimation { showToast = true }
            return
        }
        
        translation.contentOne = contentOne
        translation.contentTwo = contentTwo
        translation.timestamp = Date()
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            toastMessage = "保存失败: \(error.localizedDescription)"
            withAnimation { showToast = true }
        }
    }
}
