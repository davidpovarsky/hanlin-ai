//
//  InfoComponets.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 12/2/25.
//

import Foundation
import SwiftUI
import SwiftData

// 从Bundle获取API密钥配置
func getEnvironmentVariable(_ name: String) -> String {
    // 从Info.plist中读取配置的值
    let value = Bundle.main.object(forInfoDictionaryKey: name) as? String ?? ""
    return value
}

// 0.001 廉价；0.006 标准；

// 获得模型列表
func getModelList() -> [AllModels] {
    
    let rawModels: [AllModels] = [
        // MARK: Cherry_IN
        // 0
        AllModels(name: "openai/gpt-5-chat_repeat_cherryin", displayName: "GPT5(CherryIN)", identity: "model", position: 103, company: "CHERRY_IN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true),
        // 0
        AllModels(name: "anthropic/claude-sonnet-4.5_repeat_cherryin", displayName: "Claude-Sonnet-4.5(CherryIN)", identity: "model", position: 103, company: "CHERRY_IN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true),
        // 0
        AllModels(name: "gemini/gemini-2.5-flash_repeat_cherryin", displayName: "Gemini2.5-Flash(CherryIN)", identity: "model", position: 104, company: "CHERRY_IN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true),
        // 0
        AllModels(name: "google/gemini-2.5-pro_repeat_cherryin", displayName: "Gemini2.5-Pro(CherryIN)", identity: "model", position: 105, company: "CHERRY_IN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true),
        
        // MARK: 通义
        // 0.00015
        AllModels(name: "qwen-flash", displayName: "Qwen-Flash", identity: "model", position: 1, company: "QWEN", price: 1, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.0014
        AllModels(name: "qwen-plus", displayName: "Qwen-Plus", identity: "model", position: 2, company: "QWEN", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.0375
        AllModels(name: "qwen3-max", displayName: "Qwen3-Max", identity: "model", position: 3, company: "QWEN", price: 3, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.02575
        AllModels(name: "qwen-omni-flash", displayName: "Qwen-Omni-Flash", identity: "model", position: 3, company: "QWEN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsVoiceGen: true),
        // 0.003
        AllModels(name: "qwen3-vl-plus", displayName: "Qwen3-VL-Plus", identity: "model", position: 4, company: "QWEN", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: false, supportReasoningChange: true, supportsToolUse: true),
        // 0.003
        AllModels(name: "qwen3-vl-flash", displayName: "Qwen3-VL-Flash", identity: "model", position: 4, company: "QWEN", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: false, supportReasoningChange: true, supportsToolUse: true),
        // 0.14
        AllModels(name: "wanx2.1-t2i-turbo", displayName: "WanX2.1-Turbo", identity: "model", position: 10, company: "QWEN", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        // 0.2
        AllModels(name: "wanx2.1-t2i-plus", displayName: "WanX2.1-Plus", identity: "model", position: 11, company: "QWEN", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        // 0.25
        AllModels(name: "qwen-image-plus", displayName: "Qwen-Image-Plus", identity: "model", position: 12, company: "QWEN", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        
        // MARK: 智谱
        // 免费
        AllModels(name: "glm-4.5-flash", displayName: "GLM4.5-Flash", identity: "model", position: 11, company: "ZHIPUAI", price: 0, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        AllModels(name: "glm-4.6v-flash", displayName: "GLM4.6V-Flash", identity: "model", position: 11, company: "ZHIPUAI", price: 0, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.0014
        AllModels(name: "glm-4.5-air", displayName: "GLM4.5-Air", identity: "model", position: 11, company: "ZHIPUAI", price: 1, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.005
        AllModels(name: "glm-4.5", displayName: "GLM4.5", identity: "model", position: 11, company: "ZHIPUAI", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.005
        AllModels(name: "glm-4.7", displayName: "GLM4.7", identity: "model", position: 11, company: "ZHIPUAI", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        
        // MARK: 豆包
        // 0.0014
        AllModels(name: "doubao-seed-1-6-251015", displayName: "Doubao1.6", identity: "model", position: 11, company: "DOUBAO", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal:true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.00045
        AllModels(name: "doubao-seed-1-6-lite-251015", displayName: "Doubao1.6-Lite", identity: "model", position: 23, company: "DOUBAO", price: 1, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.0014
        AllModels(name: "doubao-seed-1-6-flash-250828", displayName: "Doubao1.6-Flash", identity: "model", position: 24, company: "DOUBAO", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal:true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        
        // MARK: Deepseek
        // 0.005
        AllModels(name: "deepseek-chat", displayName: "DeepSeek-Chat", identity: "model", position: 29, company: "DEEPSEEK", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.01
        AllModels(name: "deepseek-reasoner", displayName: "DeepSeek-Reasoner", identity: "model", position: 30, company: "DEEPSEEK", price: 3, isHidden: true, supportsSearch: true, supportsReasoning: true, supportsToolUse: true),
        
        // MARK: 百度
        // 免费
        AllModels(name: "ernie-speed-128k", displayName: "ERNIE-Speed", identity: "model", position: 31, company: "WENXIN", price: 0, isHidden: true, supportsSearch: true),
        // 0.002
        AllModels(name: "ernie-4.5-turbo-128k", displayName: "ERNIE4.5-Turbo", identity: "model", position: 32, company: "WENXIN", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.006
        AllModels(name: "ernie-4.5-turbo-vl-32k", displayName: "ERNIE4.5-Turbo-VL", identity: "model", position: 33, company: "WENXIN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.01
        AllModels(name: "ernie-4.5-8k-preview", displayName: "ERNIE4.5-Preview", identity: "model", position: 34, company: "WENXIN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.0025
        AllModels(name: "ernie-x1-turbo-32k", displayName: "ERNIE-X1-Turbo", identity: "model", position: 35, company: "WENXIN", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true),
        // 0.005
        AllModels(name: "ernie-x1-32k", displayName: "ERNIE-X1", identity: "model", position: 36, company: "WENXIN", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true),
        
        // MARK: 混元
        // 免费
        AllModels(name: "hunyuan-lite", displayName: "Hunyuan-Lite", identity: "model", position: 37, company: "HUNYUAN", price: 0, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.0014
        AllModels(name: "hunyuan-turbos-latest", displayName: "Hunyuan-TurboS", identity: "model", position: 38, company: "HUNYUAN", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.0025
        AllModels(name: "hunyuan-t1-latest", displayName: "Hunyuan-T1", identity: "model", position: 39, company: "HUNYUAN", price: 2, isHidden: true, supportsSearch: true, supportsReasoning: true),
        // 0.018
        AllModels(name: "hunyuan-vision", displayName: "Hunyuan-Vision", identity: "model", position: 40, company: "HUNYUAN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: false),
        // 0.08
        AllModels(name: "hunyuan-turbo-vision", displayName: "Hunyuan-Vision-Turbo", identity: "model", position: 41, company: "HUNYUAN", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: false),
        
        // MARK: Yi
        // 0.00099
        AllModels(name: "yi-lightning", displayName: "Yi-Light", identity: "model", position: 42, company: "YI", price: 1, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.006
        AllModels(name: "yi-vision-v2", displayName: "Yi-Vision", identity: "model", position: 43, company: "YI", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true),
        
        // MARK: Kimi
        // 0.006
        AllModels(name: "kimi-k2-0905-preview", displayName: "Kimi-K2", identity: "model", position: 44, company: "KIMI", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        
        // MARK: 阶跃星辰
        // 0.0015
        AllModels(name: "step-2-mini", displayName: "Step2-Mini", identity: "model", position: 46, company: "STEP", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.0525
        AllModels(name: "step-3", displayName: "Step3", identity: "model", position: 48, company: "STEP", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal: true),
        
        // MARK: 讯飞星火
        // 0.0015
        AllModels(name: "lite", displayName: "Spark-Lite", identity: "model", position: 50, company: "SPARK", price: 0, isHidden: true, supportsSearch: true, supportsToolUse: true),
        
        // MARK: MiniMax
        // 0.0045
        AllModels(name: "MiniMax-M2", displayName: "MiniMax-M2", identity: "model", position: 50, company: "MINIMAX", price: 2, isHidden: true, supportsSearch: true, supportsToolUse: true),
        
        // MARK: SiliconCloud
        // 0
        AllModels(name: "THUDM/GLM-4-9B-0414", displayName: "GLM-4-9B(SiliconCloud)", identity: "model", position: 54, company: "SILICONCLOUD", price: 0, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0
        AllModels(name: "Qwen/Qwen3-8B", displayName: "Qwen3-8B(SiliconCloud)", identity: "model", position: 55, company: "SILICONCLOUD", price: 0, isHidden: true, supportsSearch: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 免费
        AllModels(name: "Kwai-Kolors/Kolors", displayName: "Kolors(SiliconCloud)", identity: "model", position: 62, company: "SILICONCLOUD", price: 0, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        
        // MARK: ModelScope
        // 免费2000次/天Qwen/Qwen3-14B
        AllModels(name: "Qwen/Qwen3-30B-A3B-Instruct-2507_repeat_ms", displayName: "Qwen3-30B-A3B-Instruct-2507(ModelScope)", identity: "model", position: 63, company: "MODELSCOPE", price: 0, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 免费2000次/天
        AllModels(name: "Qwen/Qwen3-30B-A3B-Thinking-2507_repeat_ms", displayName: "Qwen3-30B-A3B-Thinking-2507(ModelScope)", identity: "model", position: 63, company: "MODELSCOPE", price: 0, isHidden: true, supportsSearch: true, supportsReasoning: true, supportsToolUse: true),
        
        // MARK: Gitee
        // 0.04/次
        AllModels(name: "GLM-4.6", displayName: "GLM-4.6(Gitee)", identity: "model", position: 70, company: "GITEE", price: 0, isHidden: true, supportsSearch: true, supportsReasoning: true, supportsToolUse: true),
        // 0.05/次
        AllModels(name: "kimi-k2-instruct", displayName: "kimi-k2-instruct(Gitee)", identity: "model", position: 71, company: "GITEE", price: 0, isHidden: true, supportsSearch: true),
        
        // MARK: GPT
        // 0.041
        AllModels(name: "gpt-5.2", displayName: "GPT5.2", identity: "model", position: 72, company: "OPENAI", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.00821
        AllModels(name: "gpt-5-mini", displayName: "GPT5-Mini", identity: "model", position: 72, company: "OPENAI", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.0016425
        AllModels(name: "gpt-5-nano", displayName: "GPT5-Nano", identity: "model", position: 72, company: "OPENAI", price: 1, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.292
        AllModels(name: "dall-e-3", displayName: "DALL-E-3", identity: "model", position: 82, company: "OPENAI", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        // 0.292
        AllModels(name: "gpt-image-1", displayName: "GPT-Image-1", identity: "model", position: 83, company: "OPENAI", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        
        // MARK: Gemini
        // 0.00146
        AllModels(name: "gemini-2.5-flash-lite", displayName: "Gemini2.0-Flash-Lite", identity: "model", position: 84, company: "GOOGLE", price: 1, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.004745
        AllModels(name: "gemini-2.5-flash", displayName: "Gemini2.5-Flash", identity: "model", position: 85, company: "GOOGLE", price: 2, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0.0136875
        AllModels(name: "gemini-2.5-pro", displayName: "Gemini2.5-Pro", identity: "model", position: 87, company: "GOOGLE", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        
        // MARK: Claude
        // 0.035
        AllModels(name: "claude-haiku-4-5", displayName: "Claude4.5-Haiku", identity: "model", position: 88, company: "ANTHROPIC", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsToolUse: true),
        // 0.0657
        AllModels(name: "claude-sonnet-4-5", displayName: "Claude4.5-Sonnet", identity: "model", position: 90, company: "ANTHROPIC", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0.0657
        AllModels(name: "claude-opus-4-5", displayName: "Claude4.5-Opus", identity: "model", position: 90, company: "ANTHROPIC", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        
        // MARK: xAI
        // 0.0657
        AllModels(name: "grok-4", displayName: "Grok4", identity: "model", position: 91, company: "XAI", price: 3, isHidden: true, supportsSearch: true, supportsReasoning: true, supportsToolUse: true),
        // 0.0657
        AllModels(name: "grok-4-fast-non-reasoning", displayName: "Grok4", identity: "model", position: 91, company: "XAI", price: 3, isHidden: true, supportsSearch: true, supportsToolUse: true),
        // 0.0657
        AllModels(name: "grok-4-fast-reasoning", displayName: "Grok4", identity: "model", position: 91, company: "XAI", price: 3, isHidden: true, supportsSearch: true, supportsReasoning: true, supportsToolUse: true),
        // 0.511
        AllModels(name: "grok-2-image", displayName: "Grok-2-Image", identity: "model", position: 97, company: "XAI", price: 3, isHidden: true, supportsTextGen: false, supportsImageGen: true),
        
        // MARK: PERPLEXITY
        // 0.0073
        AllModels(name: "sonar", displayName: "Sonar", identity: "model", position: 98, company: "PERPLEXITY", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: false),
        // 0.0657
        AllModels(name: "sonar-pro", displayName: "Sonar-Pro", identity: "model", position: 99, company: "PERPLEXITY", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: false),
        // 0.0219
        AllModels(name: "sonar-reasoning", displayName: "Sonar-Reasoning", identity: "model", position: 100, company: "PERPLEXITY", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: true),
        // 0.0365
        AllModels(name: "sonar-reasoning-pro", displayName: "Sonar-Reasoning-Pro", identity: "model", position: 101, company: "PERPLEXITY", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: true),
        // 0.0475
        AllModels(name: "sonar-deep-research", displayName: "Sonar-DeepSearch", identity: "model", position: 102, company: "PERPLEXITY", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: false, supportsReasoning: true),
        
        // MARK: OPENROUTER
        // 0
        AllModels(name: "x-ai/grok-code-fast-1_repeat_openrouter", displayName: "Grok-Code-Fast-1(OpenRouter)", identity: "model", position: 103, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true),
        // 0
        AllModels(name: "anthropic/claude-haiku-4.5_repeat_openrouter", displayName: "Claude4.5-Haiku(OpenRouter)", identity: "model", position: 103, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true),
        // 0
        AllModels(name: "anthropic/claude-sonnet-4.5_repeat_openrouter", displayName: "Claude4.5-Sonnet(OpenRouter)", identity: "model", position: 103, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportReasoningChange: true),
        // 0
        AllModels(name: "google/gemini-2.5-flash_repeat_openrouter", displayName: "Gemini2.5-Flash(OpenRouter)", identity: "model", position: 104, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true),
        // 0
        AllModels(name: "google/gemini-2.5-pro_repeat_openrouter", displayName: "Gemini2.5-Pro(OpenRouter)", identity: "model", position: 105, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true),
        // 0
        AllModels(name: "x-ai/grok-4-fast_repeat_openrouter", displayName: "Grok4-Fast(OpenRouter)", identity: "model", position: 105, company: "OPENROUTER", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true),
        
        // MARK: n1n
        // 0
        AllModels(name: "gpt-4o_repeat_n1n", displayName: "GPT-4o(n1n)", identity: "model", position: 106, company: "N1N", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsToolUse: true),
        // 0
        AllModels(name: "claude-3-5-sonnet-20240620_repeat_n1n", displayName: "Claude3.5-Sonnet(n1n)", identity: "model", position: 106, company: "N1N", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true),
        // 0
        AllModels(name: "gemini-1.5-pro-latest_repeat_n1n", displayName: "Gemini1.5-Pro(n1n)", identity: "model", position: 106, company: "N1N", price: 3, isHidden: true, supportsSearch: true, supportsMultimodal: true, supportsReasoning: true, supportsToolUse: true),
    ]
    
    // 2. 用 enumerated() 给它们重新加上正确的 position 值
    let models = rawModels.enumerated().map { (index, model) in
        // 重新构造一个 AllModels，把 position 修改为 index
        AllModels(
            name: model.name,
            displayName: model.displayName,
            identity: model.identity,
            position: index,
            company: model.company,
            price: model.price,
            isHidden: model.isHidden,
            supportsSearch: model.supportsSearch,
            supportsTextGen: model.supportsTextGen,
            supportsMultimodal: model.supportsMultimodal,
            supportsReasoning: model.supportsReasoning,
            supportReasoningChange: model.supportReasoningChange,
            supportsImageGen: model.supportsImageGen,
            supportsVoiceGen: model.supportsVoiceGen,
            supportsToolUse: model.supportsToolUse,
            systemProvision: model.systemProvision,
            icon: model.icon ?? "",
            briefDescription: model.briefDescription ?? "",
            characterDesign: model.characterDesign ?? ""
        )
    }
    return models
}

func getTestModel(for company: String) -> String {
    let models = getModelList()
    if let model = models.first(where: { $0.company?.uppercased() == company.uppercased() }) {
        let baseName = restoreBaseModelName(from: model.name ?? "Unknown")
        return baseName
    }
    return "Unknown"
}

// 获得Key列表
func getKeyList() -> [APIKeys] {
    let keys: [APIKeys] = [
        APIKeys(
            name: "CHERRY_IN_API_KEY",
            company: "CHERRY_IN",
            key: "",
            requestURL: "https://open.cherryin.net/v1/chat/completions",
            help: "https://open.cherryin.ai/console/token",
            from: .system
        ),
        APIKeys(
            name: "ZHIPUAI_API_KEY",
            company: "ZHIPUAI",
            key: "",
            requestURL: "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            help: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys",
            from: .system
        ),
        APIKeys(
            name: "DASHSCOPE_API_KEY",
            company: "QWEN",
            key: "",
            requestURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            help: "https://bailian.console.aliyun.com/?tab=model#/api-key",
            from: .system
        ),
        APIKeys(
            name: "DEEPSEEK_API_KEY",
            company: "DEEPSEEK",
            key: "",
            requestURL: "https://api.deepseek.com/v1/chat/completions",
            help: "https://platform.deepseek.com/api_keys",
            from: .system
        ),
        APIKeys(
            name: "SILICONCLOUD_API_KEY",
            company: "SILICONCLOUD",
            key: "",
            requestURL: "https://api.siliconflow.cn/v1/chat/completions",
            help: "https://cloud.siliconflow.cn/account/ak",
            from: .system
        ),
        APIKeys(
            name: "ARK_API_KEY",
            company: "DOUBAO",
            key: "",
            requestURL: "https://ark.cn-beijing.volces.com/api/v3/chat/completions",
            help: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D",
            from: .system
        ),
        APIKeys(
            name: "KIMI_API_KEY",
            company: "KIMI",
            key: "",
            requestURL: "https://api.moonshot.cn/v1/chat/completions",
            help: "https://platform.moonshot.cn/console/api-keys",
            from: .system
        ),
        APIKeys(
            name: "OPENAI_API_KEY",
            company: "OPENAI",
            key: "",
            requestURL: "https://api.openai.com/v1/chat/completions",
            help: "https://platform.openai.com/api-keys",
            from: .system
        ),
        APIKeys(
            name: "GEMINI_API_KEY",
            company: "GOOGLE",
            key: "",
            requestURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            help: "https://aistudio.google.com/apikey",
            from: .system
        ),
        APIKeys(
            name: "XAI_API_KEY",
            company: "XAI",
            key: "",
            requestURL: "https://api.x.ai/v1/chat/completions",
            help: "https://console.x.ai/team/c4aa1fe8-2617-4255-a78f-03d9572d1110/api-keys",
            from: .system
        ),
        APIKeys(
            name: "ANTHROPIC_API_KEY",
            company: "ANTHROPIC",
            key: "",
            requestURL: "https://api.anthropic.com/v1/chat/completions",
            from: .system
        ),
        APIKeys(
            name: "YI_API_KEY",
            company: "YI",
            key: "",
            requestURL: "https://api.lingyiwanwu.com/v1/chat/completions",
            help: "https://platform.lingyiwanwu.com/apikeys",
            from: .system
        ),
        APIKeys(
            name: "HUNYUAN_API_KEY",
            company: "HUNYUAN",
            key: "",
            requestURL: "https://api.hunyuan.cloud.tencent.com/v1/chat/completions",
            help: "https://cloud.tencent.com/document/product/1729/111008",
            from: .system
        ),
        APIKeys(
            name: "STEP_API_KEY",
            company: "STEP",
            key: "",
            requestURL: "https://api.stepfun.com/v1/chat/completions",
            help: "https://platform.stepfun.com/interface-key",
            from: .system
        ),
        APIKeys(
            name: "WENXIN_API_KEY",
            company: "WENXIN",
            key: "",
            requestURL: "https://qianfan.baidubce.com/v2/chat/completions",
            help: "https://console.bce.baidu.com/iam/#/iam/accesslist",
            from: .system
        ),
        APIKeys(
            name: "PERPLEXITY_API_KEY",
            company: "PERPLEXITY",
            key: "",
            requestURL: "https://api.perplexity.ai/chat/completions",
            help: "https://www.perplexity.ai/account/api/keys",
            from: .system
        ),
        APIKeys(
            name: "OPENROUTER_API_KEY",
            company: "OPENROUTER",
            key: "",
            requestURL: "https://openrouter.ai/api/v1/chat/completions",
            help: "https://openrouter.ai/settings/keys",
            from: .system
        ),
        APIKeys(
            name: "MODELSCOPE_API_KEY",
            company: "MODELSCOPE",
            key: "",
            requestURL: "https://api-inference.modelscope.cn/v1/chat/completions",
            help: "https://modelscope.cn/my/myaccesstoken",
            from: .system
        ),
        APIKeys(
            name: "GITEE_API_KEY",
            company: "GITEE",
            key: "",
            requestURL: "https://ai.gitee.com/v1/chat/completions",
            from: .system
        ),
        APIKeys(
            name: "MINIMAX_API_KEY",
            company: "MINIMAX",
            key: "",
            requestURL: "https://api.minimax.chat/v1/text/chatcompletion_v2",
            help: "https://platform.minimaxi.com/user-center/basic-information/interface-key",
            from: .system
        ),
        APIKeys(
            name: "MIMO_API_KEY",
            company: "MIMO",
            key: "",
            requestURL: "https://api.xiaomimimo.com/v1/chat/completions",
            help: "https://platform.xiaomimimo.com/#/console/api-keys",
            from: .system
        ),
        APIKeys(
            name: "LONGCAT_API_KEY",
            company: "LONGCAT",
            key: "",
            requestURL: "https://api.longcat.chat/openai/v1/chat/completions",
            help: "https://longcat.chat/platform/api_keys",
            from: .system
        ),
        APIKeys(
            name: "AI302_API_KEY",
            company: "AI302",
            key: "",
            requestURL: "https://api.302.ai/v1/chat/completions",
            help: "https://302.ai/apis/list",
            from: .system
        ),
        APIKeys(
            name: "AIHUBMIX_API_KEY",
            company: "AIHUBMIX",
            key: "",
            requestURL: "https://aihubmix.com/v1/chat/completions",
            help: "https://console.aihubmix.com/token",
            from: .system
        ),
        APIKeys(
            name: "POE_API_KEY",
            company: "POE",
            key: "",
            requestURL: "https://api.poe.com/v1/chat/completions",
            help: "https://poe.com/api/keys",
            from: .system
        ),
        APIKeys(
            name: "IFLOW_API_KEY",
            company: "IFLOW",
            key: "",
            requestURL: "https://apis.iflow.cn/v1/chat/completions",
            help: "https://platform.iflow.cn/profile?tab=apiKey",
            from: .system
        ),
        APIKeys(
            name: "N1N_API_KEY",
            company: "N1N",
            key: "",
            requestURL: "https://api.n1n.ai/v1/chat/completions",
            help: "https://n1n.ai",
            from: .system
        ),
        APIKeys(
            name: "LAN",
            company: "LAN",
            key: "",
            requestURL: "http://127.0.0.1:1234/v1/chat/completions",
            from: .system
        ),
        APIKeys(
            name: "LOCAL",
            company: "LOCAL",
            key: "LOCAL",
            requestURL: "LOCAL",
            from: .system
        )
    ]
    return keys
}

func getSearchKeyList() -> [SearchKeys] {
    let keys: [SearchKeys] = [
        SearchKeys(
            name: "ZHIPUAI_SEARCH_KEY",
            company: "ZHIPUAI",
            key: "",
            requestURL: "https://open.bigmodel.cn/api/paas/v4/web_search",
            price: 0.01,
            isUsing: false,
            help: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys"
        ),
        SearchKeys(
            name: "BOCHAAI_SEARCH_KEY",
            company: "BOCHAAI",
            key: "",
            requestURL: "https://api.bochaai.com/v1/web-search",
            price: 0.036,
            isUsing: false,
            help: "https://open.bochaai.com/api-keys"
        ),
        SearchKeys(
            name: "LANGSEARCH_SEARCH_KEY",
            company: "LANGSEARCH",
            key: "",
            requestURL: "https://api.langsearch.com/v1/web-search",
            price: 0,
            isUsing: false,
            help: "https://langsearch.com/api-keys"
        ),
        SearchKeys(
            name: "EXA_KEY",
            company: "EXA",
            key: "",
            requestURL: "https://api.exa.ai/search",
            price: 0.0365,
            isUsing: false,
            help: "https://dashboard.exa.ai/api-keys"
        ),
        SearchKeys(
            name: "TAVILY_KEY",
            company: "TAVILY",
            key: "",
            requestURL: "https://api.tavily.com/search",
            price: 0.0584,
            isUsing: false,
            help: "https://app.tavily.com/home"
        ),
        SearchKeys(
            name: "BRAVE_KEY",
            company: "BRAVE",
            key: "",
            requestURL: "https://api.search.brave.com/res/v1/web/search",
            price: 0.0219,
            isUsing: false,
            help: "https://api-dashboard.search.brave.com/app/keys"
        ),
        SearchKeys(
            name: "PERPLEXITY_KEY",
            company: "PERPLEXITY",
            key: "",
            requestURL: "https://api.perplexity.ai/search",
            price: 0.005,
            isUsing: false,
            help: "https://www.perplexity.ai/account/api/keys"
        ),
    ]
    return keys
}

// 工具列表
func getToolKeyList() -> [ToolKeys] {
    let keys: [ToolKeys] = [
        ToolKeys(
            name: "APPLE_MAP_KEY",
            company: "APPLEMAP",
            key: "APPLEMAP",
            requestURL: "https://applemap.com",
            price: 0,
            isUsing: true,
            toolClass: "map",
            help: "map"
        ),
        ToolKeys(
            name: "AMAP_MAP_KEY",
            company: "AMAP",
            key: "",
            requestURL: "https://restapi.amap.com",
            price: 0,
            isUsing: false,
            toolClass: "map",
            help: "https://console.amap.com/dev/key/app"
        ),
        ToolKeys(
            name: "GOOGLE_MAP_KEY",
            company: "GOOGLEMAP",
            key: "",
            requestURL: "https://places.googleapis.com",
            price: 0,
            isUsing: false,
            toolClass: "map",
            help: "https://console.cloud.google.com/google/maps-apis"
        ),
        ToolKeys(
            name: "QWEATHER_KEY",
            company: "QWEATHER",
            key: "",
            requestURL: "",
            price: 0,
            isUsing: false,
            toolClass: "weather",
            help: "https://console.qweather.com/project?lang=zh"
        ),
        ToolKeys(
            name: "OPENWEATHER_KEY",
            company: "OPENWEATHER",
            key: "",
            requestURL: "api.openweathermap.org",
            price: 0,
            isUsing: false,
            toolClass: "weather",
            help: "https://home.openweathermap.org/api_keys"
        ),
    ]
    return keys
}

// 获得图标
func getIconList() -> [String] {
    let availableIcons: [String] = [
        "bubble.left.circle", "circle", "circle.circle", "circle.dotted.circle", "circle.hexagongrid.circle", "circle.dotted",
        "circle.dashed", "pencil.circle", "trash.circle", "folder.circle", "paperplane.circle", "tray.circle", "archivebox.circle",
        "document.circle", "calendar.circle", "backpack.circle", "paperclip.circle", "link.circle", "personalhotspot.circle",
        "person.circle", "sportscourt.circle", "soccerball.circle", "baseball.circle", "basketball.circle", "rugbyball.circle",
        "tennisball.circle", "volleyball.circle", "trophy.circle", "command.circle", "restart.circle", "sleep.circle", "wake.circle",
        "power.circle", "eject.circle", "sunrise.circle", "sunset.circle", "moon.circle", "moonrise.circle", "moonset.circle",
        "cloud.circle", "smoke.circle", "wind.circle", "snowflake.circle", "tornado.circle", "tropicalstorm.circle",
        "hurricane.circle", "drop.circle", "flame.circle", "play.circle", "pause.circle", "stop.circle", "record.circle",
        "playpause.circle", "backward.circle", "forward.circle", "shuffle.circle", "repeat.circle", "infinity.circle", "sos.circle",
        "speaker.circle", "magnifyingglass.circle", "microphone.circle", "smallcircle.circle", "circle.grid.3x3.circle",
        "diamond.circle", "heart.circle", "star.circle", "flag.circle", "location.circle", "bell.circle", "tag.circle", "bolt.circle",
        "camera.circle", "bubble.circle", "phone.circle", "envelope.circle", "gear.circle", "gearshape.circle", "scissors.circle",
        "ellipsis.circle", "bag.circle", "cart.circle", "creditcard.circle", "hammer.circle", "stethoscope.circle", "handbag.circle",
        "briefcase.circle", "theatermasks.circle", "house.circle", "storefront.circle", "lightbulb.circle", "popcorn.circle",
        "washer.circle", "dryer.circle", "dishwasher.circle", "toilet.circle", "tent.circle", "lock.circle", "wifi.circle", "pin.circle",
        "mappin.circle", "map.circle", "headphones.circle", "headset.circle", "tv.circle", "airplane.circle", "car.circle", "tram.circle",
        "sailboat.circle", "bicycle.circle", "parkingsign.circle", "fuelpump.circle", "steeringwheel.circle", "abs.circle", "mph.circle",
        "kph.circle", "tsa.circle", "2h.circle", "4h.circle", "4l.circle", "4a.circle", "microbe.circle", "pill.circle", "pills.circle",
        "cross.circle", "staroflife.circle", "hare.circle", "tortoise.circle", "dog.circle", "cat.circle", "lizard.circle", "bird.circle",
        "ant.circle", "ladybug.circle", "fish.circle", "pawprint.circle", "leaf.circle", "tree.circle", "tshirt.circle", "shoe.circle",
        "film.circle", "eye.circle", "viewfinder.circle", "photo.circle", "shippingbox.circle", "clock.circle", "timer.circle",
        "square.circle", "triangle.circle", "l1.circle", "lb.circle", "l2.circle", "lt.circle", "r1.circle", "rb.circle", "r2.circle",
        "rt.circle", "gamecontroller.circle", "waveform.circle", "gift.circle", "hourglass.circle", "purchased.circle", "grid.circle",
        "recordingtape.circle", "binoculars.circle", "character.circle", "info.circle", "at.circle", "questionmark.circle",
        "exclamationmark.circle", "plus.circle", "minus.circle", "plusminus.circle", "multiply.circle", "divide.circle", "equal.circle",
        "notequal.circle", "lessthan.circle", "lessthanorequalto.circle", "greaterthan.circle", "greaterthanorequalto.circle",
        "number.circle", "checkmark.circle", "slash.circle", "left.circle", "right.circle", "a.circle", "b.circle", "c.circle",
        "d.circle", "e.circle", "f.circle", "g.circle", "h.circle", "i.circle", "j.circle", "k.circle", "l.circle", "m.circle",
        "n.circle", "o.circle", "p.circle", "q.circle", "r.circle", "s.circle", "t.circle", "u.circle", "v.circle", "w.circle",
        "x.circle", "y.circle", "z.circle", "australsign.circle", "australiandollarsign.circle", "bahtsign.circle", "bitcoinsign.circle",
        "brazilianrealsign.circle", "cedisign.circle", "centsign.circle", "chineseyuanrenminbisign.circle",
        "coloncurrencysign.circle", "cruzeirosign.circle", "danishkronesign.circle", "dongsign.circle", "dollarsign.circle",
        "eurosign.circle", "eurozonesign.circle", "florinsign.circle", "francsign.circle", "guaranisign.circle", "hryvniasign.circle",
        "indianrupeesign.circle", "kipsign.circle", "larisign.circle", "lirasign.circle", "malaysianringgitsign.circle",
        "manatsign.circle", "millsign.circle", "nairasign.circle", "norwegiankronesign.circle",
        "peruviansolessign.circle", "pesetasign.circle", "pesosign.circle", "polishzlotysign.circle",
        "rublesign.circle", "rupeesign.circle", "shekelsign.circle", "singaporedollarsign.circle", "sterlingsign.circle",
        "swedishkronasign.circle", "tengesign.circle", "tugriksign.circle", "turkishlirasign.circle", "wonsign.circle", "yensign.circle",
        "0.circle", "1.circle", "2.circle", "3.circle", "4.circle", "5.circle", "6.circle", "7.circle", "8.circle", "9.circle",
        "00.circle", "01.circle", "02.circle", "03.circle", "04.circle", "05.circle", "06.circle",
        "07.circle", "08.circle", "09.circle", "10.circle", "trash.slash.circle", "xmark.bin.circle", "apple.terminal.circle",
        "11.circle", "12.circle", "13.circle", "14.circle", "15.circle", "16.circle", "17.circle", "18.circle",
        "19.circle", "20.circle", "21.circle", "22.circle", "23.circle", "24.circle", "25.circle", "26.circle",
        "27.circle", "28.circle", "29.circle", "30.circle", "31.circle", "32.circle", "33.circle", "34.circle",
        "35.circle", "36.circle", "37.circle", "38.circle", "39.circle", "40.circle", "41.circle", "42.circle",
        "43.circle", "44.circle", "45.circle", "46.circle", "47.circle", "48.circle", "49.circle", "50.circle",
        "arrowshape.left.circle", "arrowshape.backward.circle", "arrowshape.right.circle", "arrowshape.forward.circle",
        "arrowshape.up.circle", "arrowshape.down.circle", "books.vertical.circle", "book.closed.circle",
        "person.2.circle", "person.crop.circle", "person.crop.circle.dashed", "photo.artframe.circle",
        "person.bust.circle", "figure.2.circle", "figure.walk.circle", "figure.wave.circle",
        "figure.fall.circle", "figure.run.circle", "figure.roll.circle", "figure.archery.circle",
        "figure.badminton.circle", "figure.barre.circle", "figure.baseball.circle", "figure.basketball.circle",
        "figure.bowling.circle", "figure.boxing.circle", "figure.climbing.circle", "figure.cooldown.circle",
        "figure.cricket.circle", "figure.curling.circle", "figure.dance.circle", "figure.elliptical.circle",
        "figure.fencing.circle", "figure.fishing.circle", "figure.flexibility.circle", "figure.golf.circle",
        "figure.gymnastics.circle", "figure.handball.circle", "figure.hiking.circle", "figure.hockey.circle",
        "figure.hunting.circle", "figure.jumprope.circle", "figure.kickboxing.circle", "figure.lacrosse.circle",
        "figure.pickleball.circle", "figure.pilates.circle", "figure.play.circle", "figure.racquetball.circle",
        "figure.rolling.circle", "figure.rugby.circle", "figure.sailing.circle", "figure.skateboarding.circle",
        "figure.snowboarding.circle", "figure.socialdance.circle", "figure.softball.circle", "figure.squash.circle",
        "figure.stairs.circle", "figure.surfing.circle", "figure.taichi.circle", "figure.tennis.circle",
        "figure.volleyball.circle", "figure.waterpolo.circle", "figure.wrestling.circle", "figure.yoga.circle",
        "american.football.circle", "australian.football.circle", "tennis.racket.circle",
        "hockey.puck.circle", "cricket.ball.circle", "sun.max.circle", "sun.horizon.circle", "sun.dust.circle",
        "sun.haze.circle","sun.rain.circle", "sun.snow.circle", "moon.dust.circle", "moon.haze.circle", "moon.stars.circle",
        "cloud.rain.circle", "cloud.heavyrain.circle", "cloud.fog.circle", "cloud.hail.circle", "cloud.snow.circle",
        "cloud.sleet.circle", "cloud.bolt.circle", "cloud.sun.circle", "cloud.moon.circle", "cloud.drizzle.circle",
        "wind.snow.circle", "thermometer.sun.circle", "thermometer.snowflake.circle", "backward.end.circle", "forward.end.circle",
        "repeat.1.circle", "speaker.slash.circle", "music.microphone.circle", "microphone.slash.circle", "swirl.circle.righthalf.filled",
        "circle.lefthalf.striped.horizontal", "heart.slash.circle", "flag.slash.circle",
        "location.slash.circle", "location.north.circle", "bell.slash.circle", "bell.badge.circle",
        "bolt.slash.circle", "bolt.horizontal.circle", "flashlight.off.circle", "flashlight.on.circle",
        "flashlight.slash.circle", "bubble.right.circle", "exclamationmark.bubble.circle",
        "phone.down.circle", "cross.case.circle", "building.columns.circle", "bed.double.circle", "tent.2.circle",
        "house.lodge.circle", "signpost.left.circle", "signpost.right.circle", "mountain.2.circle",
        "wifi.exclamationmark.circle", "mappin.slash.circle", "rotate.3d.circle",
        "bolt.car.circle", "figure.child.circle", "ladybug.slash.circle", "camera.macro.circle", "eye.slash.circle",
        "hand.raised.circle", "hand.thumbsup.circle", "hand.thumbsdown.circle", "f.cursive.circle", "fork.knife.circle",
        "battery.100percent.circle", "list.bullet.circle", "chevron.left.circle", "chevron.backward.circle", "chevron.right.circle",
        "chevron.forward.circle", "chevron.up.circle", "chevron.down.circle", "arrow.left.circle", "arrow.backward.circle",
        "arrow.right.circle", "arrow.forward.circle", "arrow.up.circle", "arrow.down.circle",
        "arrow.clockwise.circle", "arrow.counterclockwise.circle", "arrowtriangle.left.circle", "arrowtriangle.backward.circle",
        "arrowtriangle.right.circle", "arrowtriangle.forward.circle", "arrowtriangle.up.circle", "arrowtriangle.down.circle",
        "square.and.pencil.circle", "figure.run.treadmill.circle", "figure.walk.treadmill.circle", "figure.roll.runningpace.circle",
        "figure.american.football.circle", "figure.australian.football.circle", "figure.core.training.circle",
        "figure.cross.training.circle", "figure.skiing.crosscountry.circle", "figure.skiing.downhill.circle",
        "figure.disc.sports.circle", "figure.equestrian.sports.circle", "figure.strengthtraining.traditional.circle",
        "figure.hand.cycling.circle", "figure.highintensity.intervaltraining.circle", "figure.field.hockey.circle",
        "figure.ice.hockey.circle", "figure.indoor.cycle.circle", "figure.martial.arts.circle", "figure.mixed.cardio.circle",
        "figure.outdoor.cycle.circle", "oar.2.crossed.circle", "figure.pool.swim.circle", "figure.indoor.rowing.circle",
        "figure.outdoor.rowing.circle", "figure.ice.skating.circle", "figure.indoor.soccer.circle", "figure.outdoor.soccer.circle",
        "figure.stair.stepper.circle", "figure.step.training.circle", "figure.table.tennis.circle",
        "figure.water.fitness.circle", "figure.strengthtraining.functional.circle",
        "cloud.bolt.rain.circle", "cloud.sun.rain.circle", "cloud.sun.bolt.circle",
        "cloud.moon.rain.circle", "cloud.moon.bolt.circle",
        "circle.fill", "american.football.professional.circle", "speaker.wave.2.circle",
        "swirl.circle.righthalf.filled", "flag.pattern.checkered.circle", "flag.2.crossed.circle",
        "rectangle.on.rectangle.circle", "house.and.flag.circle", "mappin.and.ellipse.circle",
        "building.2.crop.circle", "arrow.up.left.circle", "arrow.up.backward.circle", "arrow.up.right.circle", "arrow.up.forward.circle",
        "arrow.down.left.circle", "arrow.down.backward.circle", "arrow.down.right.circle", "arrow.down.forward.circle",
        "arrow.uturn.left.circle", "arrow.uturn.backward.circle", "arrow.uturn.right.circle",
        "arrow.uturn.forward.circle", "arrow.uturn.up.circle", "arrow.uturn.down.circle",
        "arrowshape.turn.up.left.circle", "arrowshape.turn.up.backward.circle",
        "arrowshape.turn.up.right.circle", "arrowshape.turn.up.forward.circle",
        "figure.track.and.field.circle", "thermometer.variable.and.figure.circle",
        "rectangle.on.rectangle.slash.circle", "play.rectangle.on.rectangle.circle",
        "phone.arrow.up.right.circle", "signpost.right.and.left.circle", "signpost.and.arrowtriangle.up.circle",
        "chart.line.uptrend.xyaxis.circle", "chart.line.downtrend.xyaxis.circle", "chart.line.flattrend.xyaxis.circle",
        "line.3.horizontal.decrease.circle", "line.2.horizontal.decrease.circle",
        "arrow.left.and.right.circle", "arrow.up.and.down.circle", "arrow.up.to.line.circle",
        "arrow.down.to.line.circle", "arrow.left.to.line.circle", "arrow.backward.to.line.circle",
        "arrow.right.to.line.circle", "arrow.forward.to.line.circle", "antenna.radiowaves.left.and.right.circle", "sleep.circle"
    ]
    return availableIcons
}

func getColorList() -> [Color] {
    return [
        // HL 系列颜色（按图中顺序）
        .hlBlue,
        .hlAutumn,
        .hlAzure,
        .hlBrown,
        .hlCyanite,
        .hlGray,
        .hlGreen,
        .hlIndigo,
        .hlNavy,
        .hlOrange,
        .hlPink,
        .hlPlum,
        .hlPurple,
        .hlRed,
        .hlSpring,
        .hlTeal,
        .hlYellow,

        // 系统标准色
        .blue,
        .red,
        .green,
        .orange,
        .purple,
        .pink,
        .yellow,
        .indigo,
        .cyan,
        .mint,
        .teal,
        .brown,
        .gray
    ]
}

extension Color {
    static func from(name: String) -> Color {
        switch name.lowercased() {
        case "blue": return .blue
        case "red": return .red
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "yellow": return .yellow
        case "indigo": return .indigo
        case "cyan": return .cyan
        case "mint": return .mint
        case "teal": return .teal
        case "brown": return .brown
        case "gray": return .gray
        case "hlautumn": return .hlAutumn
        case "hlazure": return .hlAzure
        case "hlblue": return .hlBlue
        case "hlbrown": return .hlBrown
        case "hlcyanite": return .hlCyanite
        case "hlgray": return .hlGray
        case "hlgreen": return .hlGreen
        case "hlindigo": return .hlIndigo
        case "hlnavy": return .hlNavy
        case "hlorange": return .hlOrange
        case "hlpink": return .hlPink
        case "hlplum": return .hlPlum
        case "hlpurple": return .hlPurple
        case "hlred": return .hlRed
        case "hlspring": return .hlSpring
        case "hlteal": return .hlTeal
        case "hlyellow": return .hlYellow
        default: return .hlBlue // 默认颜色
        }
    }
}

extension Color {
    var name: String {
        switch self {
        case .blue: return "blue"
        case .red: return "red"
        case .green: return "green"
        case .orange: return "orange"
        case .purple: return "purple"
        case .pink: return "pink"
        case .yellow: return "yellow"
        case .indigo: return "indigo"
        case .cyan: return "cyan"
        case .mint: return "mint"
        case .teal: return "teal"
        case .brown: return "brown"
        case .gray: return "gray"
        case .hlAutumn: return "hlAutumn"
        case .hlAzure: return "hlAzure"
        case .hlBlue: return "hlBlue"
        case .hlBrown: return "hlBrown"
        case .hlCyanite: return "hlCyanite"
        case .hlGray: return "hlGray"
        case .hlGreen: return "hlGreen"
        case .hlIndigo: return "hlIndigo"
        case .hlNavy: return "hlNavy"
        case .hlOrange: return "hlOrange"
        case .hlPink: return "hlPink"
        case .hlPlum: return "hlPlum"
        case .hlPurple: return "hlPurple"
        case .hlRed: return "hlRed"
        case .hlSpring: return "hlSpring"
        case .hlTeal: return "hlTeal"
        case .hlYellow: return "hlYellow"
        default: return "hlBlue" // 默认颜色名称
        }
    }
}
    

// 根据公司名称获取对应的图标
func getCompanyIcon(for companyName: String) -> String {
    let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
    switch companyName {
    case "HANLIN":
        return "hanlin"
    case "HANLIN_OPEN":
        return "hanlin"
    case "ZHIPUAI":
        return isDarkMode ? "zhipuai_dark" : "zhipuai"
    case "QWEN":
        return "qwen"
    case "DEEPSEEK":
        return "deepseek"
    case "SILICONCLOUD":
        return "siliconflow"
    case "GITHUB":
        return isDarkMode ? "github_dark" : "github"
    case "DOUBAO":
        return "doubao"
    case "KIMI":
        return isDarkMode ? "kimi_dark" : "kimi"
    case "OPENAI":
        return isDarkMode ? "openai_dark" : "openai"
    case "GOOGLE":
        return "google"
    case "GOOGLE_SEARCH":
        return "google_search"
    case "XAI":
        return isDarkMode ? "xai_dark" : "xai"
    case "ANTHROPIC":
        return "claude"
    case "LOCAL":
        return "assistant"
    case "MODELSCOPE":
        return "modelscope"
    case "LAN":
        return isDarkMode ? "lm_studio_dark" : "lm_studio"
    case "WENXIN":
        return "wenxin"
    case "YI":
        return isDarkMode ? "yi_dark" : "yi"
    case "HUNYUAN":
        return "hunyuan"
    case "STEP":
        return "step"
    case "BOCHAAI":
        return "bochaai"
    case "BING":
        return "bing"
    case "EXA":
        return "exa"
    case "TAVILY":
        return "tavily"
    case "LANGSEARCH":
        return "langsearch"
    case "TIANGONG":
        return "tiangong"
    case "SPARK":
        return "spark"
    case "PERPLEXITY":
        return "perplexity"
    case "OPENROUTER":
        return isDarkMode ? "openrouter_dark" : "openrouter"
    case "HANLINWEB":
        return "webreader"
    case "HANLINBAG":
        return "knowledge_bag"
    case "BRAVE":
        return "brave"
    case "SIRI":
        return "siri"
    case "GITEE":
        return isDarkMode ? "gitee_dark" : "gitee"
    case "APPLEMAP":
        return "applemap"
    case "AMAP":
        return "amap"
    case "BAIDUMAP":
        return "baidumap"
    case "GOOGLEMAP":
        return "googlemap"
    case "ARXIV":
        return "arxiv"
    case "QWEATHER":
        return isDarkMode ? "qweather_dark" : "qweather"
    case "OPENWEATHER":
        return "openweather"
    case "MINIMAX":
        return "minimax"
    case "CHERRY_IN":
        return "cherry"
    case "MIMO":
        return isDarkMode ? "mimo_dark" : "mimo"
    case "LONGCAT":
        return isDarkMode ? "longcat_dark" : "longcat"
    case "AI302":
        return "ai302"
    case "POE":
        return isDarkMode ? "poe_dark" : "poe"
    case "AIHUBMIX":
        return "aihubmix"
    case "IFLOW":
        return "iflow"
    case "N1N":
        return "n1n"
    default:
        return "defaultIcon" // 默认图标名称
    }
}

func getCompanyName(for companyName: String) -> String {
    let key = "company_\(companyName.uppercased())" // 生成动态 key
    let localizedName = NSLocalizedString(key, tableName: "Localizable", bundle: .main, value: "未知", comment: "Company Name")
    return localizedName
}

// 重载函数：处理 APIKeys 对象，自定义供应商显示其名称
func getCompanyName(for apiKey: APIKeys) -> String {
    // 如果是自定义供应商，直接返回其名称
    if apiKey.from == .custom {
        return apiKey.name ?? "自定义供应商"
    }
    // 否则使用原有的本地化逻辑
    return getCompanyName(for: apiKey.company ?? "Unknown")
}

func priceText(for price: Int16) -> String {
    let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
    
    if currentLanguage.hasPrefix("zh") {
        switch price {
        case 0: return "免费"
        case 1: return "廉价"
        case 2: return "适中"
        default: return "昂贵"
        }
    } else {
        switch price {
        case 0: return "Free"
        case 1: return "Cheap"
        case 2: return "Moderate"
        default: return "Expensive"
        }
    }
}

func priceColor(for price: Int16) -> Color {
    switch price {
    case 0: return .green
    case 1: return .yellow
    case 2: return .orange
    default: return .red
    }
}

func gradient(for index: Int) -> LinearGradient {
    switch index % 8 {
    case 0:
        return LinearGradient(
            gradient: Gradient(colors: [Color.hlBlue, Color.hlPurple]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 1:
        return LinearGradient(
            gradient: Gradient(colors: [Color.red, Color.orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 2:
        return LinearGradient(
            gradient: Gradient(colors: [Color.green, Color.yellow]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 3:
        return LinearGradient(
            gradient: Gradient(colors: [Color.pink, Color.blue]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 4:
        return LinearGradient(
            gradient: Gradient(colors: [Color.teal, Color.indigo]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 5:
        return LinearGradient(
            gradient: Gradient(colors: [Color.mint, Color.cyan]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    case 6:
        return LinearGradient(
            gradient: Gradient(colors: [Color.orange, Color.pink]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    default:
        return LinearGradient(
            gradient: Gradient(colors: [Color.purple, Color.red]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 还原 Agent 模型名为基座模型名
func restoreBaseModelName(from agentModelName: String) -> String {
    // 1. 去掉 "_agent_<UUID>" 部分
    guard let baseName = agentModelName.components(separatedBy: "_agent_").first else {
        return agentModelName
    }
    guard let baseName = baseName.components(separatedBy: "_repeat_").first else {
        return baseName
    }
    if baseName.hasSuffix("_hanlin") {
        return String(baseName.dropLast("_hanlin".count))
    } else {
        return baseName
    }
}

struct EmbeddingModel: Identifiable {
    let id = UUID()
    var name: String          // 模型名称（如 text-embedding-v3）
    var displayName: String   // 显示名称
    var company: String       // 公司名称（如 阿里云 / OpenAI）
    var dimension: Int        // 向量维度（如 1024）
    var requestURL: String    // 嵌入请求的 URL
    var price: Double         // 单次调用价格（如 0.0001 / 每千 tokens）
}

func getEmbeddingModelList() -> [EmbeddingModel] {
    let models: [EmbeddingModel] = [
        EmbeddingModel(
            name: "BAAI/bge-m3",
            displayName: "BAAI/bge-m3",
            company: "SILICONCLOUD",
            dimension: 1024,
            requestURL: "https://api.siliconflow.cn/v1/embeddings",
            price: 0
        ),
        EmbeddingModel(
            name: "text-embedding-v3",
            displayName: "Qwen-Embedding-V3",
            company: "QWEN",
            dimension: 1024,
            requestURL: "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings",
            price: 0.0005
        ),
        EmbeddingModel(
            name: "embedding-3",
            displayName: "GLM-Embedding-3",
            company: "ZHIPUAI",
            dimension: 1024,
            requestURL: "https://open.bigmodel.cn/api/paas/v4/embeddings",
            price: 0.0005
        ),
        EmbeddingModel(
            name: "doubao-embedding-text-240715",
            displayName: "Doubao-Embedding",
            company: "DOUBAO",
            dimension: 1024,
            requestURL: "https://ark.cn-beijing.volces.com/api/v3/embeddings",
            price: 0.0005
        ),
        EmbeddingModel(
            name: "text-embedding-3-large",
            displayName: "OpenAI-Embedding3-Large",
            company: "OPENAI",
            dimension: 1024,
            requestURL: "https://api.openai.com/v1/embeddings",
            price: 0.000949
        ),
        EmbeddingModel(
            name: "text-embedding-3-small",
            displayName: "OpenAI-Embedding3-Small",
            company: "OPENAI",
            dimension: 1024,
            requestURL: "https://api.openai.com/v1/embeddings",
            price: 0.000146
        ),
    ]
    return models
}

/// 模拟获取语音模型列表，仅支持 Siri 和 gpt-4o-mini-tts
func getTTSModelList() -> [EmbeddingModel] {
    let models: [EmbeddingModel] = [
        EmbeddingModel(
            name: "Siri",
            displayName: "Siri",
            company: "SIRI",
            dimension: 0,
            requestURL: "",
            price: 0
        ),
        EmbeddingModel(
            name: "gpt-4o-mini-tts",
            displayName: "GPT-4o-mini-TTS",
            company: "OPENAI",
            dimension: 0,
            requestURL: "https://api.openai.com/v1/audio/speech",
            price: 0.0876
        ),
        EmbeddingModel(
            name: "tts-1",
            displayName: "OpenAI-TTS-1",
            company: "OPENAI",
            dimension: 0,
            requestURL: "https://api.openai.com/v1/audio/speech",
            price: 0.1095
        ),
        EmbeddingModel(
            name: "tts-1-hd",
            displayName: "OpenAI-TTS-1-HD",
            company: "OPENAI",
            dimension: 0,
            requestURL: "https://api.openai.com/v1/audio/speech",
            price: 0.2190
        ),
        EmbeddingModel(
            name: "FunAudioLLM/CosyVoice2-0.5B",
            displayName: "FunAudioLLM/CosyVoice2-0.5B",
            company: "SILICONCLOUD",
            dimension: 0,
            requestURL: "https://api.siliconflow.cn/v1/audio/speech",
            price: 0.15
        ),
        EmbeddingModel(
            name: "qwen-tts",
            displayName: "Qwen-TTS",
            company: "QWEN",
            dimension: 0,
            requestURL: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
            price: 0.0174
        ),
    ]
    return models
}

// 时间标准化
func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = .current
    return formatter.string(from: date)
}

/// 把 Markdown 字符串转换成易粘贴的纯文本
func markdownToPlainText(_ markdown: String) -> String {

    // MARK: - 正则缓存（首次调用时才创建）
    struct RX {
        static let codeFence  = try! NSRegularExpression(pattern: #"^\s*(```|~~~)"#)
        static let hr         = try! NSRegularExpression(pattern: #"^(\s*[-*_]\s*){3,}$"#)
        static let tableSep   = try! NSRegularExpression(pattern: #"^\|[\s\-:|]+\|$"#)
        static let tablePipe  = try! NSRegularExpression(pattern: #"(?<=\S)\s*\|\s*(?=\S)"#)
        static let heading    = try! NSRegularExpression(pattern: #"^\s{0,3}#{1,6}\s*"#)
        static let listDash   = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s+"#)
        static let blockQuote = try! NSRegularExpression(pattern: #"^\s*>\s*"#)
        static let inlineCode = try! NSRegularExpression(pattern: #"`+([^`]+?)`+"#)
        static let strong     = try! NSRegularExpression(pattern: #"\*\*(.*?)\*\*|__(.*?)__"#)
        static let em         = try! NSRegularExpression(pattern: #"\*(.*?)\*|_(.*?)_"#)
        static let del        = try! NSRegularExpression(pattern: #"~~(.*?)~~"#)
        static let link       = try! NSRegularExpression(pattern: #"\[([^\]]+)]\([^)]+\)"#)
        static let image      = try! NSRegularExpression(pattern: #"\!\[([^\]]*)]\([^)]+\)"#)
        static let htmlTag    = try! NSRegularExpression(pattern: #"<[^>]+>"#)
        static let multiSpace = try! NSRegularExpression(pattern: #" {2,}"#)
    }

    // 统一换行
    let rows = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

    var inFence = false
    var out: [String] = []

    for var line in rows {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 1) 代码围栏
        if RX.codeFence.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            inFence.toggle()
            continue
        }
        if inFence {                      // 代码块内容直接保留
            out.append(line)
            continue
        }

        // 2) 跳过 HR / 表格分隔
        if RX.hr.firstMatch(in: trimmed, range: trimmed.nsRange) != nil { continue }
        if RX.tableSep.firstMatch(in: trimmed, range: trimmed.nsRange) != nil { continue }

        // 3) 表格竖线→空格 & 压缩多空格
        line = RX.tablePipe.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: " ")
        line = RX.multiSpace.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: " ")

        // 4) 标题 / 列表符号 / 引用
        line = RX.heading.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "")
        line = RX.listDash.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1· ")
        line = RX.blockQuote.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "")

        // 5) 行内代码 & 强调
        line = RX.inlineCode.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1")
        line = RX.strong.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1$2")
        line = RX.em    .stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1$2")
        line = RX.del   .stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1")

        // 6) 链接 / 图片（仅保文本）
        line = RX.link .stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1")
        line = RX.image.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "$1")

        // 7) 去 HTML 标签
        line = RX.htmlTag.stringByReplacingMatches(in: line, range: line.nsRange, withTemplate: "")

        // 8) HTML 实体解码（常用）
        line = line.replacingOccurrences(of: "&nbsp;" , with: " ")
                   .replacingOccurrences(of: "&lt;"   , with: "<")
                   .replacingOccurrences(of: "&gt;"   , with: ">")
                   .replacingOccurrences(of: "&amp;"  , with: "&")
                   .replacingOccurrences(of: "&quot;" , with: "\"")
                   .replacingOccurrences(of: "&apos;" , with: "'")

        out.append(line.trimmingCharacters(in: .whitespaces))
    }

    // 9) 合并多余空行
    var result: [String] = []
    var blank = false
    for l in out {
        if l.isEmpty {
            if !blank { result.append("") }
            blank = true
        } else {
            result.append(l)
            blank = false
        }
    }

    return result.joined(separator: "\n")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
}

// 转换小工具
private extension String {
    /// 生成整个字符串的 NSRange
    var nsRange: NSRange { NSRange(location: 0, length: utf16.count) }
}

// MARK: - 恢复系统模型默认排序
func resetModelPositionToDefault(context: ModelContext) {
    do {
        let fetchDescriptor = FetchDescriptor<AllModels>()
        let allModels = try context.fetch(fetchDescriptor)
        
        // Step 1: 构建 name -> 预置模型 的映射表
        let predefinedModels = getModelList()
        var predefinedPositionMap: [String: Int] = [:]
        for model in predefinedModels {
            if let name = model.name, let position = model.position {
                predefinedPositionMap[name] = position
            }
        }

        // Step 2: 先处理系统预置模型
        var maxSystemPosition = -1
        for model in allModels where model.systemProvision {
            if let name = model.name, let defaultPosition = predefinedPositionMap[name] {
                model.position = defaultPosition
                maxSystemPosition = max(maxSystemPosition, defaultPosition)
            }
        }

        // Step 3: 非系统预置模型统一放在系统模型之后，按名称排序
        var nonSystemModels = allModels.filter { !$0.systemProvision }
        nonSystemModels.sort { ($0.displayName ?? "") < ($1.displayName ?? "") }

        for (offset, model) in nonSystemModels.enumerated() {
            let newPosition = maxSystemPosition + 1 + offset
            model.position = newPosition
        }

        try context.save()
        print("模型排序已按默认规则恢复完毕。")

    } catch {
        print("恢复默认模型排序失败：\(error)")
    }
}

/// 解析时间范围：支持中英丰富表达
/// - 参数 raw: 原始关键词（可能包含类似“刚刚”、“last week”、“3天前”等时间词）
/// - 返回值：去掉了时间词的“纯搜索词” + 具体的开始时间和结束时间
func extractTimeRange(from raw: String) -> (clean: String, start: Date, end: Date) {
    let now = Date()
    let cal = Calendar.current
    var startDate: Date?
    var endDate: Date = now
    var clean = raw
    
    // 1. 预定义短语（中英文），逐一匹配并移除
    let phraseHandlers: [([String], ()->Void)] = [
        (["刚刚", "just now"], {
            startDate = cal.date(byAdding: .minute, value: -5, to: now)
        }),
        (["今天", "today"], {
            startDate = cal.startOfDay(for: now)
        }),
        (["昨天", "yesterday"], {
            let todayStart = cal.startOfDay(for: now)
            endDate = todayStart
            startDate = cal.date(byAdding: .day, value: -1, to: todayStart)
        }),
        (["前天"], {
            let todayStart = cal.startOfDay(for: now)
            endDate = cal.date(byAdding: .day, value: -1, to: todayStart)!
            startDate = cal.date(byAdding: .day, value: -2, to: todayStart)
        }),
        (["本周", "this week"], {
            if let interval = cal.dateInterval(of: .weekOfYear, for: now) {
                startDate = interval.start
            }
        }),
        (["本月", "this month"], {
            if let interval = cal.dateInterval(of: .month, for: now) {
                startDate = interval.start
            }
        }),
        (["本年", "今年", "this year"], {
            if let interval = cal.dateInterval(of: .year, for: now) {
                startDate = interval.start
            }
        }),
        (["上周", "last week"], {
            startDate = cal.date(byAdding: .weekOfYear, value: -1, to: now)
        }),
        (["上个月", "last month"], {
            startDate = cal.date(byAdding: .month, value: -1, to: now)
        }),
        (["去年", "last year"], {
            startDate = cal.date(byAdding: .year, value: -1, to: now)
        }),
        (["最近一周", "过去一周", "past week", "last 7 days"], {
            startDate = cal.date(byAdding: .day, value: -7, to: now)
        }),
        (["最近30天", "过去30天", "past month", "last 30 days"], {
            startDate = cal.date(byAdding: .day, value: -30, to: now)
        })
    ]
    for (phrases, handler) in phraseHandlers {
        for p in phrases {
            if clean.range(of: p, options: .caseInsensitive) != nil {
                handler()
                clean = clean.replacingOccurrences(of: p, with: "", options: .caseInsensitive)
            }
        }
    }
    
    // 2. 动态正则：匹配“X分钟前/ago/内”、“X小时前”、“X天前”等
    let relativePatterns: [(pattern: String, component: Calendar.Component)] = [
        ("(\\d+)\\s*(分钟|min|mins)\\s*(前|ago|内)?", .minute),
        ("(\\d+)\\s*(小时|h|hour|hours)\\s*(前|ago|内)?", .hour),
        ("(\\d+)\\s*(天|d|day|days)\\s*(前|ago|内)?", .day),
        ("(\\d+)\\s*(周|星期|w|week|weeks)\\s*(前|ago|内)?", .weekOfYear),
        ("(\\d+)\\s*(月|m|month|months)\\s*(前|ago|内)?", .month),
        ("(\\d+)\\s*(年|y|year|years)\\s*(前|ago|内)?", .year)
    ]
    for (pattern, component) in relativePatterns {
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        if let m = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
           let r = Range(m.range(at: 1), in: clean),
           let val = Int(clean[r]) {
            // 计算起始时间
            startDate = cal.date(byAdding: component, value: -val, to: now)
            // 去掉已匹配的相对表达
            clean = regex.stringByReplacingMatches(in: clean,
                                                   options: [],
                                                   range: NSRange(clean.startIndex..., in: clean),
                                                   withTemplate: "")
        }
    }
    
    // 3. 默认范围：过去 7 天
    let defaultStart = cal.date(byAdding: .day, value: -7, to: now)!
    
    return (
        clean.trimmingCharacters(in: .whitespacesAndNewlines),
        startDate ?? defaultStart,
        endDate
    )
}
