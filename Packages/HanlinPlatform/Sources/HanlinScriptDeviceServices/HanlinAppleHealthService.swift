#if os(iOS)
import Foundation
import HealthKit

public actor HanlinAppleHealthService {
    private let store: HKHealthStore

    public nonisolated static var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public init(store: HKHealthStore = .init()) { self.store = store }

    public func requestReadAuthorization(for metrics: Set<HanlinScriptHealthMetric>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HanlinAppleDeviceServiceError.unavailable(.health)
        }
        let types = try Set(metrics.map { try quantityType($0) })
        try await store.requestAuthorization(toShare: [], read: Set(types))
    }

    public func sum(
        _ metric: HanlinScriptHealthMetric,
        from startDate: Date,
        to endDate: Date
    ) async throws -> HanlinScriptHealthQuantity {
        guard startDate <= endDate else {
            throw HanlinAppleDeviceServiceError.invalidRequest("health_date_range")
        }
        let type = try quantityType(metric)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samples = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let statistics = try await HKStatisticsQueryDescriptor(
            predicate: samples,
            options: .cumulativeSum
        ).result(for: store)
        let unit = unit(for: metric)
        let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
        return .init(
            metric: metric,
            value: value,
            unit: unit.unitString,
            startDate: startDate,
            endDate: endDate
        )
    }

    public func statistics(
        _ metric: HanlinScriptHealthMetric,
        from startDate: Date,
        to endDate: Date,
        options: Set<HanlinScriptHealthStatisticsOption>
    ) async throws -> HanlinScriptHealthStatistics? {
        guard startDate <= endDate else {
            throw HanlinAppleDeviceServiceError.invalidRequest("health_date_range")
        }
        guard !options.isEmpty else {
            throw HanlinAppleDeviceServiceError.invalidRequest("health_statistics_options")
        }
        try await requestReadAuthorization(for: [metric])
        let type = try quantityType(metric)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let samples = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        var nativeOptions: HKStatisticsOptions = []
        if options.contains(.cumulativeSum) { nativeOptions.insert(.cumulativeSum) }
        if options.contains(.discreteAverage) { nativeOptions.insert(.discreteAverage) }
        let statistics = try await HKStatisticsQueryDescriptor(
            predicate: samples,
            options: nativeOptions
        ).result(for: store)
        let unit = unit(for: metric)
        let sum = statistics?.sumQuantity()?.doubleValue(for: unit)
        let average = statistics?.averageQuantity()?.doubleValue(for: unit)
        guard sum != nil || average != nil else { return nil }
        return .init(
            metric: metric,
            unit: unit.unitString,
            startDate: startDate,
            endDate: endDate,
            sum: sum,
            average: average
        )
    }

    public func activitySummaries(
        from startComponents: DateComponents,
        to endComponents: DateComponents
    ) async throws -> [HanlinScriptHealthActivitySummary] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HanlinAppleDeviceServiceError.unavailable(.health)
        }
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.activitySummaryType()])
        let calendar = Calendar.current
        guard let inclusiveEnd = calendar.date(from: endComponents),
              let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("health_activity_summary_range")
        }
        var exclusiveEndComponents = calendar.dateComponents([.era, .year, .month, .day], from: exclusiveEnd)
        exclusiveEndComponents.calendar = calendar
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: startComponents,
            end: exclusiveEndComponents
        )
        let summaries = try await HKActivitySummaryQueryDescriptor(predicate: predicate).result(for: store)
        return summaries.map { summary in
            let components = summary.dateComponents(for: calendar)
            var dateComponents: [String: Int] = [:]
            if let era = components.era { dateComponents["era"] = era }
            if let year = components.year { dateComponents["year"] = year }
            if let month = components.month { dateComponents["month"] = month }
            if let day = components.day { dateComponents["day"] = day }
            return .init(
                dateComponents: dateComponents,
                activityMoveMode: summary.activityMoveMode.rawValue,
                activeEnergyBurned: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                activeEnergyBurnedGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                appleMoveTime: summary.appleMoveTime.doubleValue(for: .minute()),
                appleMoveTimeGoal: summary.appleMoveTimeGoal.doubleValue(for: .minute()),
                appleExerciseTime: summary.appleExerciseTime.doubleValue(for: .minute()),
                appleExerciseTimeGoal: summary.appleExerciseTimeGoal.doubleValue(for: .minute()),
                appleStandHours: summary.appleStandHours.doubleValue(for: .count()),
                appleStandHoursGoal: summary.appleStandHoursGoal.doubleValue(for: .count())
            )
        }
    }

    public func workouts(
        from startDate: Date,
        to endDate: Date,
        limit: Int,
        reversed: Bool
    ) async throws -> [HanlinScriptHealthWorkout] {
        guard startDate <= endDate, (1 ... 500).contains(limit) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("health_workout_query")
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HanlinAppleDeviceServiceError.unavailable(.health)
        }
        let workoutType = HKWorkoutType.workoutType()
        try await store.requestAuthorization(toShare: [], read: [workoutType])
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let order: SortOrder = reversed ? .reverse : .forward
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: order)],
            limit: limit
        )
        let values: [HKWorkout] = try await descriptor.result(for: store)
        return values.map { workout in
            var statistics: [HanlinScriptHealthMetric: HanlinScriptHealthStatistics] = [:]
            for metric in HanlinScriptHealthMetric.allCases {
                guard let native = try? quantityType(metric),
                      let value = workout.statistics(for: native),
                      let result = healthStatistics(value, metric: metric) else { continue }
                statistics[metric] = result
            }
            return .init(
                uuid: workout.uuid.uuidString.lowercased(),
                workoutActivityType: workout.workoutActivityType.rawValue,
                startDate: workout.startDate,
                endDate: workout.endDate,
                duration: workout.duration,
                statistics: statistics
            )
        }
    }

    private func healthStatistics(
        _ statistics: HKStatistics,
        metric: HanlinScriptHealthMetric
    ) -> HanlinScriptHealthStatistics? {
        let unit = unit(for: metric)
        let sum = statistics.sumQuantity()?.doubleValue(for: unit)
        let average = statistics.averageQuantity()?.doubleValue(for: unit)
        guard sum != nil || average != nil else { return nil }
        return .init(
            metric: metric,
            unit: unit.unitString,
            startDate: statistics.startDate,
            endDate: statistics.endDate,
            sum: sum,
            average: average
        )
    }

    private func quantityType(_ metric: HanlinScriptHealthMetric) throws -> HKQuantityType {
        let identifier: HKQuantityTypeIdentifier = switch metric {
        case .steps: .stepCount
        case .walkingRunningDistance: .distanceWalkingRunning
        case .activeEnergy: .activeEnergyBurned
        case .heartRate: .heartRate
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HanlinAppleDeviceServiceError.unavailable(.health)
        }
        return type
    }

    private func unit(for metric: HanlinScriptHealthMetric) -> HKUnit {
        switch metric {
        case .steps: .count()
        case .walkingRunningDistance: .meter()
        case .activeEnergy: .kilocalorie()
        case .heartRate: .count().unitDivided(by: .minute())
        }
    }
}
#endif
