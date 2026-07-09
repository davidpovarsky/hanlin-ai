//
//  QuickCalculateTool.swift
//  AI_HLY
//

import Foundation

struct QuickCalculateTool: NativeTool {
    let name = "quick_calculate"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Quick Calculator",
            summary: "Evaluate basic arithmetic expressions with +, -, *, /, parentheses and percentages.",
            categories: ["math", "calculation", "utility"],
            keywords: ["calculate", "calculator", "math", "percent", "percentage", "arithmetic", "כמה", "אחוז", "חשבון"],
            examples: ["What is 17% of 340?", "Calculate (12 + 8) * 3", "כמה זה 17% מתוך 340"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Evaluate a simple arithmetic expression. Use for exact arithmetic, percentages and short calculations.",
            parameters: NativeToolSchema.object(
                properties: [
                    "expression": NativeToolSchema.string(description: "Arithmetic expression to evaluate, e.g. '17% * 340' or '(12 + 8) / 4'.")
                ],
                required: ["expression"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let expression = try NativeToolJSON.requiredString(arguments, "expression")
            let value = try NativeExpressionEvaluator(expression: expression).parse()
            let formatted = Self.format(value)

            let block = NativeUIBlock(
                type: .calculation,
                title: "Calculation",
                subtitle: expression,
                body: formatted,
                systemImage: "function",
                actions: [NativeUIAction(type: .copyText, title: "Copy result", systemImage: "doc.on.doc", text: formatted)]
            )

            return NativeToolResult(
                modelText: "Calculation result for \(expression): \(formatted)",
                userText: formatted,
                uiBlocks: [block]
            )
        } catch {
            return NativeToolResult(
                modelText: "Calculation failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Calculation failed", body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
            )
        }
    }

    private static func format(_ value: Double) -> String {
        if value.isFinite && value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.8g", value)
    }
}

private struct NativeExpressionEvaluator {
    enum ParseError: LocalizedError {
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case divisionByZero
        case trailingInput

        var errorDescription: String? {
            switch self {
            case .unexpectedCharacter(let character): return "Unexpected character: \(character)"
            case .unexpectedEnd: return "Unexpected end of expression."
            case .divisionByZero: return "Division by zero."
            case .trailingInput: return "Unexpected trailing input."
            }
        }
    }

    private var characters: [Character]
    private var index: Int = 0

    init(expression: String) {
        self.characters = Array(expression.replacingOccurrences(of: " ", with: ""))
    }

    mutating func parse() throws -> Double {
        let value = try parseExpression()
        if index < characters.count { throw ParseError.trailingInput }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while let current = peek(), current == "+" || current == "-" {
            advance()
            let rhs = try parseTerm()
            value = current == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()
        while let current = peek(), current == "*" || current == "/" || current == "×" || current == "÷" {
            advance()
            let rhs = try parseFactor()
            if current == "/" || current == "÷" {
                if rhs == 0 { throw ParseError.divisionByZero }
                value /= rhs
            } else {
                value *= rhs
            }
        }
        return value
    }

    private mutating func parseFactor() throws -> Double {
        if let current = peek(), current == "+" || current == "-" {
            advance()
            let value = try parseFactor()
            return current == "-" ? -value : value
        }

        var value: Double
        if peek() == "(" {
            advance()
            value = try parseExpression()
            guard peek() == ")" else { throw ParseError.unexpectedEnd }
            advance()
        } else {
            value = try parseNumber()
        }

        if peek() == "%" {
            advance()
            value /= 100.0
        }
        return value
    }

    private mutating func parseNumber() throws -> Double {
        var buffer = ""
        while let current = peek(), current.isNumber || current == "." {
            buffer.append(current)
            advance()
        }
        guard !buffer.isEmpty, let value = Double(buffer) else {
            if let current = peek() { throw ParseError.unexpectedCharacter(current) }
            throw ParseError.unexpectedEnd
        }
        return value
    }

    private func peek() -> Character? {
        index < characters.count ? characters[index] : nil
    }

    private mutating func advance() {
        index += 1
    }
}
