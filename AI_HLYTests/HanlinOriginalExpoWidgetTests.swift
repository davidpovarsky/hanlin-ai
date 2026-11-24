import CryptoKit
import ExpoModulesCore
@testable import ExpoWidgets
import Foundation
import HanlinWidgetUI
import HanlinPlatformContracts
import WidgetKit
import XCTest

/// Original public registration, storage, timeline parser and configurable
/// provider contract. The original WidgetObject writes its own timeline wire.
@MainActor
final class HanlinOriginalExpoWidgetTests: XCTestCase {
    func testOriginalWidgetRegistrationTimelineAndPickerKeepProductAndInstallationIdentity() async throws {
        let group = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "ExpoWidgetsAppGroupIdentifier") as? String)
        XCTAssertEqual(WidgetsStorage.appGroupIdentifier, group)
        XCTAssertTrue(HanlinExpoWidgetsIntegration.isOriginalRuntimeAvailable,
            "The original Expo Widgets JavaScript runtime must be embedded with its native module.")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: group))
        let token = UUID().uuidString.lowercased()
        let packageID = "test.original-expo." + token
        let firstInstallation = "installed.expo-first." + token
        let secondInstallation = "installed.expo-second." + token
        let currentProduct = HanlinExpoWidgetsIntegration.productIdentifier
        let otherProduct = currentProduct + ".other-product." + token
        // Use the host's real persisted-generation wire, retaining every existing
        // installation. The real app may already have published an empty catalog.
        let productDigest = SHA256.hash(data: Data(currentProduct.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let generationKey = "__hanlin_expo_widget_active_generations_v1." + productDigest
        let originalGenerationData = defaults.data(forKey: generationKey)
        var generations: [String: UInt64]
        if let originalGenerationData {
            generations = try JSONDecoder().decode([String: UInt64].self, from: originalGenerationData)
        } else {
            generations = [:]
            for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("__hanlin_expo_widget_registration_v1.") {
                guard let data = value as? Data,
                      let descriptor = try? JSONDecoder().decode(HanlinExpoWidgetDescriptor.self, from: data),
                      descriptor.productIdentifier == currentProduct, descriptor.isActive else { continue }
                generations[descriptor.installedPackageID] = descriptor.generation
            }
        }
        generations[firstInstallation] = 1
        generations[secondInstallation] = 1
        let generationFixture = try JSONEncoder().encode(generations)
        defer {
            if let originalGenerationData { defaults.set(originalGenerationData, forKey: generationKey) }
            else { defaults.removeObject(forKey: generationKey) }
        }
        defaults.set(generationFixture, forKey: generationKey)
        let first = AppContext()
        let second = AppContext()
        let other = AppContext()
        HanlinExpoWidgetsIntegration.bind(appContext: first, packageID: packageID,
            installedPackageID: firstInstallation, generation: 1, sessionID: "first-" + token)
        HanlinExpoWidgetsIntegration.bind(appContext: second, packageID: packageID,
            installedPackageID: secondInstallation, generation: 1, sessionID: "second-" + token)
        HanlinExpoWidgetsIntegration.bind(appContext: other, packageID: packageID,
            installedPackageID: firstInstallation, generation: 1, sessionID: "other-" + token, productIdentifier: otherProduct)
        var registrations: [String] = []
        defer {
            for id in registrations {
                defaults.removeObject(forKey: "__hanlin_expo_widget_registration_v1." + id)
                for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("__expo_widgets_" + id + "_") {
                    defaults.removeObject(forKey: key)
                }
            }
            HanlinExpoWidgetsIntegration.unbind(appContext: first)
            HanlinExpoWidgetsIntegration.unbind(appContext: second)
            HanlinExpoWidgetsIntegration.unbind(appContext: other)
        }
        let name = "Original widget – מקור"
        let firstID = try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: first)
        registrations.append(firstID)
        let secondID = try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: second)
        registrations.append(secondID)
        let otherID = try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: other)
        registrations.append(otherID)
        XCTAssertEqual(Set(registrations).count, 3)
        XCTAssertEqual(try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: first), firstID)
        let owned = HanlinExpoWidgetsIntegration.registeredWidgets().filter { $0.packageID == packageID }
        XCTAssertEqual(Set(owned.map(\.id)), [firstID, secondID])
        XCTAssertTrue(owned.allSatisfy { $0.productIdentifier == currentProduct && $0.generation == 1 && $0.isActive })

        let layout = "(props) => ({type: 'TextView', props: {text: props.label}})"
        let widget = WidgetObject(name: firstID, layout: layout, initialProps: ["label": "initial"])
        XCTAssertEqual(WidgetsLayoutRegistry.layout(for: firstID), layout)
        XCTAssertEqual(HanlinExpoWidgetsIntegration.placeholder(named: firstID).props?["label"] as? String, "initial")
        let timestamp = Int(Date.now.timeIntervalSince1970 * 1_000)
        var firstEntry = WidgetsJSTimelineEntry()
        firstEntry.timestamp = timestamp
        firstEntry.props = ["label": "מקור", "count": 1]
        var nextEntry = WidgetsJSTimelineEntry()
        nextEntry.timestamp = timestamp + 60_000
        nextEntry.props = ["label": "next", "count": 2]
        try widget.updateTimeline(entries: [firstEntry, nextEntry])

        let originalTimeline = HanlinExpoWidgetsIntegration.timeline(named: firstID, family: .systemMedium)
        XCTAssertEqual(originalTimeline.entries.count, 2)
        XCTAssertEqual(originalTimeline.entries[0].name, firstID)
        XCTAssertEqual(originalTimeline.entries[0].entryIndex, 0)
        XCTAssertEqual(originalTimeline.entries[0].props?["label"] as? String, "מקור")
        XCTAssertEqual(originalTimeline.entries[1].date.timeIntervalSince1970,
            Double(timestamp + 60_000) / 1_000, accuracy: 0.001)
        var genesis = WidgetConfigurationOptionRecord()
        genesis.name = "בראשית"
        genesis.value = "Genesis"
        genesis.subtitle = "ספר ראשון"
        var exodus = WidgetConfigurationOptionRecord()
        exodus.name = "שמות"
        exodus.value = "Exodus"
        widget.setConfigurationParameterEnum(parameterName: "book", options: [genesis, exodus])
        let actualOptions = HanlinOriginalExpoWidgetOptions.options(widgetID: firstID)
        XCTAssertEqual(Set(actualOptions.map(\.value)), ["Genesis", "Exodus"])
        let selected = try XCTUnwrap(actualOptions.first { $0.value == "Genesis" })
        XCTAssertEqual(selected.parameter, "book")
        XCTAssertEqual(selected.name, "בראשית")
        XCTAssertEqual(selected.subtitle, "ספר ראשון")
        let restoredOptions = try await HanlinOriginalExpoWidgetOptionQuery().entities(for: [selected.id])
        XCTAssertEqual(restoredOptions.map(\.id), [selected.id])
        let configuration = try HanlinOriginalExpoWidgetOptions.values(widgetID: firstID, options: [selected],
            json: #"{"book":"JSON value","limit":7.5,"compact":true,"caption":"מקור"}"#)
        XCTAssertEqual(configuration["book"], .string("Genesis"))
        XCTAssertEqual(configuration["limit"], .number(7.5))
        XCTAssertEqual(configuration["compact"], .bool(true))
        let configuredLayout = """
          (props, environment) => ({type: 'TextView', props: {
            text: environment.configuration.book + '|' +
              typeof environment.configuration.limit + '|' + environment.configuration.limit + '|' +
              typeof environment.configuration.compact + '|' + environment.configuration.compact + '|' +
              environment.configuration.caption
          }})
          """
        let configuredNode = evaluateLayout(layout: configuredLayout, props: [:],
            environment: ["configuration": configuration.mapValues { $0.toAny() }])
        XCTAssertEqual((configuredNode["props"] as? [String: Any])?["text"] as? String,
            "Genesis|number|7.5|boolean|true|מקור")
        _ = WidgetsEntryView(entry: originalTimeline.entries[0], configuration: configuration.mapValues { $0.toAny() })
        XCTAssertThrowsError(try HanlinOriginalExpoWidgetOptions.values(widgetID: firstID, options: actualOptions, json: "{}"))
        XCTAssertThrowsError(try HanlinOriginalExpoWidgetOptions.values(widgetID: secondID, options: [selected], json: "{}"))
        XCTAssertThrowsError(try HanlinOriginalExpoWidgetOptions.values(widgetID: firstID, options: [], json: "[]"))
        widget.setConfigurationParameterEnum(parameterName: "book", options: nil)
        XCTAssertThrowsError(try HanlinOriginalExpoWidgetOptions.values(widgetID: firstID, options: [selected], json: "{}"))
        _ = WidgetsTimelineProvider(name: firstID)
        _ = WidgetsEntryView(entry: originalTimeline.entries[0])
        _ = HanlinOriginalExpoWidget()
        let picker = try await HanlinOriginalExpoWidgetEntityQuery().entities(for: [firstID, secondID, otherID])
        XCTAssertEqual(Set(picker.map(\.id)), [firstID, secondID])
        XCTAssertTrue(picker.allSatisfy { $0.name == name && $0.packageID == packageID })
    }
}
