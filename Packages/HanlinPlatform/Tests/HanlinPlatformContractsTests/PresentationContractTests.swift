import Foundation
import Testing
@testable import HanlinPlatformContracts

// MARK: - Presentation Contracts Codec Tests

@Test
func embeddedPresentationDescriptorRoundTrips() throws {
    let descriptor = HanlinEmbeddedPresentationDescriptor(
        handler: "sefaria.source-card",
        sizing: HanlinEmbeddedSizingPreference(
            preset: .regular,
            preferredWidth: 320,
            preferredHeight: 200
        ),
        expansion: HanlinExpansionDescriptor(
            supportedModes: [.sheet, .fullScreen],
            expandedHandler: "sefaria.full-reader"
        )
    )

    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(
        HanlinEmbeddedPresentationDescriptor.self,
        from: data
    )
    #expect(decoded == descriptor)
    #expect(decoded.handler == "sefaria.source-card")
    #expect(decoded.sizing.preset == .regular)
    #expect(decoded.sizing.preferredWidth == 320)
    #expect(decoded.sizing.preferredHeight == 200)
    #expect(decoded.expansion?.supportedModes == [.sheet, .fullScreen])
    #expect(decoded.expansion?.expandedHandler == "sefaria.full-reader")
}

@Test
func embeddedPresentationDefaultsAreMinimal() throws {
    let descriptor = HanlinEmbeddedPresentationDescriptor()
    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(
        HanlinEmbeddedPresentationDescriptor.self,
        from: data
    )
    #expect(decoded.handler == nil)
    #expect(decoded.sizing.preset == .automatic)
    #expect(decoded.sizing.preferredWidth == nil)
    #expect(decoded.sizing.preferredHeight == nil)
    #expect(decoded.expansion == nil)
}

@Test
func toolExecutionPresentationRoundTrips() throws {
    let descriptor = HanlinToolExecutionPresentationDescriptor(
        familyID: .webSearch,
        customHandler: nil
    )
    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(
        HanlinToolExecutionPresentationDescriptor.self,
        from: data
    )
    #expect(decoded == descriptor)
    #expect(decoded.familyID == .webSearch)
    #expect(decoded.customHandler == nil)
}

@Test
func executionPresentationFamilyIDIsExtensible() throws {
    // Known system families should round-trip
    let knownFamilies: [HanlinExecutionPresentationFamilyID] = [
        .generic, .webSearch, .sourceSearch, .map, .command,
        .fileOperation, .codeExecution, .imageGeneration, .custom
    ]

    for family in knownFamilies {
        let descriptor = HanlinToolExecutionPresentationDescriptor(familyID: family)
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(
            HanlinToolExecutionPresentationDescriptor.self,
            from: data
        )
        #expect(decoded.familyID == family)
    }

    // Unknown future family IDs should also round-trip without error
    let futureFamily: HanlinExecutionPresentationFamilyID = "quantum-search"
    let descriptor = HanlinToolExecutionPresentationDescriptor(familyID: futureFamily)
    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(
        HanlinToolExecutionPresentationDescriptor.self,
        from: data
    )
    #expect(decoded.familyID?.rawValue == "quantum-search")
}

@Test
func embeddedSizePresetsAllRoundTrip() throws {
    for preset in HanlinEmbeddedSizePreset.allCases {
        let pref = HanlinEmbeddedSizingPreference(preset: preset)
        let data = try JSONEncoder().encode(pref)
        let decoded = try JSONDecoder().decode(
            HanlinEmbeddedSizingPreference.self,
            from: data
        )
        #expect(decoded.preset == preset)
    }
}

@Test
func expansionMoDesAllRoundTrip() throws {
    for mode in HanlinExpansionMode.allCases {
        let desc = HanlinExpansionDescriptor(supportedModes: [mode])
        let data = try JSONEncoder().encode(desc)
        let decoded = try JSONDecoder().decode(
            HanlinExpansionDescriptor.self,
            from: data
        )
        #expect(decoded.supportedModes == [mode])
    }
}

@Test
func expansionModeBridgesToPresentationIntent() {
    #expect(HanlinExpansionMode.sheet.presentationIntent == .largeSheet)
    #expect(HanlinExpansionMode.fullScreen.presentationIntent == .fullScreen)
    #expect(HanlinExpansionMode.window.presentationIntent == .newWindow)

    #expect(HanlinExpansionMode(presentationIntent: .largeSheet) == .sheet)
    #expect(HanlinExpansionMode(presentationIntent: .fullScreen) == .fullScreen)
    #expect(HanlinExpansionMode(presentationIntent: .newWindow) == .window)
}

// MARK: - Entry Point Kind Tests

@Test
func embeddedResultEntryPointKindExists() throws {
    let kind = HanlinEntryPointKind.embeddedResult
    #expect(kind.rawValue == "embeddedResult")

    // Verify it round-trips through JSON
    let data = try JSONEncoder().encode(kind)
    let decoded = try JSONDecoder().decode(
        HanlinEntryPointKind.self,
        from: data
    )
    #expect(decoded == .embeddedResult)
}

