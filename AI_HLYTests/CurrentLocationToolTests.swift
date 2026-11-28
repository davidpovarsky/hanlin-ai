import CoreLocation
import Foundation
import HanlinScriptDeviceServices
import SwiftData
import Testing
@testable import AI_Hanlin

// These tests cover result composition and the real legacy dispatcher. The device's
// authorization prompt and Core Location updates still require native device verification.
@MainActor
@Suite("Current location and weather tool results")
struct CurrentLocationToolTests {
    @Test(arguments: [false, true])
    func validCoordinatesSurviveUnavailableAddress(emptyAddress: Bool) async throws {
        let coordinate = CLLocationCoordinate2D(latitude: 32.9281, longitude: 35.0820)
        let location = try await getCurrentLocation(
            fetchCoordinate: { coordinate },
            resolveName: { received in
                #expect(received.latitude == coordinate.latitude)
                #expect(received.longitude == coordinate.longitude)
                if emptyAddress { return "  " }
                throw URLError(.notConnectedToInternet)
            }
        )
        #expect(location.latitude == coordinate.latitude)
        #expect(location.longitude == coordinate.longitude)
        #expect(location.name == String(localized: "Your current location"))
        #expect(location.style == "current")
    }

    @Test
    func addressLookupCancellationRemainsCancellation() async {
        do {
            _ = try await getCurrentLocation(
                fetchCoordinate: { .init(latitude: 32.9281, longitude: 35.0820) },
                resolveName: { _ in throw CancellationError() }
            )
            Issue.record("Cancelled address lookup returned a successful location")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test
    func deniedLocationDoesNotAttemptAddressLookup() async {
        var resolvedAddress = false
        do {
            _ = try await getCurrentLocation(
                fetchCoordinate: { throw HanlinAppleDeviceServiceError.denied(.location) },
                resolveName: { _ in resolvedAddress = true; return "Unexpected" }
            )
            Issue.record("Denied location returned success")
        } catch {
            #expect(error as? HanlinAppleDeviceServiceError == .denied(.location))
        }
        #expect(!resolvedAddress)
    }

    @Test
    func currentLocationAppendsToExistingMapPayload() async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        let existing = Location(identifier: "existing", name: "Existing place",
            latitude: 31.778, longitude: 35.235, style: "mark")
        let current = Location(identifier: "current", name: "Akko",
            latitude: 32.9281, longitude: 35.0820, style: "current")
        api.locationsInfo = [existing]
        let (stream, continuation) = AsyncThrowingStream<StreamData, Error>.makeStream()
        let result = await api.executeLegacyTool(name: "get_current_location",
            argumentsJSON: #"{"query":"local"}"#,
            context: .init(localeIdentifier: "en"), continuation: continuation,
            currentLocationProvider: { current })
        continuation.finish()

        #expect(result.outcome == .succeeded)
        #expect(!result.isError)
        #expect(result.hasLegacyPresentationPayload)
        #expect(api.locationsInfo == [existing, current])
        #expect(result.modelText.contains("32.9281"))
        var emittedLocations: [Location]?
        for try await event in stream {
            if let locations = event.locations_info { emittedLocations = locations }
        }
        #expect(emittedLocations == [existing, current])
    }

    @Test(arguments: [false, true])
    func currentLocationFailureAndCancellationAreTruthful(cancelled: Bool) async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        let existing = Location(identifier: "existing", name: "Existing place",
            latitude: 31.778, longitude: 35.235, style: "mark")
        api.locationsInfo = [existing]
        let result = await api.executeLegacyTool(name: "get_current_location",
            argumentsJSON: #"{"query":"local"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil,
            currentLocationProvider: {
                if cancelled { throw CancellationError() }
                throw HanlinAppleDeviceServiceError.denied(.location)
            })
        let expected: NativeToolExecutionOutcome = cancelled ? .cancelled : .failed
        #expect(result.outcome == expected)
        #expect(result.isError)
        #expect(result.diagnostics.backendRoute == "system:corelocation")
        #expect(result.diagnostics.failureCategory == expected.rawValue)
        #expect(result.diagnostics.wasCancelled == cancelled)
        #expect(!result.hasLegacyPresentationPayload)
        #expect(api.locationsInfo == [existing])
    }

    @Test(arguments: [false, true])
    func weatherFailuresAreNotReportedAsSuccess(configuredService: Bool) async throws {
        let container = try database()
        if configuredService {
            // A real OpenWeather request rejects its empty key before any network access.
            container.mainContext.insert(ToolKeys(name: "Weather fixture", company: "OPENWEATHER",
                key: "", isUsing: true, toolClass: "weather"))
            try container.mainContext.save()
        }
        let api = APIManager(context: container.mainContext)
        let result = await api.executeLegacyTool(name: "query_weather",
            argumentsJSON: #"{"latitude":32.9281,"longitude":35.0820,"timeRange":"now"}"#,
            context: .init(localeIdentifier: "en"), continuation: nil)
        #expect(result.outcome == .failed)
        #expect(result.isError)
        #expect(result.diagnostics.failureCategory == NativeToolExecutionOutcome.failed.rawValue)
        #expect(!result.diagnostics.wasCancelled)
        #expect(!result.hasLegacyPresentationPayload)
        #expect(result.modelText.contains(configuredService ? "Failed to fetch weather" : "No active weather service"))
        #expect(result.userText == result.modelText)
    }

    @Test(arguments: ["get_current_location", "query_weather"])
    func alreadyCancelledRequestDoesNotReportSuccess(toolName: String) async throws {
        let container = try database()
        let api = APIManager(context: container.mainContext)
        var fetchedLocation = false
        let task = Task { @MainActor in
            let result = await api.executeLegacyTool(name: toolName,
                argumentsJSON: #"{"query":"local"}"#,
                context: .init(localeIdentifier: "en"), continuation: nil,
                currentLocationProvider: {
                    fetchedLocation = true
                    return Location(name: "Unexpected", latitude: 0, longitude: 0, style: "current")
                })
            #expect(result.outcome == .cancelled)
            #expect(result.diagnostics.wasCancelled)
            #expect(!result.hasLegacyPresentationPayload)
        }
        task.cancel()
        await task.value
        #expect(!fetchedLocation)
        #expect(api.locationsInfo == nil)
    }

    private func database() throws -> ModelContainer {
        try ModelContainer(for: ToolKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
