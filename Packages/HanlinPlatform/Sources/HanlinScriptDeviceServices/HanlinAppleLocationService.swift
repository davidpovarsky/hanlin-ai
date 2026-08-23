#if os(iOS)
import CoreLocation
import Foundation

@MainActor
public final class HanlinAppleLocationService {
    private let manager: CLLocationManager

    public init(manager: CLLocationManager = .init()) { self.manager = manager }

    public func currentLocation() async throws -> HanlinScriptLocationValue {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        for try await update in CLLocationUpdate.liveUpdates() {
            try Task.checkCancellation()
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw HanlinAppleDeviceServiceError.denied(.location)
            }
            if let location = update.location {
                return .init(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.altitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    timestamp: location.timestamp
                )
            }
        }
        throw HanlinAppleDeviceServiceError.noData(.location)
    }
}
#endif
