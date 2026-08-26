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
