import HanlinPlatformContracts
@testable import HanlinScriptingApplicationRuntime
import Foundation
import Testing

@Suite("Scripting application runtime", .serialized)
struct HanlinScriptingApplicationRuntimeTests {
    @MainActor
    @Test("Compiles and renders independently of the application target")
    func rendersIndependently() throws {
        let packageID = try HanlinInstalledPackageID(validating: "fast-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"Navigation.present({ element: createElement(Text, null, "Ready") });"#,
            filename: "compiled/index.js",
            storageAllowed: false
        )
        defer { session.dispose() }

        #expect(session.model.root.kind == .text)
        #expect(session.model.root.properties["text"] == .string("Ready"))
    }

    @MainActor
    @Test("Renders a family-specific widget and preserves its reload date")
    func rendersWidgetEntrypoint() throws {
        let packageID = try HanlinInstalledPackageID(validating: "widget-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"Widget.present(createElement(Text, null, Widget.family), { policy: "after", date: new Date(1_800_000) });"#,
            filename: "compiled/widget.js",
            entrypointContext: .widget(family: "systemLarge", parameter: "daily"),
            storageAllowed: true
        )
        defer { session.dispose() }

        #expect(session.widgetPresentation?.root.kind == .text)
        #expect(session.widgetPresentation?.root.properties["text"] == .string("systemLarge"))
        #expect(session.widgetPresentation?.reloadDate == Date(timeIntervalSince1970: 1_800))
    }

