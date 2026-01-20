//
//  APITest.swift
//  AI_Hanlin
//
//  Created by 哆啦好多梦 on 24/3/25.
//

import Foundation

/// 用于测试当前填写的 API Key 和 URL 是否可用，返回布尔值
/// - Parameters:
///   - apiKey: API密钥
///   - requestURL: 请求地址
///   - company: 厂商名称
/// - Returns: 测试是否通过
func testAIAPI(apiKey: String, requestURL: String, company: String) async -> (Bool, String?) {
    let testModel = getTestModel(for: company)
    return await testAIAPIWithModel(apiKey: apiKey, requestURL: requestURL, company: company, modelName: testModel)
}

/// 用于测试当前填写的 API Key 和 URL 是否可用，使用指定的模型名称
/// - Parameters:
///   - apiKey: API密钥
///   - requestURL: 请求地址
///   - company: 厂商名称
///   - modelName: 用于测试的模型名称
/// - Returns: 测试是否通过
func testAIAPIWithModel(apiKey: String, requestURL: String, company: String, modelName: String) async -> (Bool, String?) {
    let isZh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true
    // 1. 检查 API Key 和 URL 是否有效
    guard !apiKey.isEmpty,
          !requestURL.isEmpty,
          let url = URL(string: requestURL) else {
        return (false, isZh ? "API Key 或请求地址无效" : "Invalid API Key or request URL.")
    }
    
    // 2. 准备请求体（这里仅发送一个简单的测试消息）
    let messages: [[String: Any]] = [
        [
            "role": "user",
            "content": "Hello"
        ]
    ]
    
    // 处理模型名称，去除后缀
    let testModel = restoreBaseModelName(from: modelName)
    
    let requestBody: [String: Any] = [
        "model": testModel,
        "messages": messages,
        "stream": true
    ]
    
    // 3. 构造 URLRequest
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    if company == "ANTHROPIC" {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    } else {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])

    func parseRequestErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                if let message = error["message"] as? String, !message.isEmpty {
                    return message
                }
                if let detail = error["detail"] as? String, !detail.isEmpty {
                    return detail
                }
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if let detail = json["detail"] as? String, !detail.isEmpty {
                return detail
            }
            if let errorDescription = json["error_description"] as? String, !errorDescription.isEmpty {
                return errorDescription
            }
            if let errors = json["errors"] as? [String], !errors.isEmpty {
                return errors.joined(separator: "\n")
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    func readErrorBody(from bytes: URLSession.AsyncBytes, limit: Int = 4096) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit {
                break
            }
        }
        return data
    }
    
    // 4. 发送请求
    do {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        // 5. 检查 HTTP 状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            return (false, isZh ? "HTTP 响应无效" : "Invalid HTTP response.")
        }
        guard 200...299 ~= httpResponse.statusCode else {
            let data = try await readErrorBody(from: bytes)
            let message = parseRequestErrorMessage(from: data)
            let description = message == nil || message?.isEmpty == true
            ? (isZh ? "请求错误（HTTP \(httpResponse.statusCode)）" : "Request failed (HTTP \(httpResponse.statusCode)).")
            : (isZh
               ? "请求错误（HTTP \(httpResponse.statusCode)）：\(message ?? "")"
               : "Request failed (HTTP \(httpResponse.statusCode)): \(message ?? "")")
            return (false, description)
        }
        var iterator = bytes.makeAsyncIterator()
        if (try await iterator.next()) != nil {
            print("测试通过")
            return (true, nil)
        }
        return (false, isZh ? "未收到有效响应" : "No valid response received.")
    } catch {
        let message = error.localizedDescription
        return (false, isZh ? "请求失败：\(message)" : "Request failed: \(message)")
    }
}
