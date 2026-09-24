//
//  APIManager+LegacyTools.swift
//  AI_HLY
//

import Foundation
import SwiftData
import CoreLocation
import HanlinPlatformContracts

extension APIManager {
    @MainActor
    func executeLegacyTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext,
        continuation: AsyncThrowingStream<StreamData, Error>.Continuation?
    ) async -> NativeToolResult {
        let currentLanguage = context.localeIdentifier
        let currentLanguagePrefix = currentLanguage.hasPrefix("zh")
        let functionName = name
        let functionArguments = argumentsJSON

        var toolResult = ""
        var toolResultFront = ""
        var executionOutcome: NativeToolExecutionOutcome = .succeeded
        var useFunctionName = functionName
        var executionEvidenceItems: [AgentEvidenceItem] = []
        var executionReturnedError = false
        var executionDiagnostics = NativeToolExecutionDiagnostics()
        let toolCallID = context.toolCallID ?? name

        switch functionName {
                                            case "save_memory":
                                                // 记忆函数
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在记忆" : "Taking Notes"))
                                                
                                                let content = extractValue(from: functionArguments, forKey: "content") ?? functionArguments
                                                let success = saveMemory(content: content)
                                                
                                                toolResult = currentLanguagePrefix
                                                ? (success ? "记忆已保存。" : "记忆保存失败。")
                                                : (success ? "Memory saved." : "Failed to save memory.")
                                                
                                                toolResultFront = toolResult
                                                
                                                useFunctionName = functionName
                                                
                                            case "retrieve_memory":
                                                // 回忆函数
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在回忆" : "Looking at the Notes"))
                                                
                                                let keyword = extractValue(from: functionArguments, forKey: "keyword") ?? functionArguments
                                                let memory = retrieveMemory(keyword: keyword)
                                                
                                                toolResult = currentLanguagePrefix
                                                ? "记忆内容：\n\(memory)"
                                                : "Memory content: \n\(memory)"
                                                
                                                toolResultFront = toolResult
                                                
                                                useFunctionName = functionName
                                                
                                            case "update_memory":
                                                // 更新记忆
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在更新记忆" : "Updating Memory"))
                                                
                                                let original = extractValue(from: functionArguments, forKey: "originalContent") ?? ""
                                                let updated = extractValue(from: functionArguments, forKey: "updatedContent") ?? ""
                                                
                                                if original.isEmpty || updated.isEmpty {
                                                    toolResult = currentLanguagePrefix ? "更新失败，参数不完整。" : "Update failed: missing parameters."
                                                } else {
                                                    let result = updateMemory(originalContent: original, updatedContent: updated)
                                                    toolResult = currentLanguagePrefix ? "记忆更新结果：\(result)" : "Memory update result: \(result)"
                                                }
                                                useFunctionName = functionName
                                                toolResultFront = toolResult
                                                
                                            case "search_online":
                                                // 调用网络搜索工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在联网搜索" : "Searching Online"))
                                                useFunctionName = functionName
                                                
                                                // 提取 query 参数
                                                let actualQuery = extractValue(from: functionArguments, forKey: "query") ?? functionArguments
                                                
                                                // 执行搜索
                                                let resultMarkdown = await searchOnline(query: actualQuery)
                                                
                                                // 将搜索结果设置为 toolResult 返回给大模型
                                                toolResult = resultMarkdown
                                                toolResultFront = toolResult
                                                
                                                // 推送搜索信息
                                                if let searchEngine = self.searchEngine, !searchEngine.isEmpty {
                                                    continuation?.yield(StreamData(searchEngine: self.searchEngine, search_text: self.searchText, searchQueries: self.searchQueries))
                                                }
                                                
                                            case "search_arxiv_papers":
                                                // 调用 arXiv 文献检索工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在检索文献" : "Searching Papers"))
                                                useFunctionName = functionName
                                                
                                                // 提取 query 参数
                                                let actualQuery = extractValue(from: functionArguments, forKey: "query") ?? functionArguments
                                                
                                                // 执行搜索
                                                let resultMarkdown = await searchArxivPapers(query: actualQuery)
                                                
                                                // 将搜索结果设置为 toolResult 返回给大模型
                                                toolResult = resultMarkdown
                                                toolResultFront = toolResult
                                                
                                                // 推送搜索信息
                                                if let searchEngine = self.searchEngine, !searchEngine.isEmpty {
                                                    continuation?.yield(StreamData(searchEngine: self.searchEngine, search_text: self.searchText, searchQueries: self.searchQueries))
                                                }
                                                
                                            case "extract_remote_file_content":
                                                // 调用远程文件内容提取工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在分析文件" : "Analyzing the Document"))
                                                useFunctionName = functionName
                                                
                                                // 提取 url 参数
                                                let actualURL = extractValue(from: functionArguments, forKey: "url") ?? functionArguments
                                                
                                                // 执行提取
                                                do {
                                                    let extractedContent = try await extractContentFromRemoteFile(urlString: actualURL)
                                                    toolResult = extractedContent
                                                } catch {
                                                    let isZh = Locale.preferredLanguages.first?.hasPrefix("zh") ?? true
                                                    toolResult = isZh
                                                    ? "提取文件内容时发生错误：\(error.localizedDescription)"
                                                    : "An error occurred while extracting file content: \(error.localizedDescription)"
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                                // 推送搜索信息
                                                if let searchEngine = self.searchEngine, !searchEngine.isEmpty {
                                                    continuation?.yield(StreamData(searchEngine: self.searchEngine, search_text: self.searchText, searchQueries: self.searchQueries))
                                                }
                                                
                                            case "read_web_page":
                                                // 调用网页阅读工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在读取网页" : "Reading Web"))
                                                useFunctionName = functionName
                                                
                                                // 提取 url 参数
                                                let actualURL = extractValue(from: functionArguments, forKey: "url") ?? functionArguments
                                                
                                                // 执行网页提取
                                                let resultMarkdown = await readWebPage(url: actualURL)
                                                
                                                // 将网页内容摘要设置为 toolResult 返回给大模型
                                                toolResult = resultMarkdown
                                                toolResultFront = toolResult
                                                
                                                // 推送搜索信息
                                                if let searchEngine = self.searchEngine, !searchEngine.isEmpty {
                                                    continuation?.yield(StreamData(searchEngine: self.searchEngine, search_text: self.searchText, searchQueries: self.searchQueries))
                                                }
                                                
                                            case "search_knowledge_bag":
                                                // 调用知识背包搜索工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在翻找背包" : "Searching in Bag"))
                                                useFunctionName = functionName
                                                
                                                // 提取 query 参数
                                                let actualQuery = extractValue(from: functionArguments, forKey: "query") ?? functionArguments
                                                
                                                // 执行知识背包搜索
                                                let resultMarkdown = await searchKnowledgeBag(query: actualQuery)
                                                
                                                // 将搜索结果设置为 toolResult 返回给大模型
                                                toolResult = resultMarkdown
                                                toolResultFront = toolResult
                                                
                                                // 推送搜索信息
                                                if let searchEngine = self.searchEngine, !searchEngine.isEmpty {
                                                    continuation?.yield(StreamData(searchEngine: self.searchEngine, search_text: self.searchText, searchQueries: self.searchQueries))
                                                }
                                                
                                            case "create_knowledge_document":
                                                // 调用创建知识卡片工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "创建知识文档" : "Creating Knowledge"))
                                                useFunctionName = functionName
                                                
                                                // 提取 title 和 content 参数
                                                let title   = extractValue(from: functionArguments, forKey: "title")   ?? ""
                                                let content = extractValue(from: functionArguments, forKey: "content") ?? ""
                                                
                                                let card = createKnowledgeCard(title: title, content: content)
                                                
                                                let feedbackMD: String
                                                if currentLanguage.hasPrefix("zh") {
                                                    feedbackMD = """
                                                    已创建知识文档《\(card.title)》。用户现在可以在界面中看到知识文档的详细内容了，不用重复文档内容。
                                                    """
                                                } else {
                                                    feedbackMD = """
                                                    The knowledge document "\(card.title)" has been created. Users can now view the detailed content of the knowledge document in the interface without duplicating the document content.
                                                    """
                                                }
                                                
                                                if self.knowledgeCard == nil {
                                                    knowledgeCard = []
                                                }
                                                knowledgeCard?.append(card)
                                                
                                                toolResult = feedbackMD
                                                
                                                if currentLanguage.hasPrefix("zh") {
                                                    toolResultFront = """
                                                    已创建知识文档《\(card.title)》。
                                                    """
                                                } else {
                                                    toolResultFront = """
                                                    The knowledge document "\(card.title)" has been created.
                                                    """
                                                }
                                                
                                            case "query_location":
                                                // 调用查询位置函数
                                                guard let mapInfo = findUseMap() else {
                                                    toolResult = "当前无激活的地图服务，请先配置地图服务。"
                                                    useFunctionName = functionName
                                                    break
                                                }
                                                
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在查询位置" : "Querying Location"))
                                                
                                                do {
                                                    let actualKeyword = extractValue(from: functionArguments, forKey: "keyword") ?? functionArguments
                                                    useFunctionName = functionName
                                                    
                                                    let locations = try await queryLocation(with: actualKeyword, company: mapInfo.company, apiKey: mapInfo.apiKey)
                                                    
                                                    if locations.isEmpty {
                                                        toolResult = "未查询到与关键字 \"\(actualKeyword)\" 相关的位置"
                                                    } else {
                                                        // 初始化 locationsInfo
                                                        if self.locationsInfo == nil {
                                                            self.locationsInfo = []
                                                        }
                                                        
                                                        // 追加到全局位置数组中
                                                        self.locationsInfo?.append(contentsOf: locations)
                                                        
                                                        // 构造结果提示字符串
                                                        let formatted = locations.enumerated().map { index, loc in
                                                            "(\(index + 1)) \(loc.name)：纬度 \(loc.latitude)，经度 \(loc.longitude)"
                                                        }.joined(separator: "\n")
                                                        
                                                        toolResult = currentLanguagePrefix ?
                                                        "\(actualKeyword) 的位置查询成功，共找到 \(locations.count) 个地点：\n\(formatted)" :
                                                        "\(actualKeyword) The location query was successful, a total of \(locations.count) locations were found: \n\(formatted)\n and have been mapped in the interface."
                                                        
                                                        toolResultFront = currentLanguagePrefix ?
                                                        "\(actualKeyword) 的位置查询成功，共找到 \(locations.count) 个地点：\n\(formatted)" :
                                                        "\(actualKeyword) The location query was successful, a total of \(locations.count) locations were found: \n\(formatted)."
                                                    }
                                                } catch {
                                                    toolResult = "查询位置出错：\(error.localizedDescription)"
                                                    useFunctionName = functionName
                                                    toolResultFront = toolResult
                                                }
                                                
                                            case "query_weather":
                                                // 检查是否有激活的天气服务
                                                guard let weatherInfo = findUseWeather() else {
                                                    toolResult = currentLanguagePrefix
                                                    ? "当前无激活的天气服务，请先配置天气服务。"
                                                    : "No active weather service configured. Please set one up first."
                                                    useFunctionName = functionName
                                                    break
                                                }
                                                
                                                // 天气查询函数
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在查询天气" : "Querying Weather"))
                                                
                                                do {
                                                    // 解析 JSON 参数
                                                    guard
                                                        let jsonData = functionArguments.data(using: .utf8),
                                                        let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                                        let latitude  = json["latitude"]  as? Double,
                                                        let longitude = json["longitude"] as? Double,
                                                        let timeRange = json["timeRange"] as? String
                                                    else {
                                                        throw NSError(
                                                            domain: "ToolArgumentError",
                                                            code: -1,
                                                            userInfo: [NSLocalizedDescriptionKey: "参数解析失败"]
                                                        )
                                                    }
                                                    
                                                    let coordinate = CLLocationCoordinate2D(
                                                        latitude: latitude,
                                                        longitude: longitude
                                                    )
                                                    useFunctionName = functionName
                                                    
                                                    // 调用新版天气查询函数：支持 timeRange、apiKey、requestURL
                                                    let weatherDescription = try await queryWeatherDescription(
                                                        at: coordinate,
                                                        company: weatherInfo.company,
                                                        timeRange: timeRange,
                                                        apiKey: weatherInfo.apiKey,
                                                        requestURL: weatherInfo.requestURL
                                                    )
                                                    
                                                    toolResult = currentLanguagePrefix
                                                    ? "该位置的天气信息如下：\n\(weatherDescription)"
                                                    : "Weather information for the location:\n\(weatherDescription)"
                                                    
                                                } catch {
                                                    toolResult = currentLanguagePrefix
                                                    ? "天气查询失败：\(error.localizedDescription)"
                                                    : "Failed to fetch weather: \(error.localizedDescription)"
                                                    useFunctionName = functionName
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "get_current_location":
                                                // 获取当前位置函数
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "获取当前位置" : "Getting Location"))
                                                do {
                                                    let location = try await getCurrentLocation()
                                                    useFunctionName = functionName
                                                    toolResult = currentLanguagePrefix ?
                                                    "当前位置为 \(location.name)，坐标：纬度 \(location.latitude)，经度 \(location.longitude)" :
                                                    "Current location is \(location.name), coordinates: latitude \(location.latitude), longitude \(location.longitude)"
                                                    
                                                } catch {
                                                    toolResult = currentLanguagePrefix ?
                                                    "获取当前位置失败：\(error.localizedDescription)" :
                                                    "Failed to get current location: \(error.localizedDescription)"
                                                    useFunctionName = functionName
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "search_nearby_locations":
                                                // 搜索范围兴趣点函数
                                                
                                                guard let mapInfo = findUseMap() else {
                                                    toolResult = "当前无激活的地图服务，请先配置地图服务。"
                                                    useFunctionName = functionName
                                                    break
                                                }
                                                
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "搜索周边地点" : "Searching Nearby"))
                                                
                                                do {
                                                    guard let jsonData = functionArguments.data(using: .utf8),
                                                          let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                                          let coordinateDict = json["coordinate"] as? [String: Any],
                                                          let latitude = coordinateDict["latitude"] as? Double,
                                                          let longitude = coordinateDict["longitude"] as? Double,
                                                          let keyword = json["keyword"] as? String else {
                                                        throw NSError(domain: "ToolArgumentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "参数解析失败"])
                                                    }
                                                    
                                                    useFunctionName = functionName
                                                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                                                    let results = try await searchNearbyLocations(around: coordinate, with: keyword, company: mapInfo.company, apiKey: mapInfo.apiKey)
                                                    
                                                    if results.isEmpty {
                                                        toolResult = currentLanguagePrefix ?
                                                        "未搜索到 \(keyword) 相关地点" :
                                                        "No results found for \(keyword)"
                                                    } else {
                                                        if self.locationsInfo == nil {
                                                            self.locationsInfo = []
                                                        }
                                                        self.locationsInfo?.append(contentsOf: results)
                                                        
                                                        let formatted = results.enumerated().map { index, loc in
                                                            "(\(index + 1)) \(loc.name)：纬度 \(loc.latitude)，经度 \(loc.longitude)"
                                                        }.joined(separator: "\n")
                                                        
                                                        toolResult = currentLanguagePrefix ?
                                                        "成功找到以下与 \(keyword) 相关的周边地点：\n\(formatted)\n并已绘制在地图中。" :
                                                        "Found the following nearby places related to \(keyword):\n\(formatted)\nThey are marked on the map."
                                                    }
                                                } catch {
                                                    toolResult = currentLanguagePrefix ?
                                                    "周边搜索失败：\(error.localizedDescription)" :
                                                    "Nearby search failed: \(error.localizedDescription)"
                                                    useFunctionName = functionName
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "get_route":
                                                // 根据起点、终点及交通方式规划路线
                                                guard let mapInfo = findUseMap() else {
                                                    toolResult = "当前无激活的地图服务，请先配置地图服务。"
                                                    useFunctionName = functionName
                                                    break
                                                }
                                                
                                                // 通知用户正在规划路线
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在规划路线" : "Planning Route"))
                                                
                                                do {
                                                    // 解析 JSON 数据，提取起点、终点及交通方式
                                                    guard let jsonData = functionArguments.data(using: .utf8),
                                                          let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                                          let startDict = json["start"] as? [String: Any],
                                                          let startLatitude = startDict["latitude"] as? Double,
                                                          let startLongitude = startDict["longitude"] as? Double,
                                                          let endDict = json["end"] as? [String: Any],
                                                          let endLatitude = endDict["latitude"] as? Double,
                                                          let endLongitude = endDict["longitude"] as? Double,
                                                          let mode = json["mode"] as? String else {
                                                        throw NSError(domain: "ToolArgumentError", code: -1,
                                                                      userInfo: [NSLocalizedDescriptionKey: "参数解析失败"])
                                                    }
                                                    useFunctionName = functionName
                                                    
                                                    let startCoordinate = CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
                                                    let endCoordinate = CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
                                                    
                                                    // 调用统一接口获取路线信息，返回自定义 RouteInfo 对象
                                                    let routeInfo = try await getRoute(from: startCoordinate,
                                                                                       to: endCoordinate,
                                                                                       with: mode,
                                                                                       company: mapInfo.company,
                                                                                       apiKey: mapInfo.apiKey)
                                                    
                                                    // 格式化返回提示信息
                                                    let distanceMeters = routeInfo.distance
                                                    let expectedTravelTime = routeInfo.expectedTravelTime
                                                    let travelTimeMinutes = expectedTravelTime / 60.0
                                                    let formattedSteps = routeInfo.instructions.isEmpty ? "" : "\n途经: " + routeInfo.instructions.joined(separator: " -> ")
                                                    
                                                    toolResult = currentLanguagePrefix ?
                                                    "路线规划成功：总距离 \(Int(distanceMeters)) 米，预计花费时间 \(Int(travelTimeMinutes)) 分钟\(formattedSteps)" :
                                                    "Route planned successfully: Total distance \(Int(distanceMeters)) meters, estimated travel time \(Int(travelTimeMinutes)) minutes\(formattedSteps)"
                                                    
                                                    // 存储路线信息
                                                    if self.storeRouteInfo == nil {
                                                        self.storeRouteInfo = []
                                                    }
                                                    self.storeRouteInfo?.append(routeInfo)
                                                    
                                                    // 生成起点和终点对应的 Location 对象，并添加到 locationsInfo 中
                                                    let startLocation = Location(
                                                        id: UUID(),
                                                        identifier: "start-\(UUID().uuidString)",
                                                        name: currentLanguagePrefix ? "起点" : "Start",
                                                        latitude: startLatitude,
                                                        longitude: startLongitude,
                                                        style: "mark"
                                                    )
                                                    let endLocation = Location(
                                                        id: UUID(),
                                                        identifier: "end-\(UUID().uuidString)",
                                                        name: currentLanguagePrefix ? "终点" : "Destination",
                                                        latitude: endLatitude,
                                                        longitude: endLongitude,
                                                        style: "mark"
                                                    )
                                                    if self.locationsInfo == nil {
                                                        self.locationsInfo = []
                                                    }
                                                    self.locationsInfo?.append(contentsOf: [startLocation, endLocation])
                                                    
                                                } catch {
                                                    // 根据交通方式提供更详细的错误说明
                                                    var errorDesc = error.localizedDescription
                                                    if let jsonData = functionArguments.data(using: .utf8),
                                                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                                       let mode = json["mode"] as? String {
                                                        switch mode.lowercased() {
                                                        case "walking":
                                                            errorDesc = currentLanguagePrefix ?
                                                            "步行路线规划失败，可能原因包括：距离过长、路径不通或步行道路不支持。" :
                                                            "Walking route planning failed. Possible reasons include: distance too long, path blocked, or walking paths not supported."
                                                        case "transit":
                                                            errorDesc = currentLanguagePrefix ?
                                                            "公共交通规划失败，可能原因包括：停运、换乘不可用、起点/终点公共交通服务不足或该地区不支持公共交通规划。" :
                                                            "Transit route planning failed. Possible reasons: service suspensions, unavailable transfers, insufficient public transport at origin/destination, or region not supported."
                                                        case "driving", "automobile":
                                                            errorDesc = currentLanguagePrefix ?
                                                            "驾车路线规划失败，请检查起点、终点是否在道路网络覆盖区域内。" :
                                                            "Driving route planning failed. Please check if the starting point and destination are within road network coverage."
                                                        default:
                                                            break
                                                        }
                                                    }
                                                    toolResult = currentLanguagePrefix ?
                                                    "规划路线出错：\(errorDesc)，建议更换交通方式或选择其他路线。" :
                                                    "Error in planning the route: \(errorDesc), suggesting a change of transportation or an alternative."
                                                    useFunctionName = functionName
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "search_calendar_and_reminders":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "查询日程事项" : "Searching Calendar"))
                                                useFunctionName = functionName
                                                
                                                do {
                                                    // 从函数参数中分别提取各字段
                                                    let keyword = extractValue(from: functionArguments, forKey: "keyword")
                                                    let startDateString = extractValue(from: functionArguments, forKey: "start_date")
                                                    let endDateString = extractValue(from: functionArguments, forKey: "end_date")
                                                    let location = extractValue(from: functionArguments, forKey: "location")
                                                    let eventType = extractValue(from: functionArguments, forKey: "event_type")
                                                    
                                                    // 将日期字符串转换为 Date 对象，格式要求为 "yyyy-MM-dd"
                                                    let dateFormatter = DateFormatter()
                                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                                    var startDate: Date? = nil
                                                    var endDate: Date? = nil
                                                    if let startStr = startDateString, !startStr.isEmpty {
                                                        startDate = dateFormatter.date(from: startStr)
                                                    }
                                                    if let endStr = endDateString, !endStr.isEmpty {
                                                        endDate = dateFormatter.date(from: endStr)
                                                    }
                                                    
                                                    // 调用新的搜索函数，按照各条件查询日历与提醒事项
                                                    let items = await searchSystemEvents(keyword: keyword, startDate: startDate, endDate: endDate, location: location, eventType: eventType)
                                                    executionEvidenceItems = AgentEvidenceExtractor.calendarItems(
                                                        items,
                                                        toolName: functionName,
                                                        toolCallID: toolCallID
                                                    )
                                                    
                                                    if items.isEmpty {
                                                        toolResult = currentLanguagePrefix ?
                                                        "未查询到符合条件的日历事件或提醒事项。" :
                                                        "No calendar events or reminders found matching the criteria."
                                                    } else {
                                                        
                                                        // 格式化输出结果
                                                        let outputFormatter = DateFormatter()
                                                        outputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                                                        
                                                        let formatted = items.enumerated().map { index, item in
                                                            let timeString: String = {
                                                                if let start = item.startDate {
                                                                    return outputFormatter.string(from: start)
                                                                } else if let due = item.dueDate {
                                                                    return outputFormatter.string(from: due)
                                                                } else {
                                                                    return currentLanguagePrefix ? "无时间信息" : "No time info"
                                                                }
                                                            }()
                                                            
                                                            let notePart = item.notes?.isEmpty == false ? "（备注：\(item.notes!)）" : ""
                                                            let locPart = item.location?.isEmpty == false ? "（地点：\(item.location!)）" : ""
                                                            let typePart = item.type == "calendar" ? (currentLanguagePrefix ? "日历事件" : "Calendar") : (currentLanguagePrefix ? "提醒事项" : "Reminder")
                                                            
                                                            return "(\(index + 1)) [\(typePart)] \(item.title) - \(timeString)\(notePart)\(locPart)"
                                                        }.joined(separator: "\n")
                                                        
                                                        toolResult = currentLanguagePrefix ?
                                                        "查询成功，共找到 \(items.count) 个相关项目：\n\(formatted)" :
                                                        "Query successful. Found \(items.count) matching items:\n\(formatted)"
                                                    }
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "write_system_event":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "写入系统事件" : "Writing System Event"))
                                                useFunctionName = functionName
                                                
                                                do {
                                                    // 从函数参数中分别提取各字段
                                                    let typeStr = extractValue(from: functionArguments, forKey: "type") ?? ""
                                                    let titleStr = extractValue(from: functionArguments, forKey: "title") ?? ""
                                                    let startDateStr = extractValue(from: functionArguments, forKey: "start_date") ?? ""
                                                    let endDateStr = extractValue(from: functionArguments, forKey: "end_date") ?? ""
                                                    let dueDateStr = extractValue(from: functionArguments, forKey: "due_date") ?? ""
                                                    let locationValue = extractValue(from: functionArguments, forKey: "location") ?? ""
                                                    let notesValue = extractValue(from: functionArguments, forKey: "notes") ?? ""
                                                    let priorityStr = extractValue(from: functionArguments, forKey: "priority")
                                                    let reminderMinutesStr = extractValue(from: functionArguments, forKey: "reminder_minutes")
                                                    
                                                    // 使用 ISO8601 格式转换日期字符串（格式示例：2025-04-16T12:34:56Z）
                                                    print("时间：", startDateStr, endDateStr, dueDateStr)
                                                    let isoFormatter = ISO8601DateFormatter()
                                                    var startDate: Date? = nil
                                                    var endDate: Date? = nil
                                                    var dueDate: Date? = nil
                                                    
                                                    if !startDateStr.isEmpty {
                                                        startDate = isoFormatter.date(from: startDateStr)
                                                    }
                                                    if !endDateStr.isEmpty {
                                                        endDate = isoFormatter.date(from: endDateStr)
                                                    }
                                                    if !dueDateStr.isEmpty {
                                                        dueDate = isoFormatter.date(from: dueDateStr)
                                                    }
                                                    
                                                    // 将 priority 转换为 Int（若传入值非空）
                                                    var priorityValue: Int? = nil
                                                    if let pStr = priorityStr, let pInt = Int(pStr) {
                                                        priorityValue = pInt
                                                    }
                                                    
                                                    // 将 reminder_minutes 转换为 Int（若传入值非空）
                                                    var reminderMinutesValue: Int? = nil
                                                    if let rmStr = reminderMinutesStr, let rmInt = Int(rmStr) {
                                                        reminderMinutesValue = rmInt
                                                    }
                                                    
                                                    // 调用写入系统事件的函数
                                                    let (writtenEvent, success) = await writeSystemEvent(type: typeStr,
                                                                                                         title: titleStr,
                                                                                                         startDate: startDate,
                                                                                                         endDate: endDate,
                                                                                                         dueDate: dueDate,
                                                                                                         location: locationValue,
                                                                                                         notes: notesValue,
                                                                                                         priority: priorityValue,
                                                                                                         reminderMinutes: reminderMinutesValue)
                                                    
                                                    if success, let event = writtenEvent {
                                                        // 使用 DateFormatter 格式化时间输出
                                                        let outputFormatter = DateFormatter()
                                                        outputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
                                                        let timeString: String = {
                                                            if typeStr.lowercased() == "calendar", let start = event.startDate {
                                                                return outputFormatter.string(from: start)
                                                            } else if typeStr.lowercased() == "reminder", let due = event.dueDate {
                                                                return outputFormatter.string(from: due)
                                                            } else {
                                                                return currentLanguagePrefix ? "无时间信息" : "No time info"
                                                            }
                                                        }()
                                                        
                                                        toolResult = currentLanguagePrefix ?
                                                        "写入成功：[ \(event.title) - \(timeString) ]" :
                                                        "Event written successfully: [ \(event.title) - \(timeString) ]"
                                                        
                                                        // 存入聊天框
                                                        if self.events == nil {
                                                            self.events = []
                                                        }
                                                        self.events?.append(event)
                                                        
                                                    } else {
                                                        toolResult = currentLanguagePrefix ?
                                                        "写入系统事件失败。" :
                                                        "Failed to write system event."
                                                    }
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "create_web_view":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在创建网页" : "Creating Webpage"))
                                                
                                                useFunctionName = functionName
                                                
                                                do {
                                                    let htmlString = try await createWebView(extractValue(from: functionArguments, forKey: "code") ?? "Unknown")

                                                    if !htmlString.isEmpty, htmlString != "Unknown" {
                                                        self.htmlContent = htmlString
                                                        toolResult = currentLanguagePrefix ?
                                                        "成功渲染网页，现在用户可以看到网页内容及网页的源代码了。" :
                                                        "The webpage has been successfully rendered, and users can now see both the webpage content and its source code."
                                                        toolResultFront = currentLanguagePrefix ?
                                                        "成功向系统发送渲染网页请求" :
                                                        "The request to render the webpage has been successfully sent to the system."
                                                    } else {
                                                        toolResult = currentLanguagePrefix ?
                                                        "网页渲染失败" :
                                                        "Web page rendering failed."
                                                        toolResultFront = toolResult
                                                    }
                                                } catch {
                                                    toolResult = currentLanguagePrefix ? "网页渲染失败: \(error.localizedDescription)" : "Web page rendering failed: \(error.localizedDescription)"
                                                    toolResultFront = toolResult
                                                    executionOutcome = .failed
                                                }
                                                
                                            case "execute_remote_python_code", "execute_python_code":
                                                // 调用 Python 执行工具
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "正在执行代码" : "Executing Code"))
                                                useFunctionName = functionName
                                                
                                                // 提取 code 参数
                                                let pythonCode = extractValue(from: functionArguments, forKey: "code") ?? ""
                                                
                                                do {
                                                    // 执行脚本并获取 CodeBlock（包含 output + error 状态）
                                                    let resultBlock = try await PistonExecutor.executePythonCode(code: pythonCode)
                                                    
                                                    // 设置输出内容（作为 toolResult 返回给大模型）
                                                    toolResult = resultBlock.output
                                                    
                                                    // 存入聊天框
                                                    if self.codeBlock == nil {
                                                        self.codeBlock = []
                                                    }
                                                    self.codeBlock?.append(resultBlock)
                                                    executionOutcome = resultBlock.hasError ? .failed : .succeeded
                                                    executionReturnedError = resultBlock.hasError
                                                    executionDiagnostics.backendRoute = "remote:piston"
                                                    executionDiagnostics.source = "legacy"
                                                    executionDiagnostics.failureCategory = resultBlock.hasError ? NativeToolExecutionOutcome.failed.rawValue : nil
                                                    
                                                } catch {
                                                    // 出现严重异常（如网络失败、结构解析错误等）
                                                    toolResult = currentLanguagePrefix
                                                    ? "执行 Python 代码时发生错误：\(error.localizedDescription)"
                                                    : "An error occurred while executing the Python code: \(error.localizedDescription)"
                                                    executionOutcome = .failed
                                                    executionReturnedError = true
                                                    executionDiagnostics.backendRoute = "remote:piston"
                                                    executionDiagnostics.source = "legacy"
                                                    executionDiagnostics.failureCategory = NativeToolExecutionOutcome.failed.rawValue
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "create_canvas":
                                                // 1) 通知开始创建
                                                continuation?.yield(StreamData(
                                                    operationalState: currentLanguagePrefix ? "正在创建画布" : "Creating Canvas"
                                                ))
                                                useFunctionName = functionName

                                                // 2) 提取参数
                                                let title   = extractValue(from: functionArguments, forKey: "title")   ?? ""
                                                let content = extractValue(from: functionArguments, forKey: "content") ?? ""
                                                let type    = extractValue(from: functionArguments, forKey: "type")    ?? "text"

                                                // 3) 调用 createCanvasData，仅构建未保存的 CanvasData
                                                let canvasData = CanvasServices.createCanvasData(
                                                    title: title,
                                                    content: content,
                                                    type: type
                                                )
                                                // 4) 将画布信息赋给 self.canvasInfo，由前端负责后续保存
                                                self.canvasInfo = canvasData

                                                // 5) 准备返回给大模型的结果
                                                if currentLanguagePrefix {
                                                    toolResult = "画布已创建：\(title)\n内容：\(content)。用户现在可以阅读画布的内容，后续回答中避免赘述画布内容重复，而是应该引导用户点击右下角的画布按钮前往画布以查看和编辑画布内容。"
                                                } else {
                                                    toolResult = "Canvas created: \(title)\nContent: \(content). Users can now read the content of the canvas. In subsequent responses, avoid repeating the canvas content and instead guide users to click the canvas button in the lower right corner to view and edit the canvas."
                                                }
                            
                                                toolResultFront = currentLanguagePrefix
                                                        ? "标题为 \(title) 的画布已创建"
                                                        : "The canvas titled \(title) has been created."
                                                
                                            case "edit_canvas":
                                                continuation?.yield(StreamData(
                                                    operationalState: currentLanguagePrefix ? "正在修改画布" : "Editing canvas"
                                                ))
                                                useFunctionName = functionName

                                                // 2) 尝试解析 patterns 和 replacements 为 [String]
                                                let patterns = extractStringArray(from: functionArguments, forKey: "patterns")
                                                let replacements = extractStringArray(from: functionArguments, forKey: "replacements")

                                                // 3) 若数组长度不一致，构造错误反馈并返回（无需 guard）
                                                if patterns.count != replacements.count {
                                                    let msg = currentLanguagePrefix
                                                        ? "修改失败：patterns 与 replacements 数组长度不一致"
                                                        : "Edit failed: patterns and replacements arrays must be of the same length"
                                                    toolResult = msg
                                                    toolResultFront = msg
                                                    break
                                                }

                                                // 4) 构造规则数组
                                                let rules: [(String, String)] = zip(patterns, replacements).map { ($0, $1) }

                                                do {
                                                    // 5) 执行 Canvas 内容修改
                                                    let currentCanvas = self.canvasInfo ?? CanvasServices.createCanvasData(title: "Untitled", content: "", type: "markdown")
                                                    let updatedCanvas = try CanvasServices.editCanvasContent(
                                                        canvas: currentCanvas,
                                                        rules: rules
                                                    )

                                                    self.canvasInfo = updatedCanvas // 6) 更新到临时状态，供前端决定保存

                                                    // 7) 构造规则摘要
                                                    let ruleSummary = rules.enumerated().map { (index, pair) in
                                                        currentLanguagePrefix
                                                            ? "规则 \(index + 1)：模式：\(pair.0) → 替换为：\(pair.1)"
                                                            : "Rule \(index + 1): pattern: \(pair.0) → replacement: \(pair.1)"
                                                    }.joined(separator: "\n")

                                                    // 8) 生成完整内容
                                                    toolResult = currentLanguagePrefix
                                                        ? """
                                                        画布已修改，应用以下规则：
                                                        \(ruleSummary)

                                                        修改后内容如下：
                                                        \(updatedCanvas.content)

                                                        用户现在可以阅读画布的内容，后续回答中避免赘述画布内容重复，而是应该引导用户点击右下角的画布按钮前往画布以查看和编辑画布内容。
                                                        """
                                                        : """
                                                        Canvas has been updated using the following rules:
                                                        \(ruleSummary)

                                                        Updated content:
                                                        \(updatedCanvas.content)

                                                        Users can now read the content of the canvas. In subsequent responses, avoid repeating the canvas content and instead guide users to click the canvas button in the lower right corner to view and edit the canvas.
                                                        """

                                                    toolResultFront = currentLanguagePrefix
                                                        ? "画布内容已更新\n\(ruleSummary)"
                                                        : "Canvas content updated\n\(ruleSummary)"

                                                } catch {
                                                    let errorMsg = currentLanguagePrefix
                                                        ? "修改画布内容时发生错误：\(error.localizedDescription)"
                                                        : "An error occurred while editing the canvas: \(error.localizedDescription)"
                                                    toolResult = errorMsg
                                                    toolResultFront = errorMsg
                                                }
                                                
                                            case "fetch_step_details":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "查询距离步数" : "Fetching Steps"))
                                                useFunctionName = functionName
                                                
                                                do {
                                                    // 从函数参数中提取日期字符串
                                                    let startDateString = extractValue(from: functionArguments, forKey: "start_date")
                                                    let endDateString = extractValue(from: functionArguments, forKey: "end_date")
                                                    
                                                    // 日期格式转换
                                                    let dateFormatter = DateFormatter()
                                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                                    dateFormatter.timeZone = TimeZone.current
                                                    
                                                    guard
                                                        let startStr = startDateString,
                                                        let endStr = endDateString,
                                                        let startDate = dateFormatter.date(from: startStr),
                                                        let endDate = dateFormatter.date(from: endStr)
                                                    else {
                                                        toolResult = currentLanguagePrefix ?
                                                        "日期格式无效，请传入格式为 yyyy-MM-dd 的有效日期。" :
                                                        "Invalid date format. Please provide dates in yyyy-MM-dd format."
                                                        break
                                                    }
                                                    
                                                    // 调用步数详情查询函数
                                                    let detail = await HealthTool.shared.fetchStepDetails(from: startDate, to: endDate)
                                                    toolResult = detail
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "fetch_energy_details":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "查询能量详情" : "Fetching Energy"))
                                                useFunctionName = functionName
                                                
                                                do {
                                                    // 提取日期字符串
                                                    let startDateString = extractValue(from: functionArguments, forKey: "start_date")
                                                    let endDateString = extractValue(from: functionArguments, forKey: "end_date")
                                                    
                                                    let dateFormatter = DateFormatter()
                                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                                    dateFormatter.timeZone = TimeZone.current
                                                    
                                                    guard
                                                        let startStr = startDateString,
                                                        let endStr = endDateString,
                                                        let startDate = dateFormatter.date(from: startStr),
                                                        let endDate = dateFormatter.date(from: endStr)
                                                    else {
                                                        toolResult = currentLanguagePrefix ?
                                                        "日期格式无效，请传入格式为 yyyy-MM-dd 的有效日期。" :
                                                        "Invalid date format. Please provide dates in yyyy-MM-dd format."
                                                        break
                                                    }
                                                    
                                                    // 调用能量消耗详情查询函数
                                                    let detail = await HealthTool.shared.fetchEnergyDetails(from: startDate, to: endDate)
                                                    toolResult = detail
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "fetch_nutrition_details":
                                                continuation?.yield(StreamData(operationalState: currentLanguagePrefix ? "查询营养摄入" : "Fetching Nutrition"))
                                                useFunctionName = functionName
                                                
                                                do {
                                                    // 提取日期字符串
                                                    let startDateString = extractValue(from: functionArguments, forKey: "start_date")
                                                    let endDateString   = extractValue(from: functionArguments, forKey: "end_date")
                                                    
                                                    let dateFormatter = DateFormatter()
                                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                                    dateFormatter.timeZone = TimeZone.current
                                                    
                                                    guard
                                                        let startStr = startDateString,
                                                        let endStr   = endDateString,
                                                        let startDate = dateFormatter.date(from: startStr),
                                                        let endDate   = dateFormatter.date(from: endStr)
                                                    else {
                                                        toolResult = currentLanguagePrefix ?
                                                        "日期格式无效，请传入格式为 yyyy-MM-dd 的有效日期。" :
                                                        "Invalid date format. Please provide dates in yyyy-MM-dd format."
                                                        break
                                                    }
                                                    
                                                    // 调用营养摄入详情查询函数
                                                    let detail = await HealthTool.shared.fetchNutritionDetails(from: startDate, to: endDate)
                                                    toolResult = detail
                                                }
                                                
                                                toolResultFront = toolResult
                                                
                                            case "make_nutrition_data":
                                                continuation?.yield(StreamData(
                                                    operationalState: currentLanguagePrefix ? "生成营养卡片" : "Generating Nutrition Card"))
                                                useFunctionName = functionName
                                                
                                                guard
                                                    let raw = functionArguments.data(using: .utf8),
                                                    let dict = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
                                                else {
                                                    toolResult = currentLanguagePrefix
                                                    ? "无法解析 nutrition 参数（应为 JSON 字符串）。"
                                                    : "Failed to parse nutrition parameters (should be JSON string)."
                                                    break
                                                }
                                                
                                                func val(_ key: String) -> Double? {
                                                    if let n = dict[key] as? Double           { return n }
                                                    if let s = dict[key] as? String, let d = Double(s) { return d }
                                                    return nil
                                                }
                                                
                                                let card = await HealthTool.shared.makeNutritionData(
                                                    protein:       val("protein"),
                                                    carbohydrates: val("carbohydrates"),
                                                    fat:           val("fat"),
                                                    energy:        val("energy"),
                                                    date:          Date()                     // 如需自定义时间可再解析
                                                )
                                                
                                                // 缓存供 UI 用
                                                self.healthCard = (self.healthCard ?? []) + [card]
                                                
                                                var lines: [String] = []
                                                if let p = card.proteinGrams        { lines.append("蛋白质：\(String(format: "%.1f", p)) g") }
                                                if let c = card.carbohydratesGrams  { lines.append("碳水化合物：\(String(format: "%.1f", c)) g") }
                                                if let f = card.fatGrams            { lines.append("总脂肪：\(String(format: "%.1f", f)) g") }
                                                if let e = card.energyKilocalories  { lines.append("膳食能量：\(String(format: "%.1f", e)) kcal") }
                                                
                                                let header = currentLanguagePrefix ? "营养卡片已成功生成" : "Nutrition card generated successfully."
                                                toolResult = "\(header)\n" + lines.joined(separator: "\n")
                                                
                                                toolResultFront = toolResult
                                                

        default:
            return NativeToolResult(
                modelText: "Legacy tool '\(name)' not recognized.",
                userText: currentLanguagePrefix ? "工具不存在" : "Tool does not exist",
                outcome: .failed
            )
        }

        if toolResultFront.isEmpty {
            toolResultFront = toolResult
        }

        return NativeToolResult(
            modelText: toolResult,
            userText: toolResultFront,
            outcome: executionOutcome,
            diagnostics: executionDiagnostics
        )
    }
}
