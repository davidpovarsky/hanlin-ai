import Foundation

enum SkillL10n {
    private static let zhTranslations: [String: String] = [
        "Skill Center": "技能中心",
        "Skills": "技能",
        "All": "全部",
        "Custom": "自定义",
        "System": "系统",
        "Overrides": "已修改",
        "Search skills...": "搜索技能...",
        "No skills found": "未找到技能",
        "Custom & Imported Skills": "自定义与导入技能",
        "System & Mini App Skills": "系统与小程序技能",
        "Import": "导入",
        "Create Skill": "创建技能",
        "Edit Skill": "编辑技能",
        "Skill Details": "技能详情",
        "Identifier": "标识符",
        "Source": "来源",
        "Enabled": "已启用",
        "Disabled": "已禁用",
        "Instructions": "说明指令",
        "Preferred Tools": "优先工具",
        "Resources": "资源文件",
        "No resources": "无资源文件",
        "Customize (Override)": "自定义覆盖",
        "Reset to Default": "恢复默认",
        "Delete": "删除",
        "Delete Skill": "删除技能",
        "Are you sure you want to delete this skill?": "确定要删除此技能吗？",
        "Cancel": "取消",
        "Save": "保存",
        "Import Skill": "导入技能",
        "Import ZIP Archive": "导入 ZIP 压缩包",
        "Select ZIP File": "选择 ZIP 文件",
        "Install from HTTPS URL": "从 HTTPS 地址安装",
        "Skill Archive URL": "技能压缩包链接",
        "Download & Install": "下载并安装",
        "Installing...": "正在安装...",
        "Success": "成功",
        "Error": "错误",
        "Skill ID": "技能 ID",
        "Title": "名称",
        "Description": "描述",
        "Body / Instructions": "主体说明",
        "Keywords (comma-separated)": "关键词（逗号分隔）",
        "Trigger Hints (comma-separated)": "触发提示（逗号分隔）",
        "Preferred Tool Aliases (comma-separated)": "优先工具别名（逗号分隔）",
        "Preview Resource": "预览资源",
        "Close": "关闭"
    ]

    static func string(_ key: String) -> String {
        let isZh = (Locale.preferredLanguages.first ?? "").hasPrefix("zh")
        if isZh, let zh = zhTranslations[key] {
            return zh
        }
        return NSLocalizedString(key, tableName: "SkillLocalizable", bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
