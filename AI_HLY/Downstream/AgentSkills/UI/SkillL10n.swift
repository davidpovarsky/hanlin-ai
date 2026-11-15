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
        "Import File": "导入文件",
        "Select ZIP or SKILL.md": "选择 ZIP 或 SKILL.md",
        "Select a ZIP package or a SKILL.md file. Previewing does not run scripts.": "选择 ZIP 包或 SKILL.md 文件。预览不会运行脚本。",
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
        "Close": "关闭",
        "Compatibility": "兼容性",
        "Compatibility unknown": "兼容性未知",
        "Status": "状态",
        "Unknown": "未知",
        "Last tested": "上次测试",
        "Not recorded": "未记录",
        "Installing or enabling a skill does not verify that its actions can run.": "安装或启用技能并不表示其操作已经过运行验证。"
    ]

    private static let heTranslations: [String: String] = [
        "Import File": "ייבוא קובץ",
        "Select ZIP or SKILL.md": "בחירת ZIP או SKILL.md",
        "Select a ZIP package or a SKILL.md file. Previewing does not run scripts.": "יש לבחור חבילת ZIP או קובץ SKILL.md. תצוגה מקדימה אינה מריצה סקריפטים.",
        "Compatibility": "תאימות",
        "Compatibility unknown": "תאימות לא ידועה",
        "Status": "מצב",
        "Unknown": "לא ידוע",
        "Last tested": "בדיקה אחרונה",
        "Not recorded": "לא תועד",
        "Installing or enabling a skill does not verify that its actions can run.": "התקנה או הפעלה אינן מאמתות שניתן להריץ את פעולות ה־Skill."
    ]

    static func string(_ key: String) -> String {
        if (Locale.preferredLanguages.first ?? "").hasPrefix("he"), let he = heTranslations[key] {
            return he
        }
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
