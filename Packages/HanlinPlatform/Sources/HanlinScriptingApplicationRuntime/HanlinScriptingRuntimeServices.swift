import CoreFoundation
import Foundation
import HanlinScriptUI
import UniformTypeIdentifiers

public struct HanlinScriptingDeviceSnapshot: Hashable, Sendable {
    public struct Screen: Hashable, Sendable {
        public let width: Double
        public let height: Double
        public let scale: Double

        public init(width: Double, height: Double, scale: Double) {
            self.width = width
            self.height = height
            self.scale = scale
        }
    }

    public let model: String
    public let localizedModel: String
    public let systemVersion: String
    public let systemName: String
    public let isiPad: Bool
    public let isiPhone: Bool
    public let screen: Screen
    public let batteryState: String
    public let batteryLevel: Double
    public let proximityState: Bool
    public let orientation: String
    public let colorScheme: String
    public let isiOSAppOnMac: Bool
    public let systemLocale: String
    public let preferredLanguages: [String]
    public let systemLanguageTag: String
    public let systemLanguageCode: String
    public let systemCountryCode: String?
    public let systemScriptCode: String?

    public init(
        model: String,
        localizedModel: String,
        systemVersion: String,
        systemName: String,
        isiPad: Bool,
        isiPhone: Bool,
        screen: Screen,
        batteryState: String,
        batteryLevel: Double,
        proximityState: Bool,
        orientation: String,
        colorScheme: String,
        isiOSAppOnMac: Bool,
        systemLocale: String,
        preferredLanguages: [String],
        systemLanguageTag: String,
        systemLanguageCode: String,
        systemCountryCode: String? = nil,
        systemScriptCode: String? = nil
    ) {
        self.model = model
        self.localizedModel = localizedModel
        self.systemVersion = systemVersion
        self.systemName = systemName
        self.isiPad = isiPad
        self.isiPhone = isiPhone
        self.screen = screen
        self.batteryState = batteryState
        self.batteryLevel = batteryLevel
        self.proximityState = proximityState
        self.orientation = orientation
        self.colorScheme = colorScheme
        self.isiOSAppOnMac = isiOSAppOnMac
        self.systemLocale = systemLocale
        self.preferredLanguages = preferredLanguages
        self.systemLanguageTag = systemLanguageTag
        self.systemLanguageCode = systemLanguageCode
        self.systemCountryCode = systemCountryCode
        self.systemScriptCode = systemScriptCode
    }

    public static let unavailable = Self(
        model: "Unknown",
        localizedModel: "Unknown",
        systemVersion: "",
        systemName: "Unknown",
        isiPad: false,
        isiPhone: false,
        screen: .init(width: 0, height: 0, scale: 1),
        batteryState: "unknown",
        batteryLevel: -1,
        proximityState: false,
        orientation: "unknown",
        colorScheme: "light",
        isiOSAppOnMac: false,
        systemLocale: "und",
        preferredLanguages: [],
        systemLanguageTag: "und",
        systemLanguageCode: "und"
    )

    var nativeObject: [String: Any] {
        var object: [String: Any] = [
            "model": model,
            "localizedModel": localizedModel,
            "systemVersion": systemVersion,
            "systemName": systemName,
            "isiPad": isiPad,
            "isiPhone": isiPhone,
            "screen": ["width": screen.width, "height": screen.height, "scale": screen.scale],
            "batteryState": batteryState,
            "batteryLevel": batteryLevel,
            "proximityState": proximityState,
            "orientation": orientation,
            "isLandscape": orientation == "landscapeLeft" || orientation == "landscapeRight",
            "isPortrait": orientation == "portrait" || orientation == "portraitUpsideDown",
            "isFlat": orientation == "faceUp" || orientation == "faceDown",
            "colorScheme": colorScheme,
            "isiOSAppOnMac": isiOSAppOnMac,
            "systemLocale": systemLocale,
            "preferredLanguages": preferredLanguages,
            "systemLocales": preferredLanguages,
            "systemLanguageTag": systemLanguageTag,
            "systemLanguageCode": systemLanguageCode,
        ]
        if let systemCountryCode { object["systemCountryCode"] = systemCountryCode }
        if let systemScriptCode { object["systemScriptCode"] = systemScriptCode }
        return object
    }
}

public enum HanlinScriptingLocationAction: String, Sendable {
    case requestCurrent = "request_current"
    case geocodeAddress = "geocode_address"
    case reverseGeocode = "reverse_geocode"
    case setAccuracy = "set_accuracy"
}

public struct HanlinScriptingLocationRequest: Sendable {
    public let action: HanlinScriptingLocationAction
    public let forceRequest: Bool
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let localeIdentifier: String?
    public let accuracy: String?

    public init(
        action: HanlinScriptingLocationAction,
        forceRequest: Bool = false,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        localeIdentifier: String? = nil,
        accuracy: String? = nil
    ) {
        self.action = action
        self.forceRequest = forceRequest
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.localeIdentifier = localeIdentifier
        self.accuracy = accuracy
    }
}

public struct HanlinScriptingLocationInfo: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timestampMilliseconds: Double

    public init(latitude: Double, longitude: Double, timestampMilliseconds: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestampMilliseconds = timestampMilliseconds
    }

    var nativeObject: [String: Any] {
        [
            "latitude": latitude,
            "longitude": longitude,
            "timestamp": timestampMilliseconds,
        ]
    }
}

public struct HanlinScriptingLocationPlacemark: Hashable, Sendable {
    public let location: HanlinScriptingLocationInfo?
    public let timeZoneIdentifier: String?
    public let name: String?
    public let locality: String?
    public let isoCountryCode: String?
    public let country: String?

    public init(
        location: HanlinScriptingLocationInfo? = nil,
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

    var nativeObject: [String: Any] {
        var object: [String: Any] = [:]
        if let location { object["location"] = location.nativeObject }
        if let timeZoneIdentifier { object["timeZone"] = timeZoneIdentifier }
        if let name { object["name"] = name }
        if let locality { object["locality"] = locality }
        if let isoCountryCode { object["isoCountryCode"] = isoCountryCode }
        if let country { object["country"] = country }
        return object
    }
}

public enum HanlinScriptingLocationResult: Sendable {
    case location(HanlinScriptingLocationInfo?)
    case placemarks([HanlinScriptingLocationPlacemark]?)
    case success

