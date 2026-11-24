import Foundation
import HanlinMiniAppCore
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing
@testable import AI_Hanlin

@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    @Test func actualNativeScriptAssistantUsesDedicatedSourceAndImmutableConfiguration() async throws {
        try await exerciseActualAssistant(engine: "nativescript")
    }

    @Test func actualExpoAssistantUsesDedicatedSourceAndImmutableConfiguration() async throws {
        try await exerciseActualAssistant(engine: "expo")
    }

    /// Uses the installed original authoring toolchain, real package import/store,
    /// production request-local NativeTool and the original native engine. No
    /// mocked executor, network, foreground launch or separate JavaScript engine.
    private func exerciseActualAssistant(engine: String) async throws {
        let suffix = UUID().uuidString.lowercased()
        let appID = "hanlin.assistant-\(engine)-\(suffix)"
        let directory = FileManager.default.temporaryDirectory.appending(path: appID)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nativeScript = engine == "nativescript"
        let appEntry = nativeScript ? "nativescript/app/bundle.mjs" : "bundle.js"
        let toolEntry = nativeScript ? "assistant/echo/bundle.mjs" : "assistant/echo/bundle.js"
        let inputSchema: [String: Any] = [
            "type": "object", "properties": ["query": ["type": "string"]],
            "required": ["query"], "additionalProperties": false
        ]
        let manifest: [String: Any] = [
            "name": "Assistant \(engine) \(suffix)", "version": "1.0.0", "hanlinAppID": appID,
            "entry": appEntry, "runInApp": true, "hanlinRuntime": nativeScript ? "hanlin-nativescript" : "hanlin-expo",
            "entrypoints": [
                ["id": "echo-tool", "kind": "assistantTool", "sourcePath": toolEntry, "assistantTool": [
                    "title": "Echo", "summary": "Echo dedicated arguments and user configuration",
                    "actions": [
                        ["id": "echo", "title": "Echo", "summary": "Echo arguments", "inputSchema": inputSchema,
                         "embeddedResultID": "echo-result"],
                        ["id": "hold", "title": "Wait", "summary": "Wait for cancellation", "inputSchema": inputSchema]
                    ],
                    "configuration": ["panels": [
                        ["id": "scope", "title": "Scope", "fields": [
                            ["key": "scope", "title": "Scope", "kind": "text", "required": true, "defaultValue": "user-picked"]
                        ]]
                    ]]
                ]],
                ["id": "echo-result", "kind": "embeddedResult", "sourcePath": appEntry]
            ]
        ]
        let index: String
        let transportImport: String
        let markStarted: String
        if nativeScript {
            index = """
                import { Application, Label } from "@nativescript/core";
                (globalThis as unknown as { assistantAppSourceLoads: number }).assistantAppSourceLoads = 1;
                Application.run({create: () => { const label = new Label(); label.text = "Assistant result"; return label; }});
                """
            transportImport = #"import { File } from "@nativescript/core";"#
            markStarted = """
                const bridge = (globalThis as unknown as {
                  HanlinNativeServicesBridge: {activeSessionBridge(): {stateDirectory(): string}}
                }).HanlinNativeServicesBridge.activeSessionBridge();
                File.fromPath(bridge.stateDirectory() + "/assistant-hold").writeTextSync("ready");
                """
        } else {
            index = """
                import React from "react";
                import { AppRegistry, Text } from "react-native";
                (globalThis as unknown as { assistantAppSourceLoads: number }).assistantAppSourceLoads = 1;
                function Result() { return React.createElement(Text, null, "Assistant result"); }
                AppRegistry.registerComponent("main", () => Result);
                """
            transportImport = #"import { hostServices } from "@hanlin/expo-ui";"#
            markStarted = #"await hostServices.writeFile("assistant-hold", new Uint8Array([1]), "state");"#
        }
        let toolSource = """
            \(transportImport)
            type Context = { configuration: {scope: string}; actionID: string; caller: string };
            export function echo(args: {query: string}, context: Context) {
              return {query: args.query, configuration: context.configuration, actionID: context.actionID,
                caller: context.caller,
                appSourceLoads: (globalThis as unknown as {assistantAppSourceLoads?: number}).assistantAppSourceLoads ?? 0};
            }
            export async function hold(_args: {query: string}, _context: Context): Promise<never> {
              \(markStarted)
              return new Promise<never>(() => {});
            }
            """
        let authoring: [String: Any] = [
            "schemaVersion": 1, "engine": engine, "entry": "index.ts",
            "tsconfig": "tsconfig.json", "assistantTools": ["echo-tool": "echo.ts"]
        ]
        var compiler: [String: Any] = ["strict": true, "skipLibCheck": false]
        if !nativeScript { compiler["lib"] = ["ES2023"] }
        var tsconfig: [String: Any] = ["compilerOptions": compiler, "include": ["*.ts"]]
        if !nativeScript { tsconfig["extends"] = "expo/tsconfig.base" }
        let files: [[String: String]] = [
            ["path": "script.json", "content": try fixtureJSON(manifest)],
            ["path": "package.json", "content": try fixtureJSON([
                "name": appID, "version": "1.0.0", "private": true, "type": "module"])],
            ["path": "tsconfig.json", "content": try fixtureJSON(tsconfig)],
            ["path": "hanlin.authoring.json", "content": try fixtureJSON(authoring)],
            ["path": "index.ts", "content": index], ["path": "echo.ts", "content": toolSource]
        ]
        let written = await MiniAppAuthoringTool(operation: .write).execute(
            argumentsJSON: try fixtureJSON(["project_path": directory.path, "files": files]),
            context: .init(localeIdentifier: "en"))
        try #require(written.outcome == .succeeded, Comment(rawValue: written.modelText))
        let built = await MiniAppAuthoringTool(operation: .build).execute(
            argumentsJSON: try fixtureJSON(["engine": engine, "project_path": directory.path]),
            context: .init(localeIdentifier: "en"))
        try #require(built.outcome == .succeeded, Comment(rawValue: built.modelText))
        let report = try JSONDecoder().decode(HanlinMiniAppAuthoringReport.self, from: Data(built.modelText.utf8))
        let archive = URL(fileURLWithPath: try #require(report.archivePath))
        let platform = HanlinScriptingPlatform.shared
        await platform.importPackage(from: archive)
        let preview = try #require(platform.preview)
        try #require(preview.canInstall, Comment(rawValue: String(describing: preview.findings)))
        await platform.installPreview()
        let installed = try #require(platform.installedPackages.first { $0.appID.rawValue == appID })
        do {
            let originalForeground = platform.activeApplicationID
            let originalSession = HanlinNativeScriptSession.activeSessionIdentifier
            let descriptor = try #require(HanlinMiniAppAssistantToolExports.descriptors().first {
                $0.reference.sourceID == installed.record.installedPackageID.rawValue
            })
            var attachment = descriptor.makeAttachment(actionID: "echo")
            attachment.configuration = .object(["scope": .string("catalog-" + suffix)])
            let tool = try #require(HanlinMiniAppAssistantToolExports.tools(attachments: [attachment]).first)
            #expect(platform.activeApplicationID == originalForeground)
            #expect(HanlinNativeScriptSession.activeSessionIdentifier == originalSession)
            let arguments = #"{"query":"שלום from model"}"#
            let context = NativeToolExecutionContext(localeIdentifier: "en", toolCallID: suffix,
                chatID: "assistant-test-" + suffix, requestID: "request-" + suffix)
            let result = await assistantFixtureExecute(tool, arguments: arguments, context: context)
            try #require(result.outcome == .succeeded, Comment(rawValue: result.modelText))
            guard case let .object(value) = try HanlinJSONValue.decodeCanonicalJSON(Data(result.modelText.utf8)) else {
                Issue.record("Actual assistant did not return its JSON result")
                await platform.uninstall(installed.record.installedPackageID)
                return
            }
            #expect(value["query"] == .string("שלום from model"))
            #expect(value["configuration"] == attachment.configuration)
            #expect(value["actionID"] == .string("echo"))
            #expect(value["caller"] == .string("hanlin.host"))
            #expect(value["appSourceLoads"] == .integer(0))
            #expect(tool.catalogEntry.presentationProfile.canonicalEmbeddedPresentation?.handler == "echo-result")
            let rich = try #require(result.embeddedPayload)
            #expect(rich.ownerID == installed.record.packageID.rawValue)
            #expect(rich.metadata?["installedPackageID"] == installed.record.installedPackageID.rawValue)
            #expect(rich.metadata?["generation"] == String(installed.record.activeGeneration))
            #expect(try rich.payload?.jsonValue() == .object(value))
            var staleMetadata = rich.metadata ?? [:]
            staleMetadata["generation"] = "0"
            let stale = HanlinEmbeddedResultPayload(
                payload: rich.payload, resultReference: rich.resultReference, title: rich.title,
                metadata: staleMetadata, ownerID: rich.ownerID, actions: rich.actions)
            if nativeScript {
                #expect(NativeScriptEmbeddedResultAdapter.resolve(packageID: installed.record.packageID,
                    handler: "echo-result", payload: stale) == nil)
            } else {
                #expect(ExpoEmbeddedResultAdapter.resolve(packageID: installed.record.packageID,
                    handler: "echo-result", payload: stale) == nil)
            }

            var holdAttachment = attachment
            holdAttachment.actionID = "hold"
            let hold = try #require(HanlinMiniAppAssistantToolExports.tools(attachments: [holdAttachment]).first)
            let dataStore = try HanlinMiniAppDataStore(root: HanlinMiniAppDataStore.applicationSupportRoot())
            let running = Task { @MainActor in await hold.execute(argumentsJSON: arguments, context: context) }
            do {
                let deadline = ContinuousClock.now + .seconds(45)
                while try await dataStore.read(appID: installed.appID, area: .state, path: "assistant-hold") == nil {
                    try #require(ContinuousClock.now < deadline, "Actual assistant handler did not acknowledge invocation")
                    try await Task.sleep(for: .milliseconds(25))
                }
                running.cancel()
                let cancelled = await running.value
                #expect(cancelled.outcome == .cancelled)
            } catch {
                running.cancel()
                _ = await running.value
                throw error
            }
            let afterCancellation = await assistantFixtureExecute(tool, arguments: arguments, context: context)
            #expect(afterCancellation.outcome == .succeeded, Comment(rawValue: afterCancellation.modelText))
            #expect(platform.activeApplicationID == originalForeground)
            #expect(HanlinNativeScriptSession.activeSessionIdentifier == originalSession)

            await platform.setEnabled(false, for: installed.record.installedPackageID)
            #expect(HanlinMiniAppAssistantToolExports.tools(attachments: [attachment]).isEmpty)
            let staleCall = await tool.execute(argumentsJSON: arguments, context: context)
            #expect(staleCall.outcome == .rejectedByAvailability)
            await platform.uninstall(installed.record.installedPackageID)
        } catch {
            await platform.uninstall(installed.record.installedPackageID)
            throw error
        }
    }

    private func fixtureJSON(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    private func assistantFixtureExecute(
        _ tool: NativeTool, arguments: String, context: NativeToolExecutionContext
    ) async -> NativeToolResult {
        let invocation = Task { @MainActor in await tool.execute(argumentsJSON: arguments, context: context) }
        let deadline = Task {
            try await Task.sleep(for: .seconds(90))
            invocation.cancel()
        }
        defer { deadline.cancel() }
        return await invocation.value
    }
}
