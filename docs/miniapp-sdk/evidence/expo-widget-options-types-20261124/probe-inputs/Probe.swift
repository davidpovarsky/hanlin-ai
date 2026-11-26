import Foundation
import HanlinPlatformContracts

actor CallbackRecorder {
    private var count = 0
    func publish(_ entrypoint: String, _ variant: String, _ props: [String: HanlinValue]) -> String {
        precondition(entrypoint == "widget-one" && variant == "chosen-variant")
        precondition(props["count"] == .integer(7) && props["visible"] == .bool(true))
        count += 1
        return "actual-probe-callback"
    }
    func callCount() -> Int { count }
}

func expectError(_ label: String, _ operation: () throws -> Void, matches: (Error) -> Bool) {
    do { try operation(); fatalError("Expected error: \(label)") }
    catch { precondition(matches(error), "Unexpected error for \(label): \(error)") }
    print(label)
}

@main struct ProbeMain {
    static func main() async throws {
        let selected = ProbeFixtures.options[0]
        let values = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-one", options: [selected],
            json: #"{"book":"JSON value","limit":7.5,"compact":true,"caption":"מקור"}"#)
        precondition(values["book"] == .string("Genesis"))
        precondition(values["limit"] == .number(7.5) && values["compact"] == .bool(true))
        precondition(values["caption"] == .string("מקור"))
        print("REAL_OPTIONS_VALUES_AND_OVERRIDE_PASS")
        expectError("CANONICAL_EQUIVALENT_KEYS_REJECTED", {
            _ = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-one", options: [],
                json: #"{"e\u0301":null,"\u00e9":"collision"}"#)
        }, matches: { error in
            if case HanlinContractError.duplicateObjectKey(_, let path) = error { return path == "" }
            return false
        })
        expectError("SELECTED_PARAMETER_CANONICAL_ALIAS_REJECTED", {
            _ = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-one", options: [ProbeFixtures.options[2]],
                json: #"{"e\u0301":"JSON value"}"#)
        }, matches: { error in
            if case HanlinContractError.duplicateObjectKey(_, let path) = error { return path == "" }
            return false
        })
        expectError("CONFLICTING_OPTIONS_PRESERVED", {
            _ = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-one", options: ProbeFixtures.options, json: "{}")
        }, matches: { error in
            if case HanlinOriginalExpoWidgetConfigurationError.conflictingOptions("book") = error { return true }
            return false
        })
        expectError("OTHER_WIDGET_OPTION_REJECTED", {
            _ = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-two", options: [selected], json: "{}")
        }, matches: { error in
            if case HanlinOriginalExpoWidgetConfigurationError.unavailableOption = error { return true }
            return false
        })
        expectError("NONOBJECT_JSON_REJECTED", {
            _ = try HanlinOriginalExpoWidgetOptions.values(widgetID: "widget-one", options: [], json: "[]")
        }, matches: { error in
            if case HanlinOriginalExpoWidgetConfigurationError.invalidDictionary = error { return true }
            return false
        })
        let recorder = CallbackRecorder()
        let publisher: PreparedWidgetPublisher = { entrypoint, variant, props in
            await recorder.publish(entrypoint, variant, props)
        }
        let valid = try HanlinJSONValue.decodeCanonicalJSON(Data(#"{"count":7,"visible":true}"#.utf8), limits: .unbounded)
        guard case let .object(rawProps) = valid else { fatalError("Fixture must be an object") }
        let reply = try await publishConverted(entrypointID: "widget-one", variantID: "chosen-variant", rawProps: rawProps, preparedWidgetPublisher: publisher)
        precondition(reply == "actual-probe-callback")
        print("REAL_ADAPTER_CONVERSION_AND_CALLBACK_PASS")
        let collision = try HanlinJSONValue.decodeCanonicalJSON(Data(#"{"e\u0301":null,"\u00e9":"collision"}"#.utf8), limits: .unbounded)
        guard case let .object(collidingProps) = collision else { fatalError("Fixture must be an object") }
        do {
            _ = try await publishConverted(entrypointID: "widget-one", variantID: "chosen-variant", rawProps: collidingProps, preparedWidgetPublisher: publisher)
            fatalError("Colliding properties reached publisher")
        } catch HanlinContractError.duplicateObjectKey(_, let path) {
            precondition(path == "/props")
        }
        let calls = await recorder.callCount()
        precondition(calls == 1)
        print("ADAPTER_COLLISION_REJECTED_BEFORE_CALLBACK")
    }
}
