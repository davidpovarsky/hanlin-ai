import Foundation
import HealthKit

/// 健康数据工具类，封装步数和距离的读取操作
@MainActor
final class HealthTool {
    
    static let shared = HealthTool()
    private let healthStore = HKHealthStore()
    private init() {}
    
    // MARK: - 请求权限（异步）
    private func requestAuthorizationAsync() async throws {
        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        ]
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        ]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    // MARK: - 获取步数与距离详情（每小时统计）
    func fetchStepDetails(from startDate: Date, to endDate: Date) async -> String {
        let calendar = Calendar.current
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let healthStore = HKHealthStore()

        let now = Date()  // 精确到当前时刻
        // 1. 校验日期范围：不可为未来日期，且 start ≤ end
        guard startDate <= now, endDate <= now, startDate <= endDate else {
            return isChinese
                ? "日期范围无效：日期不可为未来，且起始日期需早于或等于结束日期。"
                : "Invalid date range: dates must not be in the future, and start ≤ end."
        }

        // 2. HealthKit 可用性
        guard HKHealthStore.isHealthDataAvailable() else {
            return isChinese
                ? "此设备不支持 HealthKit。"
                : "HealthKit is not available on this device."
        }

        // 3. 获取步数与距离类型
        guard
            let stepType     = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else {
            return isChinese
                ? "无法获取步数或距离类型。"
                : "Cannot retrieve step count or distance type."
        }

        // 4. 请求授权（假设已有异步封装 requestAuthorizationAsync）
        do {
            try await requestAuthorizationAsync()
        } catch {
            return isChinese
                ? "授权失败，请检查设置：\(error.localizedDescription)"
                : "Authorization failed: \(error.localizedDescription)"
        }

        // 公共查询参数
        let predicate  = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        var interval   = DateComponents(); interval.hour = 1

        // 5. 同步查询步数
        let stepStats: HKStatisticsCollection
        do {
            stepStats = try await withCheckedThrowingContinuation { cont in
                let q = HKStatisticsCollectionQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: anchorDate,
                    intervalComponents: interval
                )
                q.initialResultsHandler = { _, stats, error in
                    if let e = error {
                        cont.resume(throwing: e)
                    } else if let s = stats {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "HealthKit", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data"]
                        ))
                    }
                }
                healthStore.execute(q)
            }
        } catch {
            return isChinese
                ? "步数查询失败：\(error.localizedDescription)"
                : "Step query failed: \(error.localizedDescription)"
        }

        // 6. 同步查询距离
        let distStats: HKStatisticsCollection
        do {
            distStats = try await withCheckedThrowingContinuation { cont in
                let q = HKStatisticsCollectionQuery(
                    quantityType: distanceType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: anchorDate,
                    intervalComponents: interval
                )
                q.initialResultsHandler = { _, stats, error in
                    if let e = error {
                        cont.resume(throwing: e)
                    } else if let s = stats {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "HealthKit", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data"]
                        ))
                    }
                }
                healthStore.execute(q)
            }
        } catch {
            return isChinese
                ? "距离查询失败：\(error.localizedDescription)"
                : "Distance query failed: \(error.localizedDescription)"
        }

        // 7. 本地化格式器
        let dayFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale     = .current
            f.calendar   = calendar
            f.dateStyle  = .medium
            f.timeStyle  = .none
            return f
        }()
        let timeFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale     = .current
            f.calendar   = calendar
            f.dateStyle  = .none
            f.timeStyle  = .short
            return f
        }()

        // 8. 枚举或遍历每小时数据（这里保留 stride）
        var totalSteps   = 0
        var totalDist    = 0.0
        var daily: [String: [(String, Int, Double)]] = [:]

        for date in stride(from: startDate, through: endDate, by: 3600) {
            guard date <= endDate else { break }
            let steps = Int(stepStats.statistics(for: date)?
                                .sumQuantity()?.doubleValue(for: .count()) ?? 0)
            let dist  = distStats.statistics(for: date)?
                                .sumQuantity()?.doubleValue(for: .meter()) ?? 0
            if steps == 0 && dist == 0 { continue }

            let day  = dayFmt.string(from: date)
            let hour = timeFmt.string(from: date)
            daily[day, default: []].append((hour, steps, dist))
            totalSteps += steps
            totalDist  += dist
        }

        // 9. 构建输出
        var output = isChinese
            ? "从 \(dayFmt.string(from: startDate)) 到 \(dayFmt.string(from: endDate)) 的步数与距离分布如下：\n"
            : "Step and distance distribution from \(dayFmt.string(from: startDate)) to \(dayFmt.string(from: endDate)):\n"

        for day in daily.keys.sorted() {
            output += "\n*\(day)*\n"
            var daySteps = 0
            var dayDist  = 0.0
            for (hour, steps, dist) in daily[day]! {
                daySteps += steps
                dayDist  += dist
                let distStr: String
                if dist >= 1_000 {
                    distStr = isChinese
                        ? String(format: "%.2f 公里", dist/1_000)
                        : String(format: "%.2f km", dist/1_000)
                } else {
                    distStr = isChinese
                        ? "\(Int(dist)) 米"
                        : "\(Int(dist)) m"
                }
                output += isChinese
                    ? "  - \(hour)：\(steps) 步，\(distStr)\n"
                    : "  - \(hour): \(steps) steps, \(distStr)\n"
            }
            let dayTotalStr = dayDist >= 1_000
                ? String(format: isChinese ? "%.2f 公里" : "%.2f km", dayDist/1_000)
                : (isChinese ? "\(Int(dayDist)) 米" : "\(Int(dayDist)) m")
            output += isChinese
                ? "  - 当日总步数：\(daySteps) 步，总距离：\(dayTotalStr)\n"
                : "  - Daily total: \(daySteps) steps, \(dayTotalStr)\n"
        }

        let totalDistStr = totalDist >= 1_000
            ? String(format: isChinese ? "%.2f 公里" : "%.2f km", totalDist/1_000)
            : (isChinese ? "\(Int(totalDist)) 米" : "\(Int(totalDist)) m")

        output += isChinese
            ? "\n总步数（\(daily.count) 天）：\(totalSteps) 步，总距离：\(totalDistStr)"
            : "\nTotal for \(daily.count) days: \(totalSteps) steps, \(totalDistStr)"

        return output
    }
    
    // MARK: - 获取能量详情（每小时统计）
    func fetchEnergyDetails(from startDate: Date, to endDate: Date) async -> String {
        let calendar = Calendar.current
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let healthStore = HKHealthStore()
        let now = Date()
        
        // 1. 校验日期范围：不可为未来日期，且 start ≤ end
        guard startDate <= now, endDate <= now, startDate <= endDate else {
            return isChinese
                ? "日期范围无效：日期不可为未来，且起始日期需早于或等于结束日期。"
                : "Invalid date range: dates must not be in the future, and start ≤ end."
        }
        
        // 2. HealthKit 可用性
        guard HKHealthStore.isHealthDataAvailable() else {
            return isChinese
                ? "此设备不支持 HealthKit。"
                : "HealthKit is not available on this device."
        }
        
        // 3. 获取能量类型
        guard
            let basalType  = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
            let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else {
            return isChinese
                ? "无法获取能量类型。"
                : "Cannot retrieve energy types."
        }
        
        // 4. 请求授权（假设已有异步封装 requestAuthorizationAsync）
        do {
            try await requestAuthorizationAsync()
        } catch {
            return isChinese
                ? "授权失败，请检查设置：\(error.localizedDescription)"
                : "Authorization failed: \(error.localizedDescription)"
        }
        
        // 公共查询参数
        let predicate  = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        var interval   = DateComponents(); interval.hour = 1
        
        // 5. 同步查询静息能量
        let basalStats: HKStatisticsCollection
        do {
            basalStats = try await withCheckedThrowingContinuation { cont in
                let q = HKStatisticsCollectionQuery(
                    quantityType: basalType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: anchorDate,
                    intervalComponents: interval
                )
                q.initialResultsHandler = { _, stats, error in
                    if let e = error {
                        cont.resume(throwing: e)
                    } else if let s = stats {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "HealthKit", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data"]
                        ))
                    }
                }
                healthStore.execute(q)
            }
        } catch {
            return isChinese
                ? "静息能量查询失败：\(error.localizedDescription)"
                : "Basal energy query failed: \(error.localizedDescription)"
        }
        
        // 6. 同步查询活动能量
        let activeStats: HKStatisticsCollection
        do {
            activeStats = try await withCheckedThrowingContinuation { cont in
                let q = HKStatisticsCollectionQuery(
                    quantityType: activeType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: anchorDate,
                    intervalComponents: interval
                )
                q.initialResultsHandler = { _, stats, error in
                    if let e = error {
                        cont.resume(throwing: e)
                    } else if let s = stats {
                        cont.resume(returning: s)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "HealthKit", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "No data"]
                        ))
                    }
                }
                healthStore.execute(q)
            }
        } catch {
            return isChinese
                ? "活动能量查询失败：\(error.localizedDescription)"
                : "Active energy query failed: \(error.localizedDescription)"
        }
        
        // 7. 本地化格式器
        let dayFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale    = .current
            f.calendar  = calendar
            f.dateStyle = .medium
            f.timeStyle = .none
            return f
        }()
        let timeFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale    = .current
            f.calendar  = calendar
            f.dateStyle = .none
            f.timeStyle = .short
            return f
        }()
        
        // 8. 枚举每小时数据
        var totalBasal  = 0.0
        var totalActive = 0.0
        var daily: [String: [(String, Double, Double)]] = [:]
        
        for date in stride(from: startDate, through: endDate, by: 3600) {
            guard date <= endDate else { break }
            let basal  = basalStats.statistics(for: date)?
                            .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
            let active = activeStats.statistics(for: date)?
                            .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0.0
            if basal == 0 && active == 0 { continue }
            
            let day  = dayFmt.string(from: date)
            let hour = timeFmt.string(from: date)
            daily[day, default: []].append((hour, basal, active))
            totalBasal  += basal
            totalActive += active
        }
        
        // 9. 构建输出
        var output = isChinese
            ? "从 \(dayFmt.string(from: startDate)) 到 \(dayFmt.string(from: endDate)) 的每小时能量消耗如下：\n"
            : "Energy distribution from \(dayFmt.string(from: startDate)) to \(dayFmt.string(from: endDate)):\n"
        
        for day in daily.keys.sorted() {
            output += "\n*\(day)*\n"
            var dayBasal  = 0.0
            var dayActive = 0.0
            for (hour, basal, active) in daily[day]! {
                let sum = basal + active
                output += isChinese
                    ? "  - \(hour)：静息 \(String(format: "%.1f", basal)) 千卡，活动 \(String(format: "%.1f", active)) 千卡，合计 \(String(format: "%.1f", sum)) 千卡\n"
                    : "  - \(hour): Basal \(String(format: "%.1f", basal)) kcal, Active \(String(format: "%.1f", active)) kcal, Total \(String(format: "%.1f", sum)) kcal\n"
                dayBasal  += basal
                dayActive += active
            }
            let daySum = dayBasal + dayActive
            output += isChinese
                ? "  - 当日总消耗：静息 \(String(format: "%.1f", dayBasal))，活动 \(String(format: "%.1f", dayActive))，合计 \(String(format: "%.1f", daySum)) 千卡\n"
                : "  - Daily total: Basal \(String(format: "%.1f", dayBasal)) kcal, Active \(String(format: "%.1f", dayActive)) kcal, Total \(String(format: "%.1f", daySum)) kcal\n"
        }
        
        let grandTotal = totalBasal + totalActive
        output += isChinese
            ? "\n总能量消耗：静息 \(String(format: "%.1f", totalBasal)) + 活动 \(String(format: "%.1f", totalActive)) = \(String(format: "%.1f", grandTotal)) 千卡"
            : "\nGrand total: Basal \(String(format: "%.1f", totalBasal)) kcal + Active \(String(format: "%.1f", totalActive)) kcal = \(String(format: "%.1f", grandTotal)) kcal"
        
        return output
    }
    
    // MARK: - 获取营养摄入详情（按作息区间统计）
    func fetchNutritionDetails(from startDate: Date, to endDate: Date) async -> String {
        let calendar = Calendar.current
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        let healthStore = HKHealthStore()
        let now = Date()

        // 1. 校验日期
        guard startDate <= now, endDate <= now, startDate <= endDate else {
            return isChinese
                ? "日期范围无效：日期不可为未来，且起始日期需早于或等于结束日期。"
                : "Invalid date range: dates must not be in the future, and start ≤ end."
        }

        // 2. HealthKit 可用性
        guard HKHealthStore.isHealthDataAvailable() else {
            return isChinese
                ? "此设备不支持 HealthKit。"
                : "HealthKit is not available on this device."
        }

        // 3. 获取营养类型
        guard
            let proteinType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let carbType    = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fatType     = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let energyType  = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            return isChinese
                ? "无法获取营养类型。"
                : "Cannot retrieve nutrition types."
        }

        // 4. 请求授权
        do {
            try await requestAuthorizationAsync()
        } catch {
            return isChinese
                ? "授权失败，请检查设置：\(error.localizedDescription)"
                : "Authorization failed: \(error.localizedDescription)"
        }

        // 5. 并发抓取样本（带索引返回）
        func fetchSamples(of type: HKQuantityType, unit: HKUnit) async throws -> [HKQuantitySample] {
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
            return try await withCheckedThrowingContinuation { cont in
                let q = HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let e = error {
                        cont.resume(throwing: e)
                    } else {
                        cont.resume(returning: samples as? [HKQuantitySample] ?? [])
                    }
                }
                healthStore.execute(q)
            }
        }

        let indexedResults: [(Int, [HKQuantitySample])]
        do {
            indexedResults = try await withThrowingTaskGroup(of: (Int, [HKQuantitySample]).self) { group -> [(Int, [HKQuantitySample])] in
                group.addTask { (0, try await fetchSamples(of: proteinType, unit: .gram())) }
                group.addTask { (1, try await fetchSamples(of: carbType,    unit: .gram())) }
                group.addTask { (2, try await fetchSamples(of: fatType,     unit: .gram())) }
                group.addTask { (3, try await fetchSamples(of: energyType,  unit: .kilocalorie())) }

                var temp: [(Int, [HKQuantitySample])] = []
                for try await entry in group {
                    temp.append(entry)
                }
                return temp
            }
        } catch {
            return isChinese
                ? "营养样本查询失败：\(error.localizedDescription)"
                : "Nutrition samples query failed: \(error.localizedDescription)"
        }

        // 6. 解包结果
        var buckets = Array(repeating: [HKQuantitySample](), count: 4)
        for (idx, samples) in indexedResults {
            guard idx >= 0 && idx < buckets.count else { continue }
            buckets[idx] = samples
        }
        let proteinSamples = buckets[0]
        let carbSamples    = buckets[1]
        let fatSamples     = buckets[2]
        let energySamples  = buckets[3]

        // 7. 定义作息区间
        let segments: [(label: String, start: Int, end: Int)] = isChinese
            ? [("夜宵（凌晨）", 0, 3),
               ("早餐",     3, 11),
               ("午餐",    11, 13),
               ("下午茶",  13, 16),
               ("晚餐",    16, 19),
               ("夜宵（夜晚）", 19, 24)]
            : [("Late-night (early)", 0, 3),
               ("Breakfast",         3, 11),
               ("Lunch",            11, 13),
               ("Afternoon Snack",  13, 16),
               ("Dinner",           16, 19),
               ("Late-night (late)",19, 24)]

        func matchSegment(for date: Date) -> String? {
            let hour = calendar.component(.hour, from: date)
            return segments.first { hour >= $0.start && hour < $0.end }?.label
        }

        // 8. 聚合
        func aggregate(_ samples: [HKQuantitySample], unit: HKUnit) -> [String: Double] {
            var dict = [String: Double]()
            for s in samples {
                guard let seg = matchSegment(for: s.startDate) else { continue }
                dict[seg, default: 0] += s.quantity.doubleValue(for: unit)
            }
            return dict
        }

        let proteinMap = aggregate(proteinSamples, unit: .gram())
        let carbMap    = aggregate(carbSamples,    unit: .gram())
        let fatMap     = aggregate(fatSamples,     unit: .gram())
        let energyMap  = aggregate(energySamples,  unit: .kilocalorie())

        // 9. 构建输出
        let dateFmt: DateFormatter = {
            let f = DateFormatter()
            f.locale     = .current
            f.calendar   = calendar
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()

        var output = isChinese
            ? "从 \(dateFmt.string(from: startDate)) 到 \(dateFmt.string(from: endDate)) 的营养摄入统计：\n"
            : "Nutrition intake from \(dateFmt.string(from: startDate)) to \(dateFmt.string(from: endDate)):\n"

        var hasData = false
        for seg in segments {
            let p = proteinMap[seg.label] ?? 0
            let c = carbMap[seg.label]    ?? 0
            let f = fatMap[seg.label]     ?? 0
            let e = energyMap[seg.label]  ?? 0
            guard p + c + f + e > 0 else { continue }
            hasData = true

            output += "\n【\(seg.label)】\n"
            if p > 0 {
                output += isChinese
                    ? "- 蛋白质：\(String(format: "%.1f", p))g\n"
                    : "- Protein: \(String(format: "%.1f", p))g\n"
            }
            if c > 0 {
                output += isChinese
                    ? "- 碳水：\(String(format: "%.1f", c))g\n"
                    : "- Carbs: \(String(format: "%.1f", c))g\n"
            }
            if f > 0 {
                output += isChinese
                    ? "- 脂肪：\(String(format: "%.1f", f))g\n"
                    : "- Fat: \(String(format: "%.1f", f))g\n"
            }
            if e > 0 {
                output += isChinese
                    ? "- 膳食能量：\(String(format: "%.1f", e))kcal\n"
                    : "- Energy: \(String(format: "%.1f", e))kcal\n"
            }
        }

        if !hasData {
            return isChinese
                ? "没有查到任何营养摄入记录。"
                : "No nutrition data found."
        }
        return output
    }
    
    // MARK: - 构造 HealthData
    /// 大模型调用时用来构造只包含营养摄入的 HealthData
    func makeNutritionData(protein: Double? = nil,
                        carbohydrates: Double? = nil,
                        fat: Double? = nil,
                        energy: Double? = nil,
                        date: Date = Date()) -> HealthData {
        HealthData(
            date: date,
            proteinGrams: protein,
            carbohydratesGrams: carbohydrates,
            fatGrams: fat,
            energyKilocalories: energy,
            isWritten: false
        )
    }
    
    // MARK: - 写入膳食数据
    /// 将 HealthData 中的非 nil 营养摄入项写入 HealthKit，返回成功与否
    func writeNutritionData(_ data: HealthData) async throws -> Bool {
        // 1. 获取膳食类型
        guard
            let pType = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let cType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fType = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let eType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            throw NSError(domain: "HealthTool", code: 5003,
                          userInfo: [NSLocalizedDescriptionKey: "无法获取写入用膳食类型"])
        }
        
        // 2. 请求读写膳食相关权限
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let read: Set<HKObjectType>  = [pType, cType, fType, eType]
            let write: Set<HKSampleType> = [pType, cType, fType, eType]
            healthStore.requestAuthorization(toShare: write, read: read) { success, error in
                if let e = error { cont.resume(throwing: e) }
                else           { cont.resume(returning: ()) }
            }
        }
        
        // 3. 构造样本，仅对非 nil 字段生成
        var samples: [HKQuantitySample] = []
        let date = data.date
        
        if let p = data.proteinGrams {
            let qty = HKQuantity(unit: .gram(), doubleValue: p)
            samples.append(.init(type: pType, quantity: qty, start: date, end: date))
        }
        if let c = data.carbohydratesGrams {
            let qty = HKQuantity(unit: .gram(), doubleValue: c)
            samples.append(.init(type: cType, quantity: qty, start: date, end: date))
        }
        if let f = data.fatGrams {
            let qty = HKQuantity(unit: .gram(), doubleValue: f)
            samples.append(.init(type: fType, quantity: qty, start: date, end: date))
        }
        if let en = data.energyKilocalories {
            let qty = HKQuantity(unit: .kilocalorie(), doubleValue: en)
            samples.append(.init(type: eType, quantity: qty, start: date, end: date))
        }
        
        // 4. 如果没有任何样本，直接返回 true
        guard !samples.isEmpty else {
            return true
        }
        
        // 5. 批量写入并返回结果
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            healthStore.save(samples) { success, error in
                if let e = error { cont.resume(throwing: e) }
                else            { cont.resume(returning: success) }
            }
        }
    }
}