@Test
func entryPointDescriptorWithEmbeddedResultRoundTrips() throws {
    let descriptor = HanlinEntryPointDescriptor(
        kind: .embeddedResult,
        handler: "sefaria.chat-presentation",
        allowedContexts: [.mainApplication]
    )
    let data = try JSONEncoder().encode(descriptor)
    let decoded = try JSONDecoder().decode(
        HanlinEntryPointDescriptor.self,
        from: data
    )
    #expect(decoded == descriptor)
    #expect(decoded.kind == .embeddedResult)
}

// MARK: - Tool Presentation with Execution + Embedded

@Test
func toolPresentationWithExecutionAndEmbeddedRoundTrips() throws {
    let presentation = HanlinToolPresentationDescriptor(
        compactStyle: .search,
        supportsExpandedPresentation: true,
        executionPresentation: HanlinToolExecutionPresentationDescriptor(
            familyID: .sourceSearch
        ),
        embeddedPresentation: HanlinEmbeddedPresentationDescriptor(
            handler: "sefaria.results",
            sizing: HanlinEmbeddedSizingPreference(preset: .large),
            expansion: HanlinExpansionDescriptor(
                supportedModes: [.sheet],
                expandedHandler: "sefaria.full-results"
            )
        )
    )
    let data = try JSONEncoder().encode(presentation)
    let decoded = try JSONDecoder().decode(
        HanlinToolPresentationDescriptor.self,
        from: data
    )
    #expect(decoded == presentation)
    #expect(decoded.executionPresentation?.familyID == .sourceSearch)
    #expect(decoded.embeddedPresentation?.handler == "sefaria.results")
    #expect(decoded.embeddedPresentation?.sizing.preset == .large)
    #expect(decoded.embeddedPresentation?.expansion?.supportedModes == [.sheet])
}

@Test
func toolPresentationBackwardCompatibleWhenNewFieldsAbsent() throws {
    // A tool presentation JSON without executionPresentation or embeddedPresentation
    // should decode cleanly with those fields as nil when supportsExpandedPresentation is false.
    let json = """
    {"compactStyle":"automatic","supportsExpandedPresentation":false}
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        HanlinToolPresentationDescriptor.self,
        from: json
    )
    #expect(decoded.compactStyle == .automatic)
    #expect(decoded.supportsExpandedPresentation == false)
    #expect(decoded.executionPresentation == nil)
    #expect(decoded.embeddedPresentation == nil)
}

@Test
func toolPresentationMigratesLegacyExpandedPayloadToCanonicalDescriptor() throws {
    // A legacy tool presentation JSON with supportsExpandedPresentation: true
    // must construct a canonical embeddedPresentation with expansion mode [.sheet].
    let json = """
    {"compactStyle":"search","supportsExpandedPresentation":true}
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        HanlinToolPresentationDescriptor.self,
        from: json
    )
    #expect(decoded.compactStyle == .search)
    #expect(decoded.supportsExpandedPresentation == true)
    #expect(decoded.embeddedPresentation != nil)
    #expect(decoded.embeddedPresentation?.expansion?.supportedModes == [.sheet])
    #expect(decoded.embeddedPresentation?.sizing.preset == .large)

    // Re-encoding must emit both legacy supportsExpandedPresentation and canonical embeddedPresentation
    let reencoded = try JSONEncoder().encode(decoded)
    let redecoded = try JSONDecoder().decode(
        HanlinToolPresentationDescriptor.self,
        from: reencoded
    )
    #expect(redecoded.supportsExpandedPresentation == true)
    #expect(redecoded.embeddedPresentation?.expansion != nil)
}

@Test
func toolPresentationCanonicalEmbeddedIsAuthoritativeOverLegacyFlag() throws {
    // When embeddedPresentation is present without expansion,
    // supportsExpandedPresentation MUST be false even if legacy flag was true.
    let json = """
    {
        "compactStyle": "text",
        "supportsExpandedPresentation": true,
        "embeddedPresentation": {
            "sizing": {"preset": "compact"}
        }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(
        HanlinToolPresentationDescriptor.self,
        from: json
    )
    #expect(decoded.compactStyle == .text)
    #expect(decoded.supportsExpandedPresentation == false)
    #expect(decoded.embeddedPresentation?.expansion == nil)
}

// MARK: - App Descriptor with Embedded Result Entry Point

@Test
func appDescriptorWithEmbeddedResultEntryPointRoundTrips() throws {
    let descriptor = try ContractFixtures.descriptor(
        entryPoints: [
            HanlinEntryPointDescriptor(
                kind: .app,
                handler: "src/index.tsx",
                allowedContexts: [.mainApplication]
            ),
            HanlinEntryPointDescriptor(
                kind: .embeddedResult,
                handler: "src/chat-card.tsx",
                allowedContexts: [.mainApplication]
            ),
            HanlinEntryPointDescriptor(
                kind: .assistantTool,
                handler: "src/assistant-tool.tsx",
                allowedContexts: [.mainApplication]
            )
        ]
    )
    try descriptor.validate()
    let data = try descriptor.canonicalJSONData()
    let decoded = try HanlinAppDescriptor.decodeAndValidate(data)
    #expect(decoded == descriptor)

    let embeddedEntry = decoded.entryPoints.first { $0.kind == .embeddedResult }
    #expect(embeddedEntry != nil)
    #expect(embeddedEntry?.handler == "src/chat-card.tsx")
}
