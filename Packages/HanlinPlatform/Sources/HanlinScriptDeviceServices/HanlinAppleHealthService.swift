#if os(iOS)
import Foundation
import HealthKit

public actor HanlinAppleHealthService {
    private let store: HKHealthStore

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
        guard startDate <= endDate, endDate <= Date() else {
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

    private func quantityType(_ metric: HanlinScriptHealthMetric) throws -> HKQuantityType {
        let identifier: HKQuantityTypeIdentifier = switch metric {
        case .steps: .stepCount
        case .walkingRunningDistance: .distanceWalkingRunning
        case .activeEnergy: .activeEnergyBurned
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
        }
    }
}
#endif