    var nativeObject: Any {
        switch self {
        case let .location(value): value?.nativeObject ?? NSNull()
        case let .placemarks(values): values?.map(\.nativeObject) ?? NSNull()
        case .success: NSNull()
        }
    }
}

public typealias HanlinScriptingLocationLoader = @MainActor @Sendable (
    HanlinScriptingLocationRequest
) async throws -> HanlinScriptingLocationResult

public enum HanlinScriptingUnavailableLocationLoader {
    public static func load(
        _ request: HanlinScriptingLocationRequest
    ) async throws -> HanlinScriptingLocationResult {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "location_unavailable",
            message: "The Location service is unavailable."
        )
    }
}

enum HanlinScriptingLocationPayloadDecoder {
    private static let accuracies: Set<String> = [
        "best", "tenMeters", "hundredMeters", "kilometer", "threeKilometers",
        "bestForNavigation", "reduced",
    ]

    static func decode(operation: String, json: String) throws -> HanlinScriptingLocationRequest {
        let prefix = "location."
        guard operation.hasPrefix(prefix),
              let action = HanlinScriptingLocationAction(
                rawValue: String(operation.dropFirst(prefix.count))
                    .replacingOccurrences(of: "requestCurrent", with: "request_current")
                    .replacingOccurrences(of: "geocodeAddress", with: "geocode_address")
                    .replacingOccurrences(of: "reverseGeocode", with: "reverse_geocode")
                    .replacingOccurrences(of: "setAccuracy", with: "set_accuracy")
              ) else {
            throw invalid("The Location operation is unavailable.")
        }
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        let locale = try optionalString(payload["locale"], name: "locale", maximumBytes: 128)
        switch action {
        case .requestCurrent:
            guard payload["forceRequest"] == nil || payload["forceRequest"] is Bool else {
                throw invalid("Location forceRequest must be a Boolean.")
            }
            return .init(action: action, forceRequest: payload["forceRequest"] as? Bool ?? false)
        case .geocodeAddress:
            guard let address = payload["address"] as? String,
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  address.utf8.count <= 4_096 else {
                throw invalid("Location geocoding requires a bounded, non-empty address.")
            }
            return .init(action: action, address: address, localeIdentifier: locale)
        case .reverseGeocode:
            guard let latitude = finiteDouble(payload["latitude"]), (-90 ... 90).contains(latitude),
                  let longitude = finiteDouble(payload["longitude"]), (-180 ... 180).contains(longitude) else {
                throw invalid("Location reverse geocoding requires valid coordinates.")
            }
            return .init(
                action: action,
                latitude: latitude,
                longitude: longitude,
                localeIdentifier: locale
            )
        case .setAccuracy:
            guard let accuracy = payload["accuracy"] as? String, accuracies.contains(accuracy) else {
                throw invalid("The requested Location accuracy is invalid.")
            }
            return .init(action: action, accuracy: accuracy)
        }
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        guard !(value is Bool), let number = value as? NSNumber,
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func optionalString(
        _ value: Any?, name: String, maximumBytes: Int
    ) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String, !string.isEmpty, string.utf8.count <= maximumBytes else {
            throw invalid("The Location \(name) is invalid.")
        }
        return string
    }

    private static func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_location_request", message: message)
    }
}

public enum HanlinScriptingHealthMetric: String, Sendable {
    case stepCount
    case distanceWalkingRunning
    case activeEnergyBurned
    case heartRate
}

public enum HanlinScriptingHealthStatisticsOption: String, Hashable, Sendable {
    case cumulativeSum
    case discreteAverage
}

public struct HanlinScriptingHealthStatisticsRequest: Sendable {
    public let metric: HanlinScriptingHealthMetric
    public let startDate: Date
    public let endDate: Date
    public let options: Set<HanlinScriptingHealthStatisticsOption>

    public init(
        metric: HanlinScriptingHealthMetric,
        startDate: Date,
        endDate: Date,
        options: Set<HanlinScriptingHealthStatisticsOption>
    ) {
        self.metric = metric
        self.startDate = startDate
        self.endDate = endDate
        self.options = options
    }
}

public struct HanlinScriptingHealthStatisticsResult: Sendable {
    public let metric: HanlinScriptingHealthMetric
    public let unit: String
    public let startDate: Date
    public let endDate: Date
    public let sum: Double?
    public let average: Double?

    public init(
        metric: HanlinScriptingHealthMetric,
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

    var nativeObject: [String: Any] {
        var value: [String: Any] = [
            "quantityType": metric.rawValue,
            "unit": unit,
            "startDate": startDate.timeIntervalSince1970 * 1_000,
            "endDate": endDate.timeIntervalSince1970 * 1_000,
        ]
        value["sum"] = sum ?? NSNull()
        value["average"] = average ?? NSNull()
        return value
    }
}

public typealias HanlinScriptingHealthStatisticsLoader = @MainActor @Sendable (
    HanlinScriptingHealthStatisticsRequest
) async throws -> HanlinScriptingHealthStatisticsResult?

public enum HanlinScriptingUnavailableHealthStatisticsLoader {
    public static func load(
        _ request: HanlinScriptingHealthStatisticsRequest
    ) async throws -> HanlinScriptingHealthStatisticsResult? {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "health_unavailable",
            message: "Health data is unavailable."
        )
    }
}

public struct HanlinScriptingHealthActivitySummariesRequest: Sendable {
    public let startComponents: [String: Int]
    public let endComponents: [String: Int]

    public init(startComponents: [String: Int], endComponents: [String: Int]) {
        self.startComponents = startComponents
        self.endComponents = endComponents
    }
}

public struct HanlinScriptingHealthActivitySummaryResult: Sendable {
    public let dateComponents: [String: Int]
    public let activityMoveMode: Int
    public let activeEnergyBurned: Double
    public let activeEnergyBurnedGoal: Double
    public let appleMoveTime: Double
    public let appleMoveTimeGoal: Double
    public let appleExerciseTime: Double
    public let appleExerciseTimeGoal: Double
    public let appleStandHours: Double
    public let appleStandHoursGoal: Double

    public init(
        dateComponents: [String: Int],
        activityMoveMode: Int,
        activeEnergyBurned: Double,
        activeEnergyBurnedGoal: Double,
        appleMoveTime: Double,
        appleMoveTimeGoal: Double,
        appleExerciseTime: Double,
        appleExerciseTimeGoal: Double,
        appleStandHours: Double,
        appleStandHoursGoal: Double
    ) {
        self.dateComponents = dateComponents
        self.activityMoveMode = activityMoveMode
        self.activeEnergyBurned = activeEnergyBurned
        self.activeEnergyBurnedGoal = activeEnergyBurnedGoal
        self.appleMoveTime = appleMoveTime
        self.appleMoveTimeGoal = appleMoveTimeGoal
        self.appleExerciseTime = appleExerciseTime
        self.appleExerciseTimeGoal = appleExerciseTimeGoal
        self.appleStandHours = appleStandHours
        self.appleStandHoursGoal = appleStandHoursGoal
    }

