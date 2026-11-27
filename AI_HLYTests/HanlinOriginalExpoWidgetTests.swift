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
        let defaults = try XCTUnwrap(UserDefaults(suiteName: group))
        let token = UUID().uuidString.lowercased()
        let groupProbeKey = "__hanlin_original_expo_group_probe." + token
        defer { defaults.removeObject(forKey: groupProbeKey) }
        defaults.set(group, forKey: groupProbeKey)
        XCTAssertEqual(WidgetsStorage.getString(forKey: groupProbeKey), group,
            "The original Expo widget storage must reach the declared app-group suite.")
        XCTAssertTrue(HanlinExpoWidgetsIntegration.isOriginalRuntimeAvailable,
            "The original Expo Widgets JavaScript runtime must be embedded with its native module.")
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
            if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                for installation in [firstInstallation, secondInstallation] {
                    let namespace = SHA256.hash(data: Data([currentProduct, installation].joined(separator: "\0").utf8))
                        .map { String(format: "%02x", $0) }.joined()
                    try? FileManager.default.removeItem(at: container.appendingPathComponent("ExpoWidgets")
                        .appendingPathComponent(namespace))
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
        let captured = try XCTUnwrap(originalTimeline.entries.first?.snapshotProof)
        generations[firstInstallation] = 2
        defaults.set(try JSONEncoder().encode(generations), forKey: generationKey)
        HanlinExpoWidgetsIntegration.bind(appContext: first, packageID: packageID,
            installedPackageID: firstInstallation, generation: 2, sessionID: "upgraded-" + token)
        XCTAssertEqual(try HanlinExpoWidgetsIntegration.qualifiedName(name, kind: "widget", appContext: first), firstID)
        _ = WidgetObject(name: firstID, layout: layout, initialProps: ["label": "generation two"])
        let current = try XCTUnwrap(HanlinExpoWidgetState.snapshot(firstID))
        XCTAssertNotEqual(captured, current.proof)
        XCTAssertEqual(current.timeline.first?["props"] as? [String: String], ["label": "generation two"],
            "A new generation must not migrate the prior generation's unqualified timeline.")
        let stale = HanlinExpoWidgetState.render(name: firstID, layout: layout,
            props: ["label": "captured generation one"], environment: ["widgetFamily": "systemMedium"], proof: captured)
        XCTAssertFalse(stale.retained)
        XCTAssertNotEqual((stale.node["props"] as? [String: Any])?["text"] as? String, "captured generation one")
        let staleEnvironment = try JSONSerialization.data(withJSONObject: captured.environment.merging([
            "timestamp": timestamp, "widgetFamily": "systemMedium"
        ]) { _, current in current })
        XCTAssertThrowsError(try HanlinExpoWidgetState.performInteraction(source: firstID, target: "any",
            entryIndex: 0, environmentString: String(decoding: staleEnvironment, as: UTF8.self), desiredValue: true))
        // A disabled installation retains its user's configuration, but its
        // original callbacks and stored timeline are not executable/readable.
        generations.removeValue(forKey: firstInstallation)
        defaults.set(try JSONEncoder().encode(generations), forKey: generationKey)
        XCTAssertNil(HanlinExpoWidgetsIntegration.storageOwner(firstID))
        XCTAssertNil(HanlinExpoWidgetState.timeline(firstID))
        XCTAssertThrowsError(try widget.updateTimeline(entries: [firstEntry]))
        XCTAssertTrue(HanlinExpoWidgetsIntegration.registeredWidgetNames().contains(secondID))
    }
    func testOriginalToggleUsesIntendedValuesAndAtomicTimelineThroughRealRuntime() async throws {
        let name = "test.widget.wave2." + UUID().uuidString
        defer { removeWave2Widget(name) }
        let layout = """
        (props) => ({type: 'ToggleView', props: {
          target: 'enabled', isOn: props.enabled, label: 'Notifications',
          onIsOnChange: event => {
            if (props.reject) throw Error('author callback failed');
            return {enabled: event.nativeEvent.isOn, count: props.count + 1};
          }
        }})
        """
        let widget = WidgetObject(name: name, layout: layout, initialProps: ["enabled": false, "count": 0])
        var entry = WidgetsJSTimelineEntry()
        entry.timestamp = Int(Date.now.timeIntervalSince1970 * 1_000)
        entry.props = ["enabled": false, "count": 0]
        try widget.updateTimeline(entries: [entry])
        let proof = try XCTUnwrap(HanlinExpoWidgetState.snapshot(name)?.proof)
        let environment = try JSONSerialization.data(withJSONObject: proof.environment.merging([
            "timestamp": entry.timestamp, "widgetFamily": "systemMedium"
        ]) { _, current in current })
        let wire = String(decoding: environment, as: UTF8.self)
        for value in [true, true, false] {
            _ = try await WidgetSetValue(source: name, target: "enabled", entryIndex: 0,
                environmentString: wire, value: value).perform()
            let state = try XCTUnwrap(HanlinExpoWidgetState.timeline(name)?.first?["props"] as? [String: Any])
            XCTAssertEqual(state["enabled"] as? Bool, value)
        }
        // All callers read and mutate under the same cross-process lock.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try HanlinExpoWidgetState.performInteraction(source: name, target: "enabled",
                        entryIndex: 0, environmentString: wire, desiredValue: true)
                }
            }
            try await group.waitForAll()
        }
        var state = try XCTUnwrap(HanlinExpoWidgetState.timeline(name)?.first?["props"] as? [String: Any])
        XCTAssertEqual(state["enabled"] as? Bool, true)
        XCTAssertEqual(state["count"] as? Int, 15, "Concurrent callbacks must not lose another invocation's update.")
        XCTAssertThrowsError(try widget.updateTimeline(entries: []))
        XCTAssertEqual((HanlinExpoWidgetState.timeline(name)?.first?["props"] as? [String: Any])?["count"] as? Int, 15)
        state["reject"] = true
        entry.props = state
        try widget.updateTimeline(entries: [entry])
        do {
            _ = try await WidgetSetValue(source: name, target: "enabled", entryIndex: 0,
                environmentString: wire, value: false).perform()
            XCTFail("A thrown source callback must reject the native intent.")
        } catch {}
        let restored = try XCTUnwrap(HanlinExpoWidgetState.timeline(name)?.first?["props"] as? [String: Any])
        XCTAssertEqual(restored["enabled"] as? Bool, true, "Failure must not optimistically commit a Toggle value.")
        XCTAssertEqual(restored["count"] as? Int, 15)
        let persisted = try XCTUnwrap(WidgetsStorage.getArray(forKey: "__expo_widgets_\(name)_timeline")?.first as? [String: Any])
        XCTAssertEqual((persisted["props"] as? [String: Any])?["count"] as? Int, 15)
    }

    func testOriginalExpoRetainsSuccessfulRenderOnlyForMatchingWidgetAndConfiguration() throws {
        let first = "test.widget.wave2." + UUID().uuidString
        let second = "test.widget.wave2." + UUID().uuidString
        defer { removeWave2Widget(first); removeWave2Widget(second) }
        let layout = "(props) => { if (props.fail) throw Error('offline'); return {type:'TextView',props:{text:props.label}}; }"
        _ = WidgetObject(name: first, layout: layout, initialProps: ["label": "first"])
        _ = WidgetObject(name: second, layout: layout, initialProps: ["label": "second"])
        let environment: [String: Any] = ["widgetFamily": "systemExtraLargePortrait",
            "colorScheme": "dark", "widgetRenderingMode": "fullColor", "configuration": ["caption": "שקוף"]]
        let firstProof = try XCTUnwrap(HanlinExpoWidgetState.snapshot(first)?.proof)
        let secondProof = try XCTUnwrap(HanlinExpoWidgetState.snapshot(second)?.proof)
        let good = HanlinExpoWidgetState.render(name: first, layout: layout,
            props: ["label": "Last actual content"], environment: environment, proof: firstProof)
        XCTAssertFalse(good.retained)
        let retained = HanlinExpoWidgetState.render(name: first, layout: layout,
            props: ["fail": true], environment: environment, proof: firstProof)
        XCTAssertTrue(retained.retained)
        XCTAssertEqual((retained.node["props"] as? [String: Any])?["text"] as? String, "Last actual content")
        XCTAssertFalse(HanlinExpoWidgetState.render(name: second, layout: layout,
            props: ["fail": true], environment: environment, proof: secondProof).retained,
            "The same source must not restore another installation's rendered content.")
        var changed = environment
        changed["configuration"] = ["caption": "different user choice"]
        XCTAssertFalse(HanlinExpoWidgetState.render(name: first, layout: layout,
            props: ["fail": true], environment: changed, proof: firstProof).retained)
        let upgradedLayout = "(props) => { if (props.fail) throw Error('offline'); return {type:'TextView',props:{text:'new generation'}}; }"
        _ = WidgetObject(name: first, layout: upgradedLayout, initialProps: ["label": "new initial"])
        let stale = HanlinExpoWidgetState.render(name: first, layout: layout,
            props: ["label": "stale source output"], environment: environment, proof: firstProof)
        XCTAssertFalse(stale.retained)
        XCTAssertNotEqual((stale.node["props"] as? [String: Any])?["text"] as? String, "stale source output")
        XCTAssertFalse(HanlinExpoWidgetState.render(name: first, layout: upgradedLayout,
            props: ["fail": true], environment: environment, proof: HanlinExpoWidgetState.snapshot(first)?.proof).retained,
            "An old layout must not populate the new layout's retained render.")
    }

    private func removeWave2Widget(_ name: String) {
        guard name.hasPrefix("test.widget.wave2.") else { return }
        if let owner = HanlinExpoWidgetsIntegration.storageOwner(name),
           let group = Bundle.main.object(forInfoDictionaryKey: "ExpoWidgetsAppGroupIdentifier") as? String,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            try? FileManager.default.removeItem(at: container.appendingPathComponent("ExpoWidgets")
                .appendingPathComponent(owner.namespace))
        }
        for key in (WidgetsStorage.defaults?.dictionaryRepresentation() ?? [:]).keys
            where key.hasPrefix("__expo_widgets_\(name)_") {
            WidgetsStorage.defaults?.removeObject(forKey: key)
        }
    }

}
