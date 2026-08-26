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
            requiredEntitlements: ["com.apple.developer.usernotifications.time-sensitive"]
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

public enum HanlinScriptLocalNotificationTrigger: Codable, Hashable, Sendable {
    case immediate
    case timeInterval(seconds: Double, repeats: Bool)
    case calendar(components: [String: Int], timeZoneIdentifier: String?, repeats: Bool)
}

public struct HanlinScriptLocalNotification: Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let badge: Int?
    public let silent: Bool
    public let interruptionLevel: String?
    public let threadIdentifier: String
    public let userInfoJSON: Data?
    public let trigger: HanlinScriptLocalNotificationTrigger

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        body: String = "",
        badge: Int? = nil,
        silent: Bool = false,
        interruptionLevel: String? = nil,
        threadIdentifier: String = "",
        userInfoJSON: Data? = nil,
        trigger: HanlinScriptLocalNotificationTrigger = .immediate
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.silent = silent
        self.interruptionLevel = interruptionLevel
        self.threadIdentifier = threadIdentifier
        self.userInfoJSON = userInfoJSON
        self.trigger = trigger
    }
}

public enum HanlinScriptHealthMetric: String, Codable, CaseIterable, Hashable, Sendable {
    case steps = "stepCount"
    case walkingRunningDistance = "distanceWalkingRunning"
    case activeEnergy = "activeEnergyBurned"
    case heartRate
}

public enum HanlinScriptHealthStatisticsOption: String, Codable, CaseIterable, Hashable, Sendable {
    case cumulativeSum
    case discreteAverage
}

public struct HanlinScriptHealthStatistics: Codable, Hashable, Sendable {
    public let metric: HanlinScriptHealthMetric
    public let unit: String
    public let startDate: Date
    public let endDate: Date
    public let sum: Double?
    public let average: Double?

    public init(
        metric: HanlinScriptHealthMetric,
        unit: String,
        startDate: Date,
        endDate: Date,
        sum: Double? = nil,
        average: Double? = nil
    ) {
        self.metric = metric
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.sum = sum
        self.average = average
    }
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