    var nativeObject: [String: Any] {
        [
            "dateComponents": dateComponents,
            "activityMoveMode": activityMoveMode,
            "activeEnergyBurned": activeEnergyBurned,
            "activeEnergyBurnedGoal": activeEnergyBurnedGoal,
            "appleMoveTime": appleMoveTime,
            "appleMoveTimeGoal": appleMoveTimeGoal,
            "appleExerciseTime": appleExerciseTime,
            "appleExerciseTimeGoal": appleExerciseTimeGoal,
            "appleStandHours": appleStandHours,
            "appleStandHoursGoal": appleStandHoursGoal,
        ]
    }
}

public typealias HanlinScriptingHealthActivitySummariesLoader = @MainActor @Sendable (
    HanlinScriptingHealthActivitySummariesRequest
) async throws -> [HanlinScriptingHealthActivitySummaryResult]

public enum HanlinScriptingUnavailableHealthActivitySummariesLoader {
    public static func load(
        _ request: HanlinScriptingHealthActivitySummariesRequest
    ) async throws -> [HanlinScriptingHealthActivitySummaryResult] {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error", code: "health_unavailable", message: "Health data is unavailable."
        )
    }
}

public struct HanlinScriptingHealthWorkoutsRequest: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let limit: Int
    public let reversed: Bool

    public init(startDate: Date, endDate: Date, limit: Int, reversed: Bool) {
        self.startDate = startDate
        self.endDate = endDate
        self.limit = limit
        self.reversed = reversed
    }
}

public struct HanlinScriptingHealthWorkoutResult: Sendable {
    public let uuid: String
    public let workoutActivityType: UInt
    public let startDate: Date
    public let endDate: Date
    public let duration: Double
    public let statistics: [HanlinScriptingHealthMetric: HanlinScriptingHealthStatisticsResult]

    public init(
        uuid: String,
        workoutActivityType: UInt,
        startDate: Date,
        endDate: Date,
        duration: Double,
        statistics: [HanlinScriptingHealthMetric: HanlinScriptingHealthStatisticsResult]
    ) {
        self.uuid = uuid
        self.workoutActivityType = workoutActivityType
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.statistics = statistics
    }

    var nativeObject: [String: Any] {
        [
            "uuid": uuid,
            "workoutActivityType": workoutActivityType,
            "startDate": startDate.timeIntervalSince1970 * 1_000,
            "endDate": endDate.timeIntervalSince1970 * 1_000,
            "duration": duration,
            "allStatistics": Dictionary(uniqueKeysWithValues: statistics.map {
                ($0.key.rawValue, $0.value.nativeObject)
            }),
        ]
    }
}

public typealias HanlinScriptingHealthWorkoutsLoader = @MainActor @Sendable (
    HanlinScriptingHealthWorkoutsRequest
) async throws -> [HanlinScriptingHealthWorkoutResult]

public enum HanlinScriptingUnavailableHealthWorkoutsLoader {
    public static func load(
        _ request: HanlinScriptingHealthWorkoutsRequest
    ) async throws -> [HanlinScriptingHealthWorkoutResult] {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error", code: "health_unavailable", message: "Health data is unavailable."
        )
    }
}

enum HanlinScriptingHealthPayloadDecoder {
    static func decodeStatistics(_ json: String) throws -> HanlinScriptingHealthStatisticsRequest {
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        guard let metricName = payload["quantityType"] as? String,
              let metric = HanlinScriptingHealthMetric(rawValue: metricName) else {
            throw invalid("The Health quantity type is unsupported.")
        }
        let startDate = try date(payload["startDate"], name: "startDate")
        let endDate = try date(payload["endDate"], name: "endDate")
        guard startDate <= endDate,
              endDate.timeIntervalSince(startDate) <= 366 * 24 * 60 * 60 else {
            throw invalid("The Health date range is invalid or exceeds one year.")
        }
        guard let names = payload["statisticsOptions"] as? [String],
              !names.isEmpty, names.count <= 2 else {
            throw invalid("Health statisticsOptions must be a non-empty bounded array.")
        }
        let options = Set(names.compactMap(HanlinScriptingHealthStatisticsOption.init(rawValue:)))
        guard options.count == Set(names).count else {
            throw invalid("A requested Health statistics option is unsupported.")
        }
        return .init(metric: metric, startDate: startDate, endDate: endDate, options: options)
    }

    static func decodeActivitySummaries(_ json: String) throws -> HanlinScriptingHealthActivitySummariesRequest {
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        let start = try dateComponents(payload["start"], name: "start")
        let end = try dateComponents(payload["end"], name: "end")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let startDate = calendar.date(from: DateComponents(
            year: start["year"], month: start["month"], day: start["day"]
        )), let endDate = calendar.date(from: DateComponents(
            year: end["year"], month: end["month"], day: end["day"]
        )), startDate <= endDate,
        endDate.timeIntervalSince(startDate) <= 366 * 24 * 60 * 60 else {
            throw invalid("The Health activity-summary range is invalid or exceeds one year.")
        }
        return .init(startComponents: start, endComponents: end)
    }

    static func decodeWorkouts(_ json: String) throws -> HanlinScriptingHealthWorkoutsRequest {
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        let now = Date()
        let start = try payload["startDate"].map { try date($0, name: "startDate") }
            ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        let end = try payload["endDate"].map { try date($0, name: "endDate") } ?? now
        guard start <= end, end.timeIntervalSince(start) <= 366 * 24 * 60 * 60 else {
            throw invalid("The Health workout range is invalid or exceeds one year.")
        }
        let limit = try payload["limit"].map { value -> Int in
            guard !(value is Bool), let number = value as? NSNumber,
                  number.doubleValue.rounded() == number.doubleValue,
                  (1 ... 500).contains(number.intValue) else {
                throw invalid("The Health workout limit is invalid.")
            }
            return number.intValue
        } ?? 100
        var reversed = false
        if let descriptors = payload["sortDescriptors"] as? [[String: Any]], let first = descriptors.first {
            guard descriptors.count == 1, first["key"] as? String == "startDate",
                  let order = first["order"] as? String, ["forward", "reverse"].contains(order) else {
                throw invalid("Only a startDate Health workout sort descriptor is currently supported.")
            }
            reversed = order == "reverse"
        } else if payload["sortDescriptors"] != nil {
            throw invalid("Health workout sortDescriptors are invalid.")
        }
        return .init(startDate: start, endDate: end, limit: limit, reversed: reversed)
    }

