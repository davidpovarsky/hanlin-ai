import Foundation
import HanlinPlatformContracts
import SwiftData
import Testing
@testable import AI_Hanlin

/// Exercises the app's original message storage, request selection and canonical
/// dispatch boundaries. Recording executors deliberately avoid network providers;
/// installed NativeScript/Expo execution has its own runtime acceptance suite.
@MainActor
@Suite("Per-message composer capabilities through the app", .serialized)
struct HanlinComposerCapabilityIntegrationTests {
    @Test
    func sentSDKRequestAndPersistedMessageKeepIndependentCapabilitySnapshots() throws {
        let descriptor = HanlinComposerCapabilityDescriptor(
            reference: .init(kind: .miniApp, sourceID: "installed-fixture",
                             capabilityID: "search", revision: "generation-7"),
            title: "Text search", actions: [.init(id: "search", title: "Search")],
            configuration: .init(panels: [
                .init(id: "catalog", title: "Catalog", fields: [
                    .init(key: "collections", title: "Collections", kind: .catalog,
                          defaultValue: .array([.string("tanakh")]), options: [
                            .init(id: "tanakh", title: "Tanakh"),
                            .init(id: "talmud", title: "Talmud")
                          ])
                ])
            ]))
        var draft = [descriptor.makeAttachment(actionID: "search")]
        let sent = draft
        let request = HanlinConversationRequest(text: "Find this source", tools: false,
                                               capabilityAttachments: draft)
        var laterRequest = request
        let container = try ModelContainer(for: ChatRecords.self, ChatMessages.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let record = ChatRecords(name: "Composer snapshots", type: "chat")
        let user = ChatMessages(role: "user", text: request.text, record: record)
        user.capabilityAttachmentsData = try JSONEncoder().encode(request.capabilityAttachments)
        let originalBytes = user.capabilityAttachmentsData
        let oldUser = ChatMessages(role: "user", text: "Existing conversation", record: record)
        context.insert(record)
        context.insert(user)
        context.insert(oldUser)
        try context.save()

        draft[0].setValue(.array([.string("talmud")]), forKey: "collections")
        draft[0].reference.revision = "generation-8"
        laterRequest.capabilityAttachments[0].title = "A later draft"
        laterRequest.capabilityAttachments.removeAll()
        #expect(request.capabilityAttachments == sent)
        #expect(!request.tools, "Explicit attachments must not rewrite the SDK's general catalog preference")

        let verification = ModelContext(container)
        let userID = user.id
        let stored = try #require(verification.fetch(
            FetchDescriptor<ChatMessages>(predicate: #Predicate { $0.id == userID })).first)
        #expect(stored.capabilityAttachmentsData == originalBytes)
        #expect(try stored.decodedCapabilityAttachments() == sent)
        #expect(stored.capabilityAttachments == sent)
        var retrieved = stored.capabilityAttachments
        retrieved[0].setValue(.array([]), forKey: "collections")
        #expect(stored.capabilityAttachments == sent)

        let projected = HanlinComposerCapabilities.messageText(for: stored)
        #expect(projected.hasPrefix(request.text))
        #expect(projected.contains(sent[0].id.uuidString))
        #expect(projected.contains("generation-7") && !projected.contains("generation-8"))
        let selectionJSON = try #require(projected.components(separatedBy: "\n").last)
        let projectedSelections = try #require(
            JSONSerialization.jsonObject(with: Data(selectionJSON.utf8)) as? [[String: Any]])
        let projectedConfiguration = try #require(projectedSelections.first?["configuration"] as? [String: Any])
        #expect(projectedConfiguration["collections"] as? [String] == ["tanakh"],
                "Model history receives ordinary configuration JSON from the immutable sent snapshot")
        let oldID = oldUser.id
        let oldStored = try #require(verification.fetch(
            FetchDescriptor<ChatMessages>(predicate: #Predicate { $0.id == oldID })).first)
        #expect(oldStored.capabilityAttachmentsData == nil)
        #expect(try oldStored.decodedCapabilityAttachments().isEmpty)
        #expect(HanlinComposerCapabilities.messageText(for: oldStored) == "Existing conversation")

        let assistant = ChatMessages(role: "assistant", text: "Original response")
        assistant.capabilityAttachmentsData = originalBytes
        #expect(HanlinComposerCapabilities.messageText(for: assistant) == "Original response")
        let corrupt = ChatMessages(role: "user", text: "Keep readable text")
        corrupt.capabilityAttachmentsData = Data("[invalid".utf8)
        #expect(throws: DecodingError.self) { try corrupt.decodedCapabilityAttachments() }
        #expect(corrupt.capabilityAttachments.isEmpty)
        #expect(HanlinComposerCapabilities.messageText(for: corrupt) == "Keep readable text")
    }

    @Test
    func mcpAttachmentChangesOnlyThisRequestAndResolvesCurrentAliases() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "composer-mcp-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        let selections = MCPChatSelectionStore(fileLayout: layout)
        let chatID = UUID(), existingServer = UUID(), selectedServer = UUID()
        try await selections.setSelection([existingServer], chatID: chatID)
        try await selections.setSelection([], chatID: chatID, temporary: true)
        let storedSelection = try await selections.selection(chatID: chatID)
        let storedIDs = try #require(storedSelection)
        let beforeBytes = try Data(contentsOf: layout.chatSelections)
        let descriptor = HanlinComposerCapabilityDescriptor(
            reference: .init(kind: .mcp, sourceID: selectedServer.uuidString.lowercased(), capabilityID: "*"),
            title: "Selected server")
        let attachment = descriptor.makeAttachment()
        let original = AssistantToolRequestScope(chatID: chatID, mcpServerIDs: storedIDs,
                                                mcpGloballyEnabled: true)
        let scoped = try HanlinComposerCapabilities.scope(original, attachments: [attachment], catalog: [descriptor])
        #expect(scoped.mcpServerIDs == [existingServer, selectedServer])
        #expect(scoped.capabilityAttachments == [attachment])
        #expect(original.mcpServerIDs == [existingServer] && original.capabilityAttachments.isEmpty)
        #expect(try HanlinComposerCapabilities.scope(original, attachments: [], catalog: [descriptor]) == original)
        let temporary = AssistantToolRequestScope(chatID: chatID, mcpServerIDs: [],
                                                 mcpGloballyEnabled: true, isTemporaryChat: true)
        let temporaryScoped = try HanlinComposerCapabilities.scope(temporary, attachments: [attachment], catalog: [descriptor])
        #expect(temporaryScoped.isTemporaryChat && temporaryScoped.mcpServerIDs == [selectedServer])
        #expect(try await selections.selection(chatID: chatID, temporary: true) == [])
        #expect(throws: HanlinComposerCapabilityError.self) {
            try HanlinComposerCapabilities.scope(.nativeOnly, attachments: [attachment], catalog: [descriptor])
        }

