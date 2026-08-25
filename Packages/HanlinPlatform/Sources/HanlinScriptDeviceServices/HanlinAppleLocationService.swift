#if os(iOS)
import CoreLocation
import Foundation
import MapKit

@MainActor
public final class HanlinAppleLocationService {
    private let manager: CLLocationManager

    public init(manager: CLLocationManager = .init()) { self.manager = manager }

    public func setAccuracy(_ accuracy: String) throws {
        manager.desiredAccuracy = switch accuracy {
        case "best": kCLLocationAccuracyBest
        case "tenMeters": kCLLocationAccuracyNearestTenMeters
        case "hundredMeters": kCLLocationAccuracyHundredMeters
        case "kilometer": kCLLocationAccuracyKilometer
        case "threeKilometers": kCLLocationAccuracyThreeKilometers
        case "bestForNavigation": kCLLocationAccuracyBestForNavigation
        case "reduced": kCLLocationAccuracyReduced
        default: throw HanlinAppleDeviceServiceError.invalidRequest("Invalid Location accuracy.")
        }
    }

    public func currentLocation(forceRequest: Bool = false) async throws -> HanlinScriptLocationValue {
        if !forceRequest, let cached = manager.location, cached.horizontalAccuracy >= 0 {
            return Self.value(cached)
        }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        for try await update in CLLocationUpdate.liveUpdates() {
            try Task.checkCancellation()
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw HanlinAppleDeviceServiceError.denied(.location)
            }
            if let location = update.location {
                return Self.value(location)
            }
        }
        throw HanlinAppleDeviceServiceError.noData(.location)
    }

    public func geocodeAddress(
        _ address: String,
        localeIdentifier: String? = nil
    ) async throws -> [HanlinScriptPlacemarkValue] {
        guard let request = MKGeocodingRequest(addressString: address) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("Invalid geocoding address.")
        }
        request.preferredLocale = localeIdentifier.map(Locale.init(identifier:))
        let items = try await request.mapItems
        try Task.checkCancellation()
        return Self.placemarks(items)
    }

    public func reverseGeocode(
        latitude: Double,
        longitude: Double,
        localeIdentifier: String? = nil
    ) async throws -> [HanlinScriptPlacemarkValue] {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw HanlinAppleDeviceServiceError.invalidRequest("Invalid reverse-geocoding coordinate.")
        }
        request.preferredLocale = localeIdentifier.map(Locale.init(identifier:))
        let items = try await request.mapItems
        try Task.checkCancellation()
        return Self.placemarks(items)
    }

    private static func placemarks(_ items: [MKMapItem]) -> [HanlinScriptPlacemarkValue] {
        return items.prefix(32).map { item in
            let representations = item.addressRepresentations
            return .init(
                location: Self.value(item.location),
                timeZoneIdentifier: item.timeZone?.identifier,
                name: item.name,
                locality: representations?.cityName,
                isoCountryCode: representations?.region?.identifier,
                country: representations?.regionName
            )
        }
    }

    private static func value(_ location: CLLocation) -> HanlinScriptLocationValue {
        .init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}
#endif