    private static func dateComponents(_ value: Any?, name: String) throws -> [String: Int] {
        guard let object = value as? [String: Any] else {
            throw invalid("Health \(name) must be DateComponents.")
        }
        var result: [String: Int] = [:]
        for key in ["era", "year", "month", "day"] where object[key] != nil {
            guard let number = object[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.rounded() == number.doubleValue else {
                throw invalid("A Health date component is invalid.")
            }
            result[key] = number.intValue
        }
        guard result["year"] != nil, result["month"] != nil, result["day"] != nil else {
            throw invalid("Health DateComponents require year, month and day.")
        }
        return result
    }

    private static func date(_ value: Any?, name: String) throws -> Date {
        if !(value is Bool), let number = value as? NSNumber,
           number.doubleValue.isFinite {
            return Date(timeIntervalSince1970: number.doubleValue / 1_000)
        }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: string) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            if let value = formatter.date(from: string) { return value }
        }
        throw invalid("Health \(name) must be a valid date.")
    }

    private static func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_health_request", message: message)
    }
}

public enum HanlinScriptingNotificationAction: String, Sendable {
    case schedule
    case removeAllPendingsOfCurrentScript = "remove_all_pendings_of_current_script"
}

public enum HanlinScriptingNotificationTrigger: Sendable {
    case immediate
    case timeInterval(seconds: Double, repeats: Bool)
    case calendar(components: [String: Int], timeZoneIdentifier: String?, repeats: Bool)
}

public struct HanlinScriptingNotificationRequest: Sendable {
    public let action: HanlinScriptingNotificationAction
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let badge: Int?
    public let silent: Bool
    public let interruptionLevel: String?
    public let threadIdentifier: String?
    public let userInfoJSON: Data?
    public let trigger: HanlinScriptingNotificationTrigger?

    public init(
        action: HanlinScriptingNotificationAction,
        title: String? = nil,
        subtitle: String? = nil,
        body: String? = nil,
        badge: Int? = nil,
        silent: Bool = false,
        interruptionLevel: String? = nil,
        threadIdentifier: String? = nil,
        userInfoJSON: Data? = nil,
        trigger: HanlinScriptingNotificationTrigger? = nil
    ) {
        self.action = action
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

public typealias HanlinScriptingNotificationLoader = @MainActor @Sendable (
    HanlinScriptingNotificationRequest
) async throws -> Bool

public enum HanlinScriptingUnavailableNotificationLoader {
    public static func load(_ request: HanlinScriptingNotificationRequest) async throws -> Bool {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "notifications_unavailable",
            message: "Notifications are unavailable."
        )
    }
}

enum HanlinScriptingNotificationPayloadDecoder {
    private static let componentNames = Set([
        "era", "year", "yearForWeekOfYear", "quarter", "month", "weekOfMonth",
        "weekOfYear", "weekday", "weekdayOrdinal", "day", "hour", "minute", "second", "nanosecond",
    ])
    private static let interruptionLevels = Set(["active", "passive", "timeSensitive"])

    static func decode(operation: String, json: String) throws -> HanlinScriptingNotificationRequest {
        if operation == "notification.removeAllPendingsOfCurrentScript" {
            return .init(action: .removeAllPendingsOfCurrentScript)
        }
        guard operation == "notification.schedule" else {
            throw invalid("The Notification operation is unavailable.")
        }
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        let title = try requiredString(payload["title"], name: "title", maximumBytes: 1_024)
        let subtitle = try optionalString(payload["subtitle"], name: "subtitle", maximumBytes: 2_048)
        let body = try optionalString(payload["body"], name: "body", maximumBytes: 8_192)
        let thread = try optionalString(payload["threadIdentifier"], name: "threadIdentifier", maximumBytes: 512)
        let level = try optionalString(payload["interruptionLevel"], name: "interruptionLevel", maximumBytes: 32)
        if let level, !interruptionLevels.contains(level) {
            throw invalid("The Notification interruptionLevel is invalid.")
        }
        guard payload["silent"] == nil || payload["silent"] is Bool else {
            throw invalid("Notification silent must be a Boolean.")
        }
        let badge: Int? = try payload["badge"].map { value in
            guard !(value is Bool), let number = value as? NSNumber,
                  number.doubleValue.rounded() == number.doubleValue,
                  (0 ... 999_999).contains(number.intValue) else {
                throw invalid("The Notification badge is invalid.")
            }
            return number.intValue
        }
        let userInfoJSON: Data? = try payload["userInfo"].map { value in
            guard JSONSerialization.isValidJSONObject(value) else {
                throw invalid("Notification userInfo must contain JSON values.")
            }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard data.count <= 65_536 else { throw invalid("Notification userInfo is too large.") }
            return data
        }
        return .init(
            action: .schedule,
            title: title,
            subtitle: subtitle,
            body: body,
            badge: badge,
            silent: payload["silent"] as? Bool ?? false,
            interruptionLevel: level,
            threadIdentifier: thread,
            userInfoJSON: userInfoJSON,
            trigger: try trigger(payload["trigger"])
        )
    }

    private static func trigger(_ value: Any?) throws -> HanlinScriptingNotificationTrigger {
        guard let value, !(value is NSNull) else { return .immediate }
        guard let object = value as? [String: Any], let type = object["type"] as? String else {
            throw invalid("The Notification trigger is invalid.")
        }
        guard object["repeats"] == nil || object["repeats"] is Bool else {
            throw invalid("Notification trigger repeats must be a Boolean.")
        }
        let repeats = object["repeats"] as? Bool ?? false
        switch type {
        case "timeInterval":
            guard !(object["timeInterval"] is Bool), let number = object["timeInterval"] as? NSNumber,
                  number.doubleValue.isFinite,
                  number.doubleValue >= (repeats ? 60 : 1), number.doubleValue <= 366 * 24 * 60 * 60 else {
                throw invalid("The Notification time interval is invalid.")
            }
            return .timeInterval(seconds: number.doubleValue, repeats: repeats)
        case "calendar":
            guard let raw = object["dateMatching"] as? [String: Any], !raw.isEmpty else {
                throw invalid("A calendar Notification requires date components.")
            }
            var components: [String: Int] = [:]
            for (key, value) in raw where componentNames.contains(key) {
                guard !(value is Bool), let number = value as? NSNumber,
                      number.doubleValue.rounded() == number.doubleValue else {
                    throw invalid("A Notification date component is invalid.")
                }
                components[key] = number.intValue
            }
            guard !components.isEmpty else { throw invalid("A calendar Notification requires date components.") }
            let timeZone = try optionalString(raw["timeZone"], name: "timeZone", maximumBytes: 128)
            return .calendar(components: components, timeZoneIdentifier: timeZone, repeats: repeats)
        default:
            throw invalid("The Notification trigger type is unsupported.")
        }
    }