    @MainActor
    @Test("Registers bounded App Intent actions without requiring application UI")
    func registersAppIntents() async throws {
        let packageID = try HanlinInstalledPackageID(validating: "app-intent-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"AppIntentManager.register({ name: "CompleteStationIntent", protocol: AppIntentProtocol.AppIntent, perform: async params => { Widget.reloadAll(); return { stationId: params.stationId }; } });"#,
            filename: "compiled/app_intents.js",
            entrypointContext: .appIntentRegistration,
            storageAllowed: true
        )
        defer { session.dispose() }

        #expect(session.appIntentRegistrations == [.init(
            name: "CompleteStationIntent",
            protocolName: "AppIntent"
        )])
        let result = try await session.invokeAppIntent(
            name: "CompleteStationIntent",
            parameters: .object(try .init(uniqueMembers: [("stationId", .integer(7))]))
        )
        #expect(result == .object(try .init(uniqueMembers: [("stationId", .integer(7))])))
        #expect(session.requestedWidgetReload)
    }

    @MainActor
    @Test("Projects the native device snapshot into an immutable Scripting Device object")
    func deviceSnapshot() throws {
        let packageID = try HanlinInstalledPackageID(validating: "device-runtime-test")
        let snapshot = HanlinScriptingDeviceSnapshot(
            model: "iPad",
            localizedModel: "iPad",
            systemVersion: "26.5",
            systemName: "iPadOS",
            isiPad: true,
            isiPhone: false,
            screen: .init(width: 744, height: 1133, scale: 2),
            batteryState: "charging",
            batteryLevel: 0.75,
            proximityState: false,
            orientation: "landscapeRight",
            colorScheme: "dark",
            isiOSAppOnMac: false,
            systemLocale: "he_IL",
            preferredLanguages: ["he-IL", "en-US"],
            systemLanguageTag: "he-IL",
            systemLanguageCode: "he",
            systemCountryCode: "IL",
            systemScriptCode: "Hebr"
        )
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, JSON.stringify([
              Device.model, Device.systemName, Device.screen.width, Device.batteryState,
              Device.orientation, Device.colorScheme, Device.systemLanguageCode,
              Device.systemCountryCode, Device.isLandscape, Device.isPortrait,
              Object.isFrozen(Device), Object.isFrozen(Device.screen),
              Object.isFrozen(Device.preferredLanguages)
            ])) });
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            deviceSnapshot: snapshot
        )
        defer { session.dispose() }

        #expect(session.model.root.properties["text"] == .string(
            #"["iPad","iPadOS",744,"charging","landscapeRight","dark","he","IL",true,false,true,true,true]"#
        ))
    }

    @MainActor
    @Test("Runs FileManager and nativ-ai Pasteboard and Safari calls through the native system channel")
    func pasteboardAndSafariRuntime() async throws {
        let packageID = try HanlinInstalledPackageID(validating: "system-service-runtime-test")
        let recorder = HanlinSystemOperationRecorder()
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            Promise.all([
              Pasteboard.setString("/documents/report.txt"),
              Safari.openURL("https://example.com/settings")
            ]).then(async ([, opened]) => {
              const copied = await Pasteboard.getString();
              Navigation.present({ element: createElement(Text, null, JSON.stringify([copied, opened])) });
            });
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            systemLoader: { operation, payloadJSON in
                recorder.operations.append(operation)
                if operation == "pasteboard.setString" {
                    let payload = try #require(
                        JSONSerialization.jsonObject(with: Data(payloadJSON.utf8)) as? [String: String]
                    )
                    #expect(payload["value"] == "/documents/report.txt")
                    return .null
                }
                if operation == "pasteboard.getString" { return .string("/documents/report.txt") }
                if operation == "safari.openURL" { return .bool(true) }
                Issue.record("Unexpected system operation: \(operation)")
                return .null
            }
        )
        defer { session.dispose() }

        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string(#"["/documents/report.txt",true]"#))
        #expect(recorder.operations == ["pasteboard.setString", "safari.openURL", "pasteboard.getString"])
    }

    @MainActor
    @Test("Runs the nativ-ai Reminder creation flow and returns the EventKit identifier")
    func reminderRuntime() async throws {
        let packageID = try HanlinInstalledPackageID(validating: "reminder-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            (async () => {
              const params = {
                title: "Take medicine",
                notes: "After dinner",
                dueDateISO: "2027-02-03T18:45:00Z",
                priority: "high"
              };
              const reminder = new Reminder();
              reminder.title = params.title || "Reminder";
              if (params.notes) reminder.notes = params.notes;
              if (params.dueDateISO) {
                const date = new Date(params.dueDateISO);
                reminder.dueDateComponents = new DateComponents({
                  year: date.getUTCFullYear(), month: date.getUTCMonth() + 1,
                  day: date.getUTCDate(), hour: date.getUTCHours(), minute: date.getUTCMinutes()
                });
              }
              reminder.priority = params.priority === "high" ? 1 : 0;
              await reminder.save();
              Navigation.present({ element: createElement(Text, null, JSON.stringify({
                ok: true, identifier: reminder.identifier
              })) });
            })().catch(error => {
              Navigation.present({ element: createElement(Text, null, `ERROR:${error?.message ?? error}`) });
            });
            """#,
            filename: "compiled/tools/reminder.js",
            storageAllowed: false,
            remindersAllowed: true,
            reminderLoader: { request in
                #expect(request.title == "Take medicine")
                #expect(request.notes == "After dinner")
                #expect(request.priority == 1)
                #expect(request.dueDateComponents == [
                    "year": 2027, "month": 2, "day": 3, "hour": 18, "minute": 45,
                ])
                return "eventkit-reminder-id"
            }
        )
        defer { session.dispose() }

        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string(
            #"{"ok":true,"identifier":"eventkit-reminder-id"}"#
        ))
    }

    @Test("Rejects malformed Reminder payloads before invoking EventKit")
    func reminderPayloadValidation() throws {
        let request = try HanlinScriptingReminderPayloadDecoder.decode(
            operation: "reminder.save",
            json: #"{"title":"Call home","notes":null,"priority":5,"dueDateComponents":{"year":2027,"month":3,"day":4}}"#
        )
        #expect(request.title == "Call home")
        #expect(request.priority == 5)
        #expect(request.dueDateComponents == ["year": 2027, "month": 3, "day": 4])

        #expect(throws: HanlinScriptingNativeError.self) {
            try HanlinScriptingReminderPayloadDecoder.decode(
                operation: "reminder.save",
                json: #"{"title":"","priority":20}"#
            )
        }
    }

    @MainActor
    @Test("Imports FileManager selections and previews the package copy through system UI")
    func documentPickerAndQuickLookRuntime() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-system-ui-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let selectedDirectory = root.appending(path: "Selected", directoryHint: .isDirectory)
        let selectedFile = selectedDirectory.appending(path: "source note.txt", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        try Data("selected-content".utf8).write(to: selectedFile)
        defer { try? FileManager.default.removeItem(at: root) }

        let packageID = try HanlinInstalledPackageID(validating: "system-ui-runtime-test")
        var operations: [String] = []
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            (async () => {
              const picked = await DocumentPicker.pickFiles({
                allowsMultipleSelection: true,
                shouldShowFileExtensions: true,
                types: ["public.text"]
              });
              const destination = Path.join(FileManager.documentsDirectory, "imported.txt");
              await FileManager.copyFile(picked[0], destination);
              const directory = await DocumentPicker.pickDirectory();
              await QuickLook.previewURLs([encodeURI(destination)]);
              DocumentPicker.stopAcessingSecurityScopedResources();
              Navigation.present({ element: createElement(Text, null, JSON.stringify([
                FileManager.readAsStringSync(destination), directory != null
              ])) });
            })().catch(error => {
              Navigation.present({ element: createElement(Text, null, `ERROR:${error?.message ?? error}`) });
            });
            """#,
            filename: "compiled/file-manager-system-ui.js",
            storageAllowed: false,
            filesAllowed: true,
            runtimeRoot: root.appending(path: "Runtime", directoryHint: .isDirectory),
            systemUILoader: { request in
                switch request {
                case let .pickFiles(multiple, extensions, types):
                    operations.append("pickFiles")
                    #expect(FileManager.default.fileExists(atPath: selectedFile.path(percentEncoded: false)))
                    #expect(multiple)
                    #expect(extensions)
                    #expect(types == ["public.text"])
                    return .urls([selectedFile])
                case .pickDirectory:
                    operations.append("pickDirectory")
                    return .urls([selectedDirectory])
                case let .previewURLs(urls):
                    operations.append("previewURLs")
                    #expect(urls.count == 1)
                    let url = try #require(urls.first)
                    let content = try String(contentsOf: url, encoding: .utf8)
                    #expect(content == "selected-content")
                    return .completed
                }
            }
        )
        defer { session.dispose() }

        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string(#"["selected-content",true]"#))
        #expect(operations == ["pickFiles", "pickDirectory", "previewURLs"])
    }

    @Test("Decodes bounded Assistant requests and emits Web-compatible chunks")
    func assistantNativePayloads() throws {
        let request = try HanlinScriptingAssistantPayloadDecoder.decode(#"""
        {
          "kind": "streaming",
          "systemPrompt": "Be concise",
          "messages": [{"role":"user","content":"Hello"}],
          "provider": {"custom":"https://assistant.example/v1"},
          "modelId": "test-model"
        }
        """#)
        #expect(request.kind == .streaming)
        #expect(request.provider == .custom("https://assistant.example/v1"))
        #expect(request.modelID == "test-model")
        #expect(request.messagesJSON != nil)

        let usage = try HanlinScriptingAssistantChunk.usage(.init(
            totalCost: nil,
            cacheReadTokens: 4,
            inputTokens: 7,
            outputTokens: 3
        )).nativeObject()
        #expect(usage["type"] as? String == "usage")
        let content = try #require(usage["content"] as? [String: Any])
        #expect(content["inputTokens"] as? Int == 7)

        let structured = try HanlinScriptingAssistantChunk.structuredJSON(
            Data(#"{"answer":"verified"}"#.utf8)
        ).nativeObject()
        #expect(structured["type"] as? String == "structured")
        #expect((structured["content"] as? [String: Any])?["answer"] as? String == "verified")
    }

    @Test("SQLite executes parameterized statements and returns typed rows")
    func sqliteRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-sqlite-test-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let fileSystem = try HanlinScriptingPackageFileSystem(
            installedPackageID: "sqlite-test",
            allowed: true,
            runtimeRoot: root,
            packageSourceDirectory: nil
        )
        let store = HanlinScriptingSQLiteStore(fileSystem: fileSystem)
        let prefix = #"{"handle":"database-1","path":"/app-group/history.sqlite","configuration":{"foreignKeysEnabled":true,"journalMode":"wal","busyMode":1},"#
        _ = try store.perform(
            operation: "sqlite.execute",
            payloadJSON: prefix + #""sql":"CREATE TABLE items (id TEXT PRIMARY KEY, count INTEGER, enabled INTEGER)","arguments":null}"#
        )
        _ = try store.perform(
            operation: "sqlite.execute",
            payloadJSON: prefix + #""sql":"INSERT INTO items VALUES (:id, :count, :enabled)","arguments":{"id":"one","count":7,"enabled":1}}"#
        )
        let result = try store.perform(
            operation: "sqlite.fetchAll",
            payloadJSON: prefix + #""sql":"SELECT id, count, enabled FROM items WHERE id = ?","arguments":["one"]}"#
        )
        let rows = try #require(result as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows[0]["id"] as? String == "one")
        #expect((rows[0]["count"] as? NSNumber)?.intValue == 7)
        #expect((rows[0]["enabled"] as? NSNumber)?.intValue == 1)
    }

    @Test("Location requests validate capabilities, coordinates, locales, and accuracy")
    func locationPayloads() throws {
        let current = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.requestCurrent",
            json: #"{"forceRequest":true}"#
        )
        #expect(current.action == .requestCurrent)
        #expect(current.forceRequest)

        let reverse = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.reverseGeocode",
            json: #"{"latitude":31.7683,"longitude":35.2137,"locale":"he_IL"}"#
        )
        #expect(reverse.latitude == 31.7683)
        #expect(reverse.longitude == 35.2137)
        #expect(reverse.localeIdentifier == "he_IL")

        let accuracy = try HanlinScriptingLocationPayloadDecoder.decode(
            operation: "location.setAccuracy",
            json: #"{"accuracy":"hundredMeters"}"#
        )
        #expect(accuracy.accuracy == "hundredMeters")

        #expect(throws: (any Error).self) {
            try HanlinScriptingLocationPayloadDecoder.decode(
                operation: "location.reverseGeocode",
                json: #"{"latitude":91,"longitude":35}"#
            )
        }
        #expect(throws: (any Error).self) {
            try HanlinScriptingLocationPayloadDecoder.decode(
                operation: "location.setAccuracy",
                json: #"{"accuracy":"unbounded"}"#
            )
        }
    }

    @Test("Health and Notification payloads reject unsupported or unbounded requests")
    func healthAndNotificationPayloads() throws {
        let health = try HanlinScriptingHealthPayloadDecoder.decodeStatistics(#"""
        {
          "quantityType":"heartRate",
          "startDate":1759276800000,
          "endDate":1759363200000,
          "statisticsOptions":["discreteAverage"]
        }
        """#)
        #expect(health.metric == .heartRate)
        #expect(health.options == [.discreteAverage])

        let activity = try HanlinScriptingHealthPayloadDecoder.decodeActivitySummaries(
            #"{"start":{"year":2025,"month":10,"day":1},"end":{"year":2025,"month":10,"day":1}}"#
        )
        #expect(activity.startComponents["day"] == 1)

        let notification = try HanlinScriptingNotificationPayloadDecoder.decode(
            operation: "notification.schedule",
            json: #"""
            {
              "title":"Meal reminder",
              "interruptionLevel":"timeSensitive",
              "trigger":{
                "type":"calendar",
                "dateMatching":{"hour":12,"minute":30,"timeZone":"Asia/Jerusalem"},
                "repeats":true
              }
            }
            """#
        )
        #expect(notification.action == .schedule)
        #expect(notification.interruptionLevel == "timeSensitive")
        guard case let .calendar(components, timeZone, repeats) = notification.trigger else {
            Issue.record("Expected a calendar notification trigger")
            return
        }
        #expect(components == ["hour": 12, "minute": 30])
        #expect(timeZone == "Asia/Jerusalem")
        #expect(repeats)

        #expect(throws: (any Error).self) {
            try HanlinScriptingHealthPayloadDecoder.decodeStatistics(
                #"{"quantityType":"stepCount","startDate":0,"endDate":9999999999999,"statisticsOptions":["cumulativeSum"]}"#
            )
        }
        #expect(throws: (any Error).self) {
            try HanlinScriptingNotificationPayloadDecoder.decode(
                operation: "notification.schedule",
                json: #"{"title":"Invalid","trigger":{"type":"timeInterval","timeInterval":30,"repeats":true}}"#
            )
        }
    }

    @MainActor
    @Test("Runs smart-eating Health statistics and recurring Notification primitives end to end")
    func healthAndNotificationRuntime() async throws {
        let packageID = try HanlinInstalledPackageID(validating: "health-notification-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"""
            Navigation.present({ element: createElement(Text, null, "Waiting") });
            const components = new DateComponents({ hour: 8, minute: 15 });
            Promise.all([
              Health.queryStatistics("stepCount", {
                startDate: new Date("2025-10-01T00:00:00Z"),
                endDate: new Date("2025-10-01T23:59:59Z"),
                statisticsOptions: ["cumulativeSum"]
              }),
              Notification.schedule({
                title: "Breakfast",
                trigger: new CalendarNotificationTrigger({ dateMatching: components, repeats: true }),
                interruptionLevel: "timeSensitive"
              }),
              Health.queryActivitySummaries({
                start: DateComponents.fromDate(new Date("2025-10-01T12:00:00Z")),
                end: DateComponents.fromDate(new Date("2025-10-01T12:00:00Z"))
              }),
              Health.queryWorkouts({
                startDate: new Date("2025-10-01T00:00:00Z"),
                endDate: new Date("2025-10-01T23:59:59Z"),
                sortDescriptors: [{ key: "startDate", order: "reverse" }]
              })
            ]).then(([stats, scheduled, activity, workouts]) => Navigation.present({ element: createElement(
              Text, null, JSON.stringify([
                stats.sumQuantity(HealthUnit.count()), scheduled,
                activity[0].appleExerciseTime(HealthUnit.minute()), workouts[0].duration,
                workouts[0].allStatistics.activeEnergyBurned.sumQuantity(HealthUnit.kilocalorie())
              ])
            ) })).catch(error => Navigation.present({ element: createElement(
              Text, null, `ERROR:${error?.name}:${error?.message}`
            ) }));
            """#,
            filename: "compiled/index.js",
            storageAllowed: false,
            healthAllowed: true,
            healthDataAvailable: true,
            healthStatisticsLoader: { request in
                #expect(request.metric == .stepCount)
                #expect(request.options == [.cumulativeSum])
                return .init(
                    metric: request.metric,
                    unit: "count",
                    startDate: request.startDate,
                    endDate: request.endDate,
                    sum: 8_432
                )
            },
            healthActivitySummariesLoader: { request in
                #expect(request.startComponents["year"] == 2025)
                return [.init(
                    dateComponents: ["year": 2025, "month": 10, "day": 1],
                    activityMoveMode: 1,
                    activeEnergyBurned: 510,
                    activeEnergyBurnedGoal: 600,
                    appleMoveTime: 0,
                    appleMoveTimeGoal: 0,
                    appleExerciseTime: 34,
                    appleExerciseTimeGoal: 30,
                    appleStandHours: 9,
                    appleStandHoursGoal: 12
                )]
            },
            healthWorkoutsLoader: { request in
                #expect(request.reversed)
                return [.init(
                    uuid: "workout-1",
                    workoutActivityType: 37,
                    startDate: request.startDate,
                    endDate: request.startDate.addingTimeInterval(1_800),
                    duration: 1_800,
                    statistics: [
                        .activeEnergyBurned: .init(
                            metric: .activeEnergyBurned,
                            unit: "kcal",
                            startDate: request.startDate,
                            endDate: request.startDate.addingTimeInterval(1_800),
                            sum: 240
                        )
                    ]
                )]
            },
            notificationsAllowed: true,
            notificationLoader: { request in
                #expect(request.action == .schedule)
                guard case let .calendar(components, _, repeats) = request.trigger else {
                    Issue.record("Expected the serialized calendar trigger")
                    return false
                }
                #expect(components == ["hour": 8, "minute": 15])
                #expect(repeats)
                return true
            }
        )
        defer { session.dispose() }

        let expected = "[8432,true,34,1800,240]"
        await session.waitForNativeQuiescence()
        #expect(session.model.root.properties["text"] == .string(expected))
    }
}

@MainActor
private final class HanlinSystemOperationRecorder {
    var operations: [String] = []
}
