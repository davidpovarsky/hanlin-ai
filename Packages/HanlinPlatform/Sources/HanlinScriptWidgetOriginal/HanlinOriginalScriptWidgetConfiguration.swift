import Foundation
import SwiftUI
import WidgetKit
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreLocation) && os(iOS)
import CoreLocation
#endif

@MainActor
public struct HanlinOriginalScriptWidgetConfiguration: View {
    private let package: ScriptWidgetPackage
    @State private var healthMessage = ""
    @State private var systemPresented = false
    @State private var cloudPresented = false
    #if canImport(CoreLocation) && os(iOS)
    @StateObject private var location = HanlinOriginalLocationConfiguration()
    #endif

    init(package: ScriptWidgetPackage) { self.package = package }

    private func declared(_ permission: WidgetPackagePermission) -> Bool {
        package.readManifest()?.permissions.contains(permission) == true
    }

    public var body: some View {
        Form {
            if declared(.calendar) {
                Section("Calendar") { CalendarAccessSettingsView() }
            }
            if declared(.reminders) || declared(.remindersWrite) {
                Section("Reminders") { RemindersAccessSettingsView() }
            }
            if declared(.photos) {
                Section("Photos") { PhotosAccessSettingsView() }
            }
            if declared(.music) {
                Section("Music") { ScriptWidgetMusicAccessSettingsView() }
            }
            if declared(.health) {
                Section("Health") {
                    #if canImport(HealthKit)
                    Button("Choose Health Data") {
                        HKHealthStore().requestAuthorization(toShare: [],
                            read: ScriptWidgetRuntimeHealth.authorizationReadTypes) { success, error in
                            DispatchQueue.main.async {
                                WidgetCenter.shared.reloadAllTimelines()
                                healthMessage = error?.localizedDescription
                                    ?? (success ? "Health selection completed." : "Health selection did not complete.")
                            }
                        }
                    }
                    #else
                    Text("HealthKit is unavailable on this platform.")
                    #endif
                    if !healthMessage.isEmpty { Text(healthMessage) }
                }
            }
            if declared(.location) {
                Section("Location") {
                    #if canImport(CoreLocation) && os(iOS)
                    Text(location.status)
                    Button("Use Location") { location.request() }
                    #else
                    Text("Location is unavailable on this platform.")
                    #endif
                }
            }
            if ScriptWidgetSystemAccessView.supports(package) {
                Section("System Data and Actions") {
                    Button("Contacts, Home, Files, Notifications and Alarms") { systemPresented = true }
                }
            }
            if declared(.icloud) {
                Section("iCloud JSON") {
                    Button("Connect Data Store") { cloudPresented = true }
                }
            }
            if declared(.services) {
                Section("Connected Services") {
                    NavigationLink("Service Accounts") {
                        ScriptWidgetServiceAccountsView(model: ScriptWidgetServiceAccountsModel(loadOwners: {
                            guard let scope = package.managedScope, let binding = scope.binding,
                                  let owner = UUID(uuidString: binding.ownerID) else { throw ScriptWidgetServiceError.unavailable }
                            try scope.validate(name: package.name)
                            return [.init(id: owner, name: package.readManifest()?.name ?? package.name,
                                          validate: { try scope.validate(name: package.name) })]
                        }))
                    }
                }
            }
        }
        .navigationTitle("Widget Services")
        .sheet(isPresented: $systemPresented) { ScriptWidgetSystemAccessView(package: package) }
        .sheet(isPresented: $cloudPresented) { ScriptWidgetCloudJSONView(package: package) }
    }
}

extension HanlinOriginalScriptWidgetSession {
    @MainActor
    public var configurationView: HanlinOriginalScriptWidgetConfiguration {
        HanlinOriginalScriptWidgetConfiguration(package: installedPackage)
    }
}

#if canImport(CoreLocation) && os(iOS)
@MainActor
private final class HanlinOriginalLocationConfiguration: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status = "Location has not been requested."
    private let manager = CLLocationManager()
    override init() {
        super.init()
        manager.delegate = self
        update()
    }
    func request() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: update()
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        update()
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) {
            manager.requestLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            ScriptWidgetRuntimeLocation.cacheLocation(location,
                accuracyAuthorization: ScriptWidgetRuntimeLocation.accuracyAuthorizationString(manager))
            WidgetCenter.shared.reloadAllTimelines()
            status = "Location updated for widgets."
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = error.localizedDescription
    }
    private func update() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: status = "Location is available."
        case .notDetermined: status = "Choose location access to use local features."
        case .denied, .restricted: status = "Location is disabled in system Settings."
        @unknown default: status = "Location status is unavailable."
        }
    }
}
#endif