    private static func requiredString(_ value: Any?, name: String, maximumBytes: Int) throws -> String {
        guard let value = try optionalString(value, name: name, maximumBytes: maximumBytes), !value.isEmpty else {
            throw invalid("Notification \(name) is required.")
        }
        return value
    }

    private static func optionalString(_ value: Any?, name: String, maximumBytes: Int) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String, string.utf8.count <= maximumBytes else {
            throw invalid("Notification \(name) is invalid.")
        }
        return string
    }

    private static func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_notification_request", message: message)
    }
}

public enum HanlinScriptingLiveActivityAction: String, Sendable {
    case start
    case update
    case end
    case areActivitiesEnabled = "are_activities_enabled"
}

public struct HanlinScriptingLiveActivityRequest: Sendable {
    public let action: HanlinScriptingLiveActivityAction
    public let name: String?
    public let activityID: String?
    public let stateJSON: Data?
    public let root: HanlinScriptUINode?
    public let staleDate: Date?
    public let relevanceScore: Double?
    public let dismissTimeInterval: Double?

    public init(
        action: HanlinScriptingLiveActivityAction,
        name: String? = nil,
        activityID: String? = nil,
        stateJSON: Data? = nil,
        root: HanlinScriptUINode? = nil,
        staleDate: Date? = nil,
        relevanceScore: Double? = nil,
        dismissTimeInterval: Double? = nil
    ) {
        self.action = action
        self.name = name
        self.activityID = activityID
        self.stateJSON = stateJSON
        self.root = root
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
        self.dismissTimeInterval = dismissTimeInterval
    }
}

public enum HanlinScriptingLiveActivityResult: Sendable {
    case started(activityID: String)
    case success(Bool)

    func nativeObject() -> Any {
        switch self {
        case let .started(activityID): ["activityId": activityID]
        case let .success(value): value
        }
    }
}

public typealias HanlinScriptingLiveActivityLoader = @MainActor @Sendable (
    HanlinScriptingLiveActivityRequest
) async throws -> HanlinScriptingLiveActivityResult

public enum HanlinScriptingUnavailableLiveActivityLoader {
    public static func load(
        _ request: HanlinScriptingLiveActivityRequest
    ) async throws -> HanlinScriptingLiveActivityResult {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "live_activity_unavailable",
            message: "The Live Activity service is unavailable."
        )
    }
}

public enum HanlinScriptingAssistantRequestKind: String, Sendable {
    case streaming
    case structuredData = "structured_data"
}

public enum HanlinScriptingAssistantProvider: Hashable, Sendable {
    case builtIn(String)
    case custom(String)
}

public struct HanlinScriptingAssistantRequest: Sendable {
    public let kind: HanlinScriptingAssistantRequestKind
    public let prompt: String?
    public let images: [String]
    public let schemaJSON: Data?
    public let systemPrompt: String?
    public let messagesJSON: Data?
    public let provider: HanlinScriptingAssistantProvider?
    public let modelID: String?

    public init(
        kind: HanlinScriptingAssistantRequestKind,
        prompt: String? = nil,
        images: [String] = [],
        schemaJSON: Data? = nil,
        systemPrompt: String? = nil,
        messagesJSON: Data? = nil,
        provider: HanlinScriptingAssistantProvider? = nil,
        modelID: String? = nil
    ) {
        self.kind = kind
        self.prompt = prompt
        self.images = images
        self.schemaJSON = schemaJSON
        self.systemPrompt = systemPrompt
        self.messagesJSON = messagesJSON
        self.provider = provider
        self.modelID = modelID
    }
}

public struct HanlinScriptingAssistantUsage: Hashable, Sendable {
    public let totalCost: Double?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let inputTokens: Int
    public let outputTokens: Int

    public init(
        totalCost: Double? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        inputTokens: Int,
        outputTokens: Int
    ) {
        self.totalCost = totalCost
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum HanlinScriptingAssistantChunk: Sendable {
    case text(String)
    case reasoning(String)
    case usage(HanlinScriptingAssistantUsage)
    case structuredJSON(Data)
}

public typealias HanlinScriptingAssistantLoader = @MainActor @Sendable (
    HanlinScriptingAssistantRequest
) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error>

public enum HanlinScriptingUnavailableAssistantLoader {
    public static func load(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        _ = request
        throw HanlinScriptingNativeError(
            name: "Error",
            code: "assistant_unavailable",
            message: "The Assistant service is unavailable."
        )
    }
}

public struct HanlinScriptingFetchRequest: Decodable, Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]
    public let bodyBase64: String?
    public let timeout: Double?
    public let allowInsecureRequest: Bool
}

public struct HanlinScriptingFetchResponse: Sendable {
    public let url: String
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(url: String, status: Int, headers: [String: String], body: Data) {
        self.url = url
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public typealias HanlinScriptingNetworkLoader = @Sendable (
    HanlinScriptingFetchRequest
) async throws -> HanlinScriptingFetchResponse

public enum HanlinScriptingURLSessionLoader {
    public static func load(_ request: HanlinScriptingFetchRequest) async throws -> HanlinScriptingFetchResponse {
        guard let url = URL(string: request.url), let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && request.allowInsecureRequest) else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_url",
                message: "The URL is malformed or its scheme is not permitted."
            )
        }
        guard request.method.utf8.count <= 32,
              request.headers.count <= 128,
              request.headers.allSatisfy({ $0.key.utf8.count <= 8_192 && $0.value.utf8.count <= 32_768 }) else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_request",
                message: "The network request exceeds the supported limits."
            )
        }
        var nativeRequest = URLRequest(url: url)
        nativeRequest.httpMethod = request.method.uppercased()
        request.headers.forEach { nativeRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        if let bodyBase64 = request.bodyBase64 {
            guard let body = Data(base64Encoded: bodyBase64), body.count <= 16 * 1_024 * 1_024 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_body",
                    message: "The request body is not valid base64 data or is too large."
                )
            }
            nativeRequest.httpBody = body
        }
        if let timeout = request.timeout {
            guard timeout.isFinite, timeout > 0, timeout <= 300 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_timeout",
                    message: "The timeout must be between 0 and 300 seconds."
                )
            }
            nativeRequest.timeoutInterval = timeout
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (body, response) = try await session.data(for: nativeRequest)
            try Task.checkCancellation()
            guard body.count <= 16 * 1_024 * 1_024,
                  let httpResponse = response as? HTTPURLResponse else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_response",
                    message: "The network response is invalid or too large."
                )
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
                guard let name = item.key as? String else { return }
                result[name] = String(describing: item.value)
            }
            return HanlinScriptingFetchResponse(
                url: httpResponse.url?.absoluteString ?? request.url,
                status: httpResponse.statusCode,
                headers: headers,
                body: body
            )
        } catch is CancellationError {
            throw HanlinScriptingNativeError(
                name: "AbortError",
                code: "cancelled",
                message: "The operation was cancelled."
            )
        } catch let error as HanlinScriptingNativeError {
            throw error
        } catch {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "network_failure",
                message: "The network request failed."
            )
        }
    }
}

