import Foundation
import HanlinPlatformContracts

public enum HanlinAppleServiceFamily: String, Codable, CaseIterable, Hashable, Sendable {
    case location
    case notifications
    case health
    case calendar
    case reminders
}

public struct HanlinAppleServiceAvailability: Codable, Hashable, Sendable {
    public let family: HanlinAppleServiceFamily
    public let allowedContexts: Set<HanlinExecutionContext>
    public let requiredEntitlements: [String]
    public let requiredUsageDescriptions: [String]

    public init(
        family: HanlinAppleServiceFamily,
        allowedContexts: Set<HanlinExecutionContext>,
        requiredEntitlements: [String] = [],
        requiredUsageDescriptions: [String] = []
    ) {
        self.family = family
        self.allowedContexts = allowedContexts
        self.requiredEntitlements = requiredEntitlements
        self.requiredUsageDescriptions = requiredUsageDescriptions
    }

    public static let current: [Self] = [
        .init(
            family: .location,
            allowedContexts: [.mainApplication, .appIntent, .backgroundTask],
            requiredUsageDescriptions: ["NSLocationWhenInUseUsageDescription"]
        ),
        .init(
            family: .notifications,
            allowedContexts: [.mainApplication, .appIntent, .backgroundTask],
            requiredEntitlements: ["aps-environment"]
        ),
        .init(
            family: .health,
            allowedContexts: [.mainApplication, .appIntent],
            requiredEntitlements: ["com.apple.developer.healthkit"],
            requiredUsageDescriptions: ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"]
        ),
        .init(
            family: .calendar,
            allowedContexts: [.mainApplication, .appIntent],
            requiredUsageDescriptions: ["NSCalendarsFullAccessUsageDescription"]
        ),
        .init(
            family: .reminders,
            allowedContexts: [.mainApplication, .appIntent],
            requiredUsageDescriptions: ["NSRemindersFullAccessUsageDescription"]
        )
    ]
}

public struct HanlinScriptLocationValue: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontalAccuracy: Double,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

public struct HanlinScriptPlacemarkValue: Codable, Hashable, Sendable {
    public let location: HanlinScriptLocationValue
    public let timeZoneIdentifier: String?
    public let name: String?
    public let locality: String?
    public let isoCountryCode: String?
    public let country: String?

    public init(
        location: HanlinScriptLocationValue,
        timeZoneIdentifier: String? = nil,
        name: String? = nil,
        locality: String? = nil,
        isoCountryCode: String? = nil,
        country: String? = nil
    ) {
        self.location = location
        self.timeZoneIdentifier = timeZoneIdentifier
        self.name = name
        self.locality = locality
        self.isoCountryCode = isoCountryCode
        self.country = country
    }
}

public struct HanlinScriptLocalNotification: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public let userInfo: [String: String]

    public init(id: String, title: String, body: String, fireDate: Date, userInfo: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.userInfo = userInfo
    }
}

public enum HanlinScriptHealthMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case steps
    case walkingRunningDistance
    case activeEnergy
}

public struct HanlinScriptHealthQuantity: Codable, Hashable, Sendable {
    public let metric: HanlinScriptHealthMetric
    public let value: Double
    public let unit: String
    public let startDate: Date
    public let endDate: Date

    public init(metric: HanlinScriptHealthMetric, value: Double, unit: String, startDate: Date, endDate: Date) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct HanlinScriptCalendarItem: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool

    public init(id: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }
}

public enum HanlinAppleDeviceServiceError: Error, Equatable, Sendable {
    case unsupportedByPlatform(HanlinAppleServiceFamily)
    case unavailable(HanlinAppleServiceFamily)
    case denied(HanlinAppleServiceFamily)
    case invalidRequest(String)
    case noData(HanlinAppleServiceFamily)
}
