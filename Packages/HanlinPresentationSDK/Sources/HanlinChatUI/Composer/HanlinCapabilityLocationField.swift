import SwiftUI
import MapKit
import HanlinLocalization
import HanlinPlatformContracts

/// A real MapKit location chooser. Panning and tapping only update the draft;
/// there is no location permission request and no places search on selection.
struct HanlinCapabilityLocationField: View {
    let title: String
    let fieldKey: String
    @Binding var value: HanlinJSONValue?
    let minimumRadius: Double?
    let maximumRadius: Double?
    @State private var position: MapCameraPosition
    @State private var visibleCenter: CLLocationCoordinate2D?

    init(title: String, fieldKey: String, value: Binding<HanlinJSONValue?>,
         minimumRadius: Double?, maximumRadius: Double?) {
        self.title = title
        self.fieldKey = fieldKey
        _value = value
        self.minimumRadius = minimumRadius
        self.maximumRadius = maximumRadius
        if let coordinate = Self.coordinate(in: value.wrappedValue) {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))))
        } else {
            _position = State(initialValue: .automatic)
        }
    }

    private static func coordinate(in value: HanlinJSONValue?) -> CLLocationCoordinate2D? {
        guard case let .object(location)? = value,
              let latitude = location["latitude"]?.composerNumber,
              let longitude = location["longitude"]?.composerNumber else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private var coordinate: CLLocationCoordinate2D? { Self.coordinate(in: value) }
    private var radius: Double? {
        guard case let .object(location)? = value else { return nil }
        return location["radiusMeters"]?.composerNumber
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate {
                            Marker(title, coordinate: coordinate)
                            if let radius, radius > 0, radius.isFinite {
                                MapCircle(center: coordinate, radius: radius)
                                    .foregroundStyle(.blue.opacity(0.12))
                                    .stroke(.blue.opacity(0.7), lineWidth: 1)
                            }
                        }
                    }
                    .mapControls { MapCompass(); MapScaleView() }
                    .onTapGesture(coordinateSpace: .local) { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            select(coordinate)
                        }
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        visibleCenter = context.region.center
                    }
                }
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel(title)
                .accessibilityIdentifier("hanlin-capability-location-map")

                Text("hanlin.composer.capabilities.mapHint", bundle: HanlinLocalization.bundle)
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    if let visibleCenter { select(visibleCenter) }
                } label: {
                    Label(String(localized: "hanlin.composer.capabilities.useMapCenter",
                                 bundle: HanlinLocalization.bundle), systemImage: "mappin.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(visibleCenter == nil)
                .accessibilityIdentifier("hanlin-capability-location-center")

                // Native text controls keep selection possible with VoiceOver
                // and a hardware keyboard as well as direct map interaction.
                HanlinCapabilityNumberField(
                    title: String(localized: "hanlin.composer.capabilities.latitude", bundle: HanlinLocalization.bundle),
                    value: member("latitude"),
                    accessibilityID: "hanlin-capability-input-\(fieldKey).latitude")
                HanlinCapabilityNumberField(
                    title: String(localized: "hanlin.composer.capabilities.longitude", bundle: HanlinLocalization.bundle),
                    value: member("longitude"),
                    accessibilityID: "hanlin-capability-input-\(fieldKey).longitude")
                HanlinCapabilityNumberField(
                    title: String(localized: "hanlin.composer.capabilities.radius", bundle: HanlinLocalization.bundle),
                    value: member("radiusMeters"),
                    accessibilityID: "hanlin-capability-input-\(fieldKey).radiusMeters")
            }
        }
    }

    private func member(_ key: String) -> Binding<HanlinJSONValue?> {
        Binding(get: {
            guard case let .object(location)? = value else { return nil }
            return location[key]
        }, set: { newValue in
            var location: HanlinObject<HanlinJSONValue>
            if case let .object(existing)? = value { location = existing } else { location = [:] }
            location[key] = newValue
            value = .object(location)
        })
    }

    private func select(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        var location: HanlinObject<HanlinJSONValue>
        if case let .object(existing)? = value { location = existing } else { location = [:] }
        location["latitude"] = .number(coordinate.latitude)
        location["longitude"] = .number(coordinate.longitude)
        if location["radiusMeters"] == nil {
            let preferredRadius = max(minimumRadius ?? 0, min(1_000, maximumRadius ?? 1_000))
            location["radiusMeters"] = .number(preferredRadius)
        }
        value = .object(location)
    }
}