public struct HanlinScriptingNativeError: Error, Sendable {
    public let name: String
    public let code: String
    public let message: String

    public init(name: String, code: String, message: String) {
        self.name = name
        self.code = code
        self.message = message
    }
}

enum HanlinScriptingAssistantPayloadDecoder {
    private static let builtInProviders: Set<String> = [
        "openai", "gemini", "anthropic", "deepseek", "openrouter",
    ]

    static func decode(_ json: String) throws -> HanlinScriptingAssistantRequest {
        guard json.utf8.count <= 8 * 1_024 * 1_024 else {
            throw invalid("The Assistant request is too large.")
        }
        let payload = try HanlinScriptingNativeJSON.decodeObject(json)
        guard let rawKind = payload["kind"] as? String,
              let kind = HanlinScriptingAssistantRequestKind(rawValue: rawKind) else {
            throw invalid("The Assistant request kind is invalid.")
        }
        let provider = try decodeProvider(payload["provider"])
        let modelID = try optionalString(payload["modelId"], name: "modelId", maximumBytes: 512)

        switch kind {
        case .streaming:
            let systemPrompt = try optionalString(
                payload["systemPrompt"],
                name: "systemPrompt",
                maximumBytes: 1_048_576,
                allowsNull: true
            )
            guard let rawMessages = payload["messages"], !(rawMessages is NSNull),
                  JSONSerialization.isValidJSONObject([rawMessages]) else {
                throw invalid("Assistant streaming messages are required.")
            }
            let messagesJSON = try JSONSerialization.data(
                withJSONObject: rawMessages,
                options: [.sortedKeys]
            )
            guard messagesJSON.count <= 6 * 1_024 * 1_024 else {
                throw invalid("Assistant streaming messages are too large.")
            }
            return .init(
                kind: kind,
                systemPrompt: systemPrompt,
                messagesJSON: messagesJSON,
                provider: provider,
                modelID: modelID
            )
        case .structuredData:
            guard let prompt = payload["prompt"] as? String,
                  !prompt.isEmpty,
                  prompt.utf8.count <= 1_048_576 else {
                throw invalid("A non-empty Assistant prompt is required.")
            }
            guard let schema = payload["schema"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(schema) else {
                throw invalid("A JSON object schema is required.")
            }
            let schemaJSON = try JSONSerialization.data(
                withJSONObject: schema,
                options: [.sortedKeys]
            )
            guard schemaJSON.count <= 1_048_576 else {
                throw invalid("The Assistant schema is too large.")
            }
            let images = try decodeImages(payload["images"])
            return .init(
                kind: kind,
                prompt: prompt,
                images: images,
                schemaJSON: schemaJSON,
                provider: provider,
                modelID: modelID
            )
        }
    }

    private static func decodeProvider(_ value: Any?) throws -> HanlinScriptingAssistantProvider? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? String, builtInProviders.contains(value) {
            return .builtIn(value)
        }
        if let object = value as? [String: Any], object.count == 1,
           let custom = object["custom"] as? String,
           !custom.isEmpty, custom.utf8.count <= 2_048 {
            return .custom(custom)
        }
        throw invalid("The Assistant provider is invalid.")
    }

    private static func decodeImages(_ value: Any?) throws -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        guard let images = value as? [String], images.count <= 16 else {
            throw invalid("Assistant images must be a bounded array of data URIs.")
        }
        var byteCount = 0
        for image in images {
            byteCount += image.utf8.count
            guard image.hasPrefix("data:image/"), image.contains(";base64,"),
                  image.utf8.count <= 4 * 1_024 * 1_024,
                  byteCount <= 8 * 1_024 * 1_024 else {
                throw invalid("An Assistant image data URI is invalid or too large.")
            }
        }
        return images
    }

    private static func optionalString(
        _ value: Any?,
        name: String,
        maximumBytes: Int,
        allowsNull: Bool = false
    ) throws -> String? {
        guard let value else { return nil }
        if value is NSNull, allowsNull { return nil }
        guard let string = value as? String, string.utf8.count <= maximumBytes else {
            throw invalid("The Assistant \(name) value is invalid.")
        }
        return string
    }

    private static func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "TypeError", code: "invalid_assistant_request", message: message)
    }
}

extension HanlinScriptingAssistantChunk {
    func nativeObject() throws -> [String: Any] {
        switch self {
        case let .text(content):
            return ["type": "text", "content": content]
        case let .reasoning(content):
            return ["type": "reasoning", "content": content]
        case let .usage(usage):
            guard usage.inputTokens >= 0, usage.outputTokens >= 0,
                  usage.cacheReadTokens.map({ $0 >= 0 }) ?? true,
                  usage.cacheWriteTokens.map({ $0 >= 0 }) ?? true,
                  usage.totalCost.map(\.isFinite) ?? true else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_assistant_chunk",
                    message: "The Assistant usage chunk is invalid."
                )
            }
            return [
                "type": "usage",
                "content": [
                    "totalCost": usage.totalCost.map { $0 as Any } ?? NSNull(),
                    "cacheReadTokens": usage.cacheReadTokens.map { $0 as Any } ?? NSNull(),
                    "cacheWriteTokens": usage.cacheWriteTokens.map { $0 as Any } ?? NSNull(),
                    "inputTokens": usage.inputTokens,
                    "outputTokens": usage.outputTokens,
                ],
            ]
        case let .structuredJSON(data):
            guard data.count <= 8 * 1_024 * 1_024 else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_assistant_chunk",
                    message: "The Assistant structured result is too large."
                )
            }
            let value = try JSONSerialization.jsonObject(with: data)
            guard JSONSerialization.isValidJSONObject([value]) else {
                throw HanlinScriptingNativeError(
                    name: "TypeError",
                    code: "invalid_assistant_chunk",
                    message: "The Assistant structured result is not valid JSON."
                )
            }
            return ["type": "structured", "content": value]
        }
    }
}

