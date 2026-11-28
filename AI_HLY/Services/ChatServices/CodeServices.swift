//
//  CodeServices.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 20/4/25.
//

import Foundation

class PistonExecutor {
    /// 执行完整 Python 3.10 脚本，返回包含执行状态的 CodeBlock
    static func executePythonCode(code: String) async throws -> CodeBlock {
        let url = URL(string: "https://emkc.org/api/v2/piston/execute")!

        // 预处理为 Jupyter 风格：最后表达式自动 print 输出
        let preprocessedCode = preprocessCodeForJupyterStyle(code)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "language": "python3",
            "version": "3.10.0",
            "files": [[
                "name": "main.py",
                "content": preprocessedCode
            ]]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return CodeBlock(codeType: "python", code: code, output: "请求构建失败：\(error.localizedDescription)", hasError: true)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
                return CodeBlock(codeType: "python", code: code,
                    output: RuntimeL10n.string("Piston requires provider authorization. No execution result was returned. You can run Python on this device instead."),
                    hasError: true)
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return CodeBlock(codeType: "python", code: code, output: "网络请求失败（状态码错误）", hasError: true)
            }

            guard
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let run = json["run"] as? [String: Any]
            else {
                return CodeBlock(codeType: "python", code: code, output: "无法解析执行结果", hasError: true)
            }

            let stdout = run["stdout"] as? String ?? ""
            let stderr = run["stderr"] as? String ?? ""
            let output = (stdout + stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            let hasError = !stderr.isEmpty

            return CodeBlock(codeType: "python", code: code, output: output, hasError: hasError)
        } catch {
            return CodeBlock(codeType: "python", code: code, output: "请求执行失败：\(error.localizedDescription)", hasError: true)
        }
    }

    /// 将最后一行表达式转换为 print(repr(...))，模拟 Jupyter 自动输出行为
    private static func preprocessCodeForJupyterStyle(_ code: String) -> String {
        let lines = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let lastLineIndex = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return code
        }

        let lastLine = lines[lastLineIndex].trimmingCharacters(in: .whitespaces)

        // 不处理注释、空行
        if lastLine.hasPrefix("#") { return code }

        // 不处理已有 print/return 调用
        let normalized = lastLine.replacingOccurrences(of: " ", with: "")
        if normalized.hasPrefix("print(") || normalized.hasPrefix("return") {
            return code
        }

        // 控制结构、定义、赋值语句等不处理
        let controlKeywords = [
            "def ", "class ", "if ", "elif ", "else",
            "try", "except", "for ", "while ", "with ",
            "import ", "pass", "="
        ]
        if controlKeywords.contains(where: { lastLine.hasPrefix($0) || lastLine.contains(" = ") }) {
            return code
        }
        let methodCallPattern = #"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\(.*\)$"#
        if lastLine.range(of: methodCallPattern, options: .regularExpression) != nil {
            return code
        }

        // 替换最后一行为 print(repr(...))
        var newLines = lines
        newLines[lastLineIndex] = "print(repr(\(lastLine)))"
        return newLines.joined(separator: "\n")
    }
}