        // The two servers deliberately export the same slug/name. Resolve the
        // selected server from the canonical route, never a guessed alias.
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [
            mcpTool(serverID: existingServer, name: "echo"),
            mcpTool(serverID: selectedServer, name: "echo"),
            mcpTool(serverID: selectedServer, name: "status")
        ])
        let selectedRoutes = authority.backendRoutes.filter {
            if case .mcp(let serverID, _) = $0.backend { return serverID == selectedServer }
            return false
        }
        let aliases = Set(selectedRoutes.map { $0.route.alias })
        #expect(aliases.count == 2)
        let echoAlias = try #require(selectedRoutes.first {
            if case .mcp(_, let name) = $0.backend { return name == "echo" }
            return false
        }?.route.alias)
        var calls: [(serverID: UUID, name: String, arguments: String)] = []
        let prepared = AssistantToolBridge.PreparedTools(authority: authority, executors: .init(
            executeNative: { _, _, _, _ in
                Issue.record("Selecting an MCP capability must not dispatch a native tool")
                return NativeToolResult(modelText: "Unexpected native execution", outcome: .failed)
            },
            executeMCP: { serverID, name, _, arguments in
                calls.append((serverID, name, arguments))
                return NativeToolResult(modelText: "MCP recording executor")
            },
            executeScripting: { _, _ in
                Issue.record("Selecting an MCP capability must not start a script")
                return NativeToolResult(modelText: "Unexpected script execution", outcome: .failed)
            }))
        let session = AssistantCapabilitySession(isTemporaryChat: true, capabilityAttachments: scoped.capabilityAttachments)
        try await session.prepareExplicitSelections(using: prepared, capabilityCatalog: [descriptor])
        #expect(calls.isEmpty)
        #expect(session.explicitlySelectedToolAliases == aliases)
        #expect(session.exposedToolAliases == aliases)
        let arguments = #"{ "value": "selected message" }"#
        let result = await prepared.execute(alias: echoAlias, argumentsJSON: arguments,
            context: .init(localeIdentifier: "en", capabilitySession: session))
        #expect(result?.modelText == "MCP recording executor")
        #expect(calls.count == 1)
        #expect(calls.first?.serverID == selectedServer && calls.first?.name == "echo")
        #expect(calls.first?.arguments == arguments)

        let unrelated = AssistantCapabilitySession(isTemporaryChat: true)
        try await unrelated.prepareExplicitSelections(using: prepared, capabilityCatalog: [descriptor])
        #expect(unrelated.explicitlySelectedToolAliases.isEmpty && unrelated.exposedToolAliases.isEmpty)
        #expect(unrelated.explicitSelectionInstruction == nil)
        #expect(try await selections.selection(chatID: chatID) == storedIDs)
        #expect(try Data(contentsOf: layout.chatSelections) == beforeBytes)
        #expect(try await selections.selection(chatID: chatID, temporary: true) == [])
    }

    @Test
    func nativeAndLegacySelectionsDispatchOriginalArgumentsWithIndependentConfiguration() async throws {
        let native = try nativeFixture()
        let catalog = NativeToolCatalog.shared
        let preferencesBefore = enabledPreferences(in: catalog)
        let revisionBefore = catalog.preferenceRevision
        let map = mapDescriptor()
        var selectedNative = native.descriptor.makeAttachment()
        selectedNative.setValue(.integer(2), forKey: "limit")
        var selectedMap = map.makeAttachment()
        selectedMap.setValue(location(latitude: 31.78, longitude: 35.23, radius: 1_200), forKey: "location")
        let sent = [selectedNative, selectedMap]
        let session = AssistantCapabilitySession(isTemporaryChat: true, capabilityAttachments: sent)
        selectedNative.setValue(.integer(9), forKey: "limit")
        selectedMap.setValue(location(latitude: 0, longitude: 0, radius: 50), forKey: "location")

        let names = HanlinComposerCapabilities.explicitNativeNames(in: sent)
        #expect(names == [native.entry.name])
        let requested = try NativeToolBridge.canonicalSourcesForRequest(explicitToolNames: names)
        #expect(requested.contains { $0.entry.name == native.entry.name })
        let legacy = HanlinComposerCapabilities.explicitLegacySources(in: sent)
        #expect(!LegacyToolCanonicalAdapter.sources(mapEnabled: false).contains {
            $0.toolName == "search_nearby_locations"
        })
        #expect(legacy.map(\.toolName) == ["search_nearby_locations"])
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [native.source],
            mcpTools: [], legacySources: legacy)
        let nativeAlias = try #require(authority.backendRoutes.first {
            if case .native(_, let name) = $0.backend { return name == native.entry.name }
            return false
        }?.route.alias)
        let mapAlias = try #require(authority.backendRoutes.first {
            if case .legacy(let name) = $0.backend { return name == "search_nearby_locations" }
            return false
        }?.route.alias)
        #expect(nativeAlias != native.entry.name, "This fixture must exercise canonical alias resolution")
        var nativeCalls: [(arguments: String, configuration: HanlinJSONValue?, sessionID: UUID?)] = []
        var legacyCalls: [(arguments: String, configuration: HanlinJSONValue?)] = []
        var resolvedRegions: [HanlinNearbySearchRegion] = []
        let prepared = AssistantToolBridge.PreparedTools(authority: authority, executors: .init(
            executeNative: { provider, name, arguments, context in
                #expect(provider.rawValue == native.descriptor.reference.sourceID)
                #expect(name == native.entry.name)
                nativeCalls.append((arguments, context.composerConfiguration, context.capabilitySession?.id))
                return NativeToolResult(modelText: "Native recording executor")
            },
            executeScripting: { _, _ in
                Issue.record("Selection/dispatch must not start an unrelated script or app entrypoint")
                return NativeToolResult(modelText: "Unexpected script execution", outcome: .failed)
            },
            executeLegacy: { name, arguments, context in
                #expect(name == "search_nearby_locations")
                legacyCalls.append((arguments, context.composerConfiguration))
                do {
                    resolvedRegions.append(try HanlinNearbySearchRegion.resolve(latitude: 0, longitude: 0,
                        configuration: context.composerConfiguration))
                } catch { Issue.record("Valid selected map configuration was rejected: \(error)") }
                return NativeToolResult(modelText: "Legacy recording executor")
            }), legacySources: legacy)
        try await session.prepareExplicitSelections(using: prepared, capabilityCatalog: [native.descriptor, map])
        #expect(nativeCalls.isEmpty && legacyCalls.isEmpty && resolvedRegions.isEmpty)
        #expect(session.explicitlySelectedToolAliases == [nativeAlias, mapAlias])
        #expect(session.composerConfiguration(for: nativeAlias) == sent[0].configuration)
        #expect(session.composerConfiguration(for: mapAlias) == sent[1].configuration)
        #expect(session.explicitSelectionInstruction?.contains(nativeAlias) == true)

        let nativeArguments = #"{ "query": "charity", "limit": 19 }"#
        let mapArguments = #"{ "coordinate": { "latitude": 0, "longitude": 0 }, "keyword": "cafes" }"#
        let nativeResult = await prepared.execute(alias: nativeAlias, argumentsJSON: nativeArguments,
            context: .init(localeIdentifier: "en", capabilitySession: session))
        let mapResult = await prepared.execute(alias: mapAlias, argumentsJSON: mapArguments,
            context: .init(localeIdentifier: "en", capabilitySession: session))
        #expect(nativeResult?.modelText == "Native recording executor")
        #expect(mapResult?.modelText == "Legacy recording executor")
        #expect(nativeResult?.diagnostics.modelFacingAlias == nativeAlias)
        #expect(mapResult?.diagnostics.backendRoute == "legacy:search_nearby_locations")
        #expect(nativeCalls.count == 1 && legacyCalls.count == 1)
        #expect(nativeCalls.first?.arguments == nativeArguments)
        #expect(nativeCalls.first?.configuration == sent[0].configuration)
        #expect(nativeCalls.first?.sessionID == session.id)
        #expect(legacyCalls.first?.arguments == mapArguments)
        #expect(legacyCalls.first?.configuration == sent[1].configuration)
        #expect(resolvedRegions == [.init(latitude: 31.78, longitude: 35.23, radiusMeters: 1_200)])

        // Reusing the authority in another run must not reuse configuration. A
        // caller-supplied context value cannot replace the selection snapshot.
        let unrelated = AssistantCapabilitySession(isTemporaryChat: true)
        try await unrelated.prepareExplicitSelections(using: prepared, capabilityCatalog: [native.descriptor, map])
        #expect(unrelated.explicitlySelectedToolAliases.isEmpty && unrelated.exposedToolAliases.isEmpty)
        _ = await prepared.execute(alias: nativeAlias, argumentsJSON: nativeArguments,
            context: .init(localeIdentifier: "en", capabilitySession: unrelated,
                           composerConfiguration: .object(["limit": .integer(99)])))
        #expect(nativeCalls.count == 2 && nativeCalls.last?.configuration == nil)
        #expect(nativeCalls.last?.sessionID == unrelated.id)

        let other = AssistantCapabilitySession(isTemporaryChat: true, capabilityAttachments: [selectedNative])
        try await other.prepareExplicitSelections(using: prepared, capabilityCatalog: [native.descriptor])
        _ = await prepared.execute(alias: nativeAlias, argumentsJSON: nativeArguments,
            context: .init(localeIdentifier: "en", capabilitySession: other))
        #expect(nativeCalls.count == 3 && nativeCalls.last?.configuration == selectedNative.configuration)
        #expect(session.composerConfiguration(for: nativeAlias) == sent[0].configuration)
        #expect(session.composerConfiguration(for: mapAlias) == sent[1].configuration)
        #expect(catalog.preferenceRevision == revisionBefore)
        #expect(enabledPreferences(in: catalog) == preferencesBefore)
        session.reset()
        #expect(session.composerConfiguration(for: nativeAlias) == nil)
        #expect(session.explicitSelectionInstruction == nil && session.explicitlySelectedToolAliases.isEmpty)
    }

    @Test
    func explicitNativeRequestAdmitsADisabledToolWithoutEnablingItsPreferences() async throws {
        let suiteName = "hanlin-composer-disabled-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let catalog = NativeToolCatalog(defaults: defaults, automaticallyRegistersBuiltins: false,
                                        trace: { _, _ in })
        var executionCount = 0
        let tool = DisabledCalculatorFixture(onExecute: { executionCount += 1 })
        #expect(catalog.register(tool))
        let entry = try #require(catalog.entry(named: tool.name))
        let provider = try NativeToolCanonicalShadowAdapter.providerInstanceID(for: entry)
        let preferencesBefore = defaults.persistentDomain(forName: suiteName) ?? [:]
        let revisionBefore = catalog.preferenceRevision
        #expect(!catalog.isEnabled(entry) && !catalog.isEffectivelyEnabled(entry))
        #expect(try NativeToolBridge.canonicalSourcesForRequest(catalog: catalog).isEmpty)

        let selectedSources = try NativeToolBridge.canonicalSourcesForRequest(
            explicitToolNames: [tool.name], catalog: catalog)
        #expect(selectedSources.map { $0.entry.name } == [tool.name])
        #expect(executionCount == 0, "Admitting a selected schema must not run its executor")
        let arguments = #"{"expression":"6 * 7"}"#
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let unselected = await NativeToolBridge.executeCanonical(providerInstanceID: provider,
            toolName: tool.name, argumentsJSON: arguments, context: context, catalog: catalog)
        #expect(unselected.outcome == .rejectedByAvailability && executionCount == 0)
        let selected = await NativeToolBridge.executeCanonical(providerInstanceID: provider,
            toolName: tool.name, argumentsJSON: arguments, context: context,
            explicitlySelected: true, catalog: catalog)
        #expect(selected.outcome == .succeeded && selected.userText == "42" && executionCount == 1)
        let nextUnselected = await NativeToolBridge.executeCanonical(providerInstanceID: provider,
            toolName: tool.name, argumentsJSON: arguments, context: context, catalog: catalog)
        #expect(nextUnselected.outcome == .rejectedByAvailability && executionCount == 1)
        #expect(try NativeToolBridge.canonicalSourcesForRequest(catalog: catalog).isEmpty)
        #expect(!catalog.isEnabled(entry) && !catalog.isEffectivelyEnabled(entry))
        #expect(catalog.preferenceRevision == revisionBefore)
        #expect(NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:])
            .isEqual(to: preferencesBefore))
    }

    @Test
    func overlappingNativeAndMiniAppSelectionsRejectDifferentConfigurationsAtomically() async throws {
        let native = try nativeFixture()
        let sourceAppID = try #require(native.entry.sourceAppID)
        let group = HanlinComposerCapabilityDescriptor(
            reference: .init(kind: .miniApp, sourceID: sourceAppID, capabilityID: "assistantTools"),
            title: "Sefaria MiniApp",
            actions: [.init(id: native.entry.name, title: native.entry.title)],
            configuration: native.descriptor.configuration)
        var direct = native.descriptor.makeAttachment()
        direct.setValue(.integer(2), forKey: "limit")
        var grouped = group.makeAttachment(actionID: native.entry.name)
        grouped.setValue(.integer(3), forKey: "limit")
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [native.source], mcpTools: [])
        let alias = try #require(authority.backendRoutes.first?.route.alias)
        var calls = 0
        let prepared = AssistantToolBridge.PreparedTools(authority: authority, executors: .init(
            executeNative: { _, _, _, _ in
                calls += 1
                return NativeToolResult(modelText: "Unexpected execution", outcome: .failed)
            }, executeScripting: { _, _ in
                calls += 1
                return NativeToolResult(modelText: "Unexpected execution", outcome: .failed)
            }))
        let conflicted = AssistantCapabilitySession(isTemporaryChat: true, capabilityAttachments: [direct, grouped])
        await #expect(throws: HanlinComposerCapabilityError.self) {
            try await conflicted.prepareExplicitSelections(using: prepared, capabilityCatalog: [native.descriptor, group])
        }
        #expect(calls == 0)
        #expect(conflicted.explicitlySelectedToolAliases.isEmpty && conflicted.exposedToolAliases.isEmpty)
        #expect(conflicted.explicitSelectionInstruction == nil && conflicted.composerConfiguration(for: alias) == nil)

        grouped.configuration = direct.configuration
        let compatible = AssistantCapabilitySession(isTemporaryChat: true, capabilityAttachments: [direct, grouped])
        try await compatible.prepareExplicitSelections(using: prepared, capabilityCatalog: [native.descriptor, group])
        #expect(compatible.explicitlySelectedToolAliases == [alias])
        #expect(compatible.composerConfiguration(for: alias) == direct.configuration)
        #expect(calls == 0)
    }

    @Test
    func selectedMapRegionOverridesModelCoordinatesAndNeverBecomesADefault() throws {
        let configuration: HanlinJSONValue = .object([
            "location": location(latitude: 31.78, longitude: 35.23, radius: 750)
        ])
        #expect(try HanlinNearbySearchRegion.resolve(latitude: 40.7, longitude: -74,
            configuration: configuration) == .init(latitude: 31.78, longitude: 35.23, radiusMeters: 750))
        for invalidRadius in [0.0, -1.0, .infinity] {
            #expect(throws: HanlinComposerCapabilityError.self) {
                try HanlinNearbySearchRegion.resolve(latitude: 40.7, longitude: -74,
                    configuration: .object([
                        "location": location(latitude: 31.78, longitude: 35.23, radius: invalidRadius)
                    ]))
            }
        }
        #expect(try HanlinNearbySearchRegion.resolve(latitude: 40.7, longitude: -74,
            configuration: nil) == .init(latitude: 40.7, longitude: -74, radiusMeters: 5_000))
        #expect(try HanlinNearbySearchRegion.resolve(latitude: 51.5, longitude: -0.12,
            configuration: .object([:])) == .init(latitude: 51.5, longitude: -0.12, radiusMeters: 5_000))
    }

    private func nativeFixture() throws -> (
        entry: NativeToolCatalogEntry,
        descriptor: HanlinComposerCapabilityDescriptor,
        source: HanlinCanonicalToolAuthority.NativeSource
    ) {
        let catalog = NativeToolCatalog.shared
        let entry = try #require(catalog.entry(named: "sefaria_search"))
        let tool = try #require(catalog.tool(named: entry.name, enabledOnly: false))
        let provider = try NativeToolCanonicalShadowAdapter.providerInstanceID(for: entry)
        let configuration = try #require(entry.composerConfiguration)
        let descriptor = HanlinComposerCapabilityDescriptor(
            reference: .init(kind: .tool, sourceID: provider.rawValue, capabilityID: entry.name),
            title: entry.title, summary: entry.summary, configuration: configuration)
        let source = HanlinCanonicalToolAuthority.NativeSource(entry: entry,
            canonicalSchema: tool.openAIToolSchema(), modelSchema: tool.openAIToolSchema(),
            preferredAlias: "attached_sefaria_search")
        return (entry, descriptor, source)
    }

    private func mapDescriptor() -> HanlinComposerCapabilityDescriptor {
        .init(reference: .init(kind: .tool, sourceID: LegacyToolCanonicalAdapter.providerInstanceIDString,
                              capabilityID: "search_nearby_locations"),
              title: "Nearby places", configuration: .init(panels: [
                .init(id: "region", title: "Search area", fields: [
                    .init(key: "location", title: "Search area", kind: .location, required: true)
                ])
              ]))
    }

    private func location(latitude: Double, longitude: Double, radius: Double) -> HanlinJSONValue {
        .object(["latitude": .number(latitude), "longitude": .number(longitude), "radiusMeters": .number(radius)])
    }

    private func enabledPreferences(in catalog: NativeToolCatalog) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: catalog.allEntries().map { ($0.name, catalog.isEffectivelyEnabled($0)) })
    }

    private func mcpTool(serverID: UUID, name: String) -> MCPToolDescriptor {
        .init(serverID: serverID, serverSlug: "composer_fixture", serverDisplayName: "Composer fixture",
              originalName: name, exposedName: "mcp__composer_fixture__" + name,
              title: name, summary: "Records canonical request routing",
              inputSchemaJSON: Data(#"{"type":"object","properties":{"value":{"type":"string"}}}"#.utf8))
    }

    @MainActor
    private struct DisabledCalculatorFixture: NativeTool {
        let onExecute: @MainActor () -> Void
        private let calculator = QuickCalculateTool()
        init(onExecute: @escaping @MainActor () -> Void) { self.onExecute = onExecute }
        var name: String { calculator.name }
        var catalogEntry: NativeToolCatalogEntry {
            var entry = calculator.catalogEntry
            entry.isEnabledByDefault = false
            return entry
        }
        func openAIToolSchema() -> [String: Any] { calculator.openAIToolSchema() }
        func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
            onExecute()
            return await calculator.execute(argumentsJSON: argumentsJSON, context: context)
        }
    }
}