final class HanlinScriptingPackageFileSystem: @unchecked Sendable {
    private struct ResolvedPath {
        let url: URL
        let root: URL
        let readOnly: Bool
    }

    private let lock = NSLock()
    private let fileManager = FileManager()
    private let documentsRoot: URL
    private let appGroupRoot: URL
    private let temporaryRoot: URL
    private let scriptsRoot: URL
    private let allowed: Bool
    private let maximumBytes = 64 * 1_024 * 1_024
    private let maximumReadBytes = 16 * 1_024 * 1_024

    init(
        installedPackageID: String,
        allowed: Bool,
        runtimeRoot: URL?,
        packageSourceDirectory: URL?
    ) throws {
        let baseRoot: URL
        if let runtimeRoot {
            baseRoot = runtimeRoot
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw HanlinScriptingNativeError(
                    name: "Error",
                    code: "filesystem_unavailable",
                    message: "The package filesystem is unavailable."
                )
            }
            baseRoot = applicationSupport
                .appending(path: "Hanlin/ScriptingPlatform/RuntimeData", directoryHint: .isDirectory)
                .appending(path: installedPackageID, directoryHint: .isDirectory)
        }
        documentsRoot = baseRoot.appending(path: "Documents", directoryHint: .isDirectory)
        appGroupRoot = baseRoot.appending(path: "AppGroupDocuments", directoryHint: .isDirectory)
        temporaryRoot = baseRoot.appending(path: "Temporary", directoryHint: .isDirectory)
        scriptsRoot = packageSourceDirectory ?? baseRoot.appending(path: "Scripts", directoryHint: .isDirectory)
        self.allowed = allowed
        try fileManager.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appGroupRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        if packageSourceDirectory == nil {
            try fileManager.createDirectory(at: scriptsRoot, withIntermediateDirectories: true)
        }
    }

    var publicDirectories: [String: Any] {
        [
            "documentsDirectory": "/documents",
            "appGroupDocumentsDirectory": "/app-group",
            "temporaryDirectory": "/temporary",
            "scriptsDirectory": "/scripts",
            "isiCloudEnabled": false,
            "isWebDAVAvailable": false,
        ]
    }

    func databaseURL(for path: String) throws -> URL {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "permission_denied",
                message: "The files capability is not granted."
            )
        }
        let target = try resolve(path, requireExisting: false)
        guard !target.readOnly else {
            throw HanlinScriptingNativeError(
                name: "Error", code: "read_only",
                message: "A SQLite database cannot be opened in the scripts directory."
            )
        }
        try fileManager.createDirectory(
            at: target.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return target.url
    }

    func perform(operation: String, payload: [String: Any]) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        guard allowed else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "permission_denied",
                message: "The files capability is not granted."
            )
        }
        switch operation {
        case "file.createDirectory":
            let target = try writable(payload, "path")
            let recursive = payload["recursive"] as? Bool ?? false
            try fileManager.createDirectory(
                at: target.url,
                withIntermediateDirectories: recursive
            )
            return NSNull()
        case "file.readDirectory":
            let target = try readable(payload, "path")
            let recursive = payload["recursive"] as? Bool ?? false
            return try directoryContents(at: target.url, recursive: recursive)
        case "file.exists":
            return fileManager.fileExists(atPath: try resolved(payload, "path").url.path())
        case "file.isFile":
            return try fileType(payload) == .typeRegular
        case "file.isDirectory":
            return try fileType(payload) == .typeDirectory
        case "file.isLink":
            return try fileType(payload, followsLinks: false) == .typeSymbolicLink
        case "file.readData":
            let data = try readData(payload)
            return data.base64EncodedString()
        case "file.writeData":
            let target = try writable(payload, "path")
            guard let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64), data.count <= maximumReadBytes else {
                throw invalid("The file data is invalid or too large.")
            }
            try checkQuota(replacing: target.url, withByteCount: data.count)
            try data.write(to: target.url, options: .atomic)
            return NSNull()
        case "file.appendData":
            let target = try writable(payload, "path")
            guard let base64 = payload["base64"] as? String,
                  let data = Data(base64Encoded: base64), data.count <= maximumReadBytes else {
                throw invalid("The file data is invalid or too large.")
            }
            try fileManager.createDirectory(
                at: target.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let previous = (try? Data(contentsOf: target.url, options: .mappedIfSafe)) ?? Data()
            guard previous.count + data.count <= maximumReadBytes else {
                throw quota()
            }
            try checkQuota(replacing: target.url, withByteCount: previous.count + data.count)
            var combined = previous
            combined.append(data)
            try combined.write(to: target.url, options: .atomic)
            return NSNull()
        case "file.stat":
            return try stat(payload)
        case "file.remove":
            let target = try writable(payload, "path")
            try fileManager.removeItem(at: target.url)
            return NSNull()
        case "file.copy":
            let source = try readable(payload, "path")
            let destination = try writable(payload, "newPath")
            try checkQuota(replacing: destination.url, withByteCount: try recursiveSize(source.url))
            try fileManager.copyItem(at: source.url, to: destination.url)
            return NSNull()
        case "file.rename":
            let source = try writable(payload, "path")
            let destination = try writable(payload, "newPath")
            try fileManager.moveItem(at: source.url, to: destination.url)
            return NSNull()
        case "file.mimeType":
            let target = try readable(payload, "path")
            return UTType(filenameExtension: target.url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
        default:
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "unsupported_operation",
                message: "The requested filesystem operation is unavailable."
            )
        }
    }

    private func readData(_ payload: [String: Any]) throws -> Data {
        let target = try readable(payload, "path")
        let attributes = try fileManager.attributesOfItem(atPath: target.url.path())
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumReadBytes else {
            throw quota()
        }
        return try Data(contentsOf: target.url, options: .mappedIfSafe)
    }

    private func directoryContents(at url: URL, recursive: Bool) throws -> [String] {
        if !recursive {
            return try fileManager.contentsOfDirectory(atPath: url.path()).sorted()
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [String] = []
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            result.append(String(item.path().dropFirst(url.path().count + 1)))
        }
        return result.sorted()
    }

    private func stat(_ payload: [String: Any]) throws -> [String: Any] {
        let target = try readable(payload, "path")
        let attributes = try fileManager.attributesOfItem(atPath: target.url.path())
        let type = attributes[.type] as? FileAttributeType
        return [
            "creationDate": milliseconds(attributes[.creationDate] as? Date),
            "modificationDate": milliseconds(attributes[.modificationDate] as? Date),
            "type": typeName(type),
            "size": (attributes[.size] as? NSNumber)?.int64Value ?? 0,
        ]
    }

    private func fileType(
        _ payload: [String: Any],
        followsLinks: Bool = true
    ) throws -> FileAttributeType? {
        guard let path = payload["path"] as? String else {
            throw invalid("A file path is required.")
        }
        let target = try resolve(
            path,
            requireExisting: false,
            followFinalSymbolicLink: followsLinks
        )
        guard fileManager.fileExists(atPath: target.url.path()) else { return nil }
        return try fileManager.attributesOfItem(atPath: target.url.path())[.type] as? FileAttributeType
    }

    private func checkQuota(replacing target: URL, withByteCount byteCount: Int) throws {
        let existing = (try? recursiveSize(target)) ?? 0
        let total = try recursiveSize(documentsRoot)
            + recursiveSize(appGroupRoot)
            + recursiveSize(temporaryRoot)
            - existing
            + byteCount
        guard total <= maximumBytes else { throw quota() }
    }

    private func recursiveSize(_ url: URL) throws -> Int {
        guard fileManager.fileExists(atPath: url.path()) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: url.path())
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true { enumerator.skipDescendants() }
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
        }
        return total
    }

    private func readable(_ payload: [String: Any], _ key: String) throws -> ResolvedPath {
        let value = try resolved(payload, key)
        guard fileManager.fileExists(atPath: value.url.path()) else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "not_found",
                message: "The file or directory does not exist."
            )
        }
        return value
    }

    private func writable(_ payload: [String: Any], _ key: String) throws -> ResolvedPath {
        let value = try resolved(payload, key, requireExisting: false)
        guard !value.readOnly else {
            throw HanlinScriptingNativeError(
                name: "Error",
                code: "read_only",
                message: "The scripts directory is read-only."
            )
        }
        return value
    }

    private func resolved(
        _ payload: [String: Any],
        _ key: String,
        requireExisting: Bool = true
    ) throws -> ResolvedPath {
        guard let path = payload[key] as? String else { throw invalid("A file path is required.") }
        return try resolve(path, requireExisting: requireExisting)
    }

    private func resolve(
        _ path: String,
        requireExisting: Bool,
        followFinalSymbolicLink: Bool = true
    ) throws -> ResolvedPath {
        guard !path.isEmpty, path.utf8.count <= 8_192,
              !path.contains("\\"), !path.contains("\0") else {
            throw invalid("The file path is invalid.")
        }
        let mapping: (root: URL, relative: String, readOnly: Bool)
        if path == "/documents" || path.hasPrefix("/documents/") {
            mapping = (documentsRoot, String(path.dropFirst("/documents".count)), false)
        } else if path == "/app-group" || path.hasPrefix("/app-group/") {
            mapping = (appGroupRoot, String(path.dropFirst("/app-group".count)), false)
        } else if path == "/temporary" || path.hasPrefix("/temporary/") {
            mapping = (temporaryRoot, String(path.dropFirst("/temporary".count)), false)
        } else if path == "/scripts" || path.hasPrefix("/scripts/") {
            mapping = (scriptsRoot, String(path.dropFirst("/scripts".count)), true)
        } else if !path.hasPrefix("/") {
            mapping = (documentsRoot, path, false)
        } else {
            throw invalid("The file path is outside the package filesystem.")
        }
        let components = mapping.relative.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains(".."), !components.contains(".") else {
            throw invalid("The file path contains traversal components.")
        }
        let candidate = components.reduce(mapping.root) {
            $0.appending(path: String($1), directoryHint: .inferFromPath)
        }.standardizedFileURL
        let candidateExists = fileManager.fileExists(atPath: candidate.path())
        let checkedURL = if followFinalSymbolicLink && (requireExisting || candidateExists) {
            candidate.resolvingSymlinksInPath()
        } else {
            candidate.deletingLastPathComponent().resolvingSymlinksInPath()
                .appending(path: candidate.lastPathComponent, directoryHint: .inferFromPath)
        }
        let root = mapping.root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path().hasSuffix("/") ? root.path() : root.path() + "/"
        guard checkedURL == root || checkedURL.path().hasPrefix(rootPath) else {
            throw invalid("The file path escapes its package root.")
        }
        return ResolvedPath(url: checkedURL, root: root, readOnly: mapping.readOnly)
    }

    private func milliseconds(_ date: Date?) -> Double {
        (date?.timeIntervalSince1970 ?? 0) * 1_000
    }

    private func typeName(_ type: FileAttributeType?) -> String {
        switch type {
        case .typeRegular: "file"
        case .typeDirectory: "directory"
        case .typeSymbolicLink: "link"
        case .typeSocket: "unixDomainSock"
        default: "notFound"
        }
    }

    private func invalid(_ message: String) -> HanlinScriptingNativeError {
        .init(name: "Error", code: "invalid_path", message: message)
    }

    private func quota() -> HanlinScriptingNativeError {
        .init(name: "Error", code: "quota_exceeded", message: "The package file quota was exceeded.")
    }
}

enum HanlinScriptingNativeJSON {
    static func decodeObject(_ json: String) throws -> [String: Any] {
        guard json.utf8.count <= 20 * 1_024 * 1_024,
              let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HanlinScriptingNativeError(
                name: "TypeError",
                code: "invalid_payload",
                message: "The native request payload is invalid."
            )
        }
        return object
    }

    static func success(_ value: Any) -> String {
        encode(["ok": true, "value": value])
    }

    static func failure(_ error: Error) -> String {
        let native = error as? HanlinScriptingNativeError ?? .init(
            name: "Error",
            code: "native_failure",
            message: "The native operation failed."
        )
        return encode([
            "ok": false,
            "error": ["name": native.name, "code": native.code, "message": native.message],
        ])
    }

    private static func encode(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"error":{"name":"Error","code":"encoding_failure","message":"The native result could not be encoded."}}"#
        }
        return string
    }
}
