import Foundation
import HanlinPlatformContracts
import SwiftUI
import Testing

@testable import AI_Hanlin

@Suite("Chat canonical presentation survival", .serialized)
struct ChatCanonicalPresentationSurvivalTests {

  @MainActor
  @Test(
    "Dynamic non-builtin tool preserves presentation descriptors across entire event and transcript pipeline"
  )
  func dynamicToolPresentationSurvival() throws {
    let toolName = "dynamic_analytics_runner"

    // 1. Verify this tool is NOT in BuiltinCanonicalRegistrations
    #expect(ChatPresentationBridge.findCanonicalTool(named: toolName) == nil)

    // 2. Construct tool presentation profile with explicit canonical descriptors
    let customFamily: HanlinExecutionPresentationFamilyID = "custom-analytics"
    let executionPresentation = HanlinToolExecutionPresentationDescriptor(
      familyID: customFamily,
      customHandler: "analytics.mini.app"
    )
    let embeddedPresentation = HanlinEmbeddedPresentationDescriptor(
      handler: "analytics.card",
      sizing: HanlinEmbeddedSizingPreference(preset: .large),
      expansion: HanlinExpansionDescriptor(supportedModes: [.window, .sheet])
    )

    var profile = ToolPresentationProfile.generic(toolName: toolName)
    profile.canonicalExecutionPresentation = executionPresentation
    profile.canonicalEmbeddedPresentation = embeddedPresentation

    let canonicalSchema = NativeToolSchema.function(
      name: toolName,
      description: "Analytics tool",
      parameters: NativeToolSchema.object(
        properties: ["metric": NativeToolSchema.string(description: "Metric name")],
        required: ["metric"]
      )
    )
    let source = HanlinCanonicalToolAuthority.NativeSource(
      entry: NativeToolCatalogEntry(
        name: toolName,
        title: "Analytics Runner",
        summary: "Runs dynamic analytics",
        presentationProfile: profile
      ),
      canonicalSchema: canonicalSchema,
      modelSchema: ToolSchemaDecorator.decorate(
        schema: canonicalSchema,
        profile: profile,
        progressSummaryRequired: false
      )
    )

    // 3. Build canonical tool authority and verify descriptors are preserved in resolution
    let authority = try HanlinCanonicalToolAuthority.build(
      nativeSources: [source],
      mcpTools: []
    )
    let resolution = try #require(authority.resolution(alias: toolName))
    #expect(resolution.toolPresentation.executionPresentation?.familyID == customFamily)
    #expect(resolution.toolPresentation.embeddedPresentation?.sizing.preset == .large)
    #expect(resolution.presentationProfile.canonicalExecutionPresentation?.familyID == customFamily)
    #expect(resolution.presentationProfile.canonicalEmbeddedPresentation?.sizing.preset == .large)

    // 4. Trace through AgentToolCall.parse
    let call = AgentToolCall.parse(
      id: "call_analytics_1",
      name: toolName,
      argumentsJSON: #"{"metric":"active_users"}"#,
      presentationProfile: resolution.presentationProfile
    )
    #expect(call.canonicalExecutionPresentation?.familyID == customFamily)
    #expect(call.canonicalEmbeddedPresentation?.sizing.preset == .large)

    // 5. Trace through AgentEventAccumulator
    var accumulator = AgentEventAccumulator()
    let callStartedAt = Date()
    accumulator.apply(.toolCallStarted(call))

    let transcriptItem = try #require(
      accumulator.transcript.items.first(where: { $0.callID == call.id }))
    #expect(transcriptItem.toolName == toolName)
    #expect(transcriptItem.canonicalExecutionPresentation?.familyID == customFamily)
    #expect(transcriptItem.canonicalEmbeddedPresentation?.sizing.preset == .large)

    let step = try #require(
      accumulator.run.steps.first(where: { $0.externalID == "call:\(call.id)" }))
    #expect(step.canonicalExecutionPresentation?.familyID == customFamily)
    #expect(step.canonicalEmbeddedPresentation?.sizing.preset == .large)

    // Tool execution starts
    accumulator.apply(
      .toolExecutionStarted(
        AgentToolExecution(
          id: "exec_analytics_1",
          callID: call.id,
          name: toolName,
          startedAt: callStartedAt
        )))

    // Tool execution completes with UI blocks
    let resultBlock = NativeUIBlock(
      id: "block_1",
      type: .custom,
      title: "Analytics Result",
      body: "Active users: 4200"
    )
    let toolResult = AgentToolResult(
      modelText: "Success",
      userText: "Analytics complete",
      richResultBlocks: [resultBlock],
      hasLegacyPresentationPayload: false,
      isError: false,
      duration: 0.5
    )
    accumulator.apply(.toolExecutionCompleted(id: "exec_analytics_1", result: toolResult))

    // Check user visible result item in transcript
    let resultItem = try #require(
      accumulator.transcript.items.first(where: { $0.kind == .userVisibleToolResult }))
    #expect(resultItem.toolName == toolName)
    #expect(resultItem.canonicalExecutionPresentation?.familyID == customFamily)
    #expect(resultItem.canonicalEmbeddedPresentation?.sizing.preset == .large)

    // Check AgentActivityComposer
    let timeline = AgentActivityComposer.compose(accumulator.run)
    let displayActivity = try #require(timeline.activities.first)
    #expect(displayActivity.executionPresentation?.familyID == customFamily)
    #expect(displayActivity.embeddedPresentation?.sizing.preset == .large)

    // 6. Verify ChatPresentationBridge consumes explicit descriptors directly without BuiltinCanonicalRegistrations
    let resolvedFamily = ChatPresentationBridge.executionFamily(
      explicit: displayActivity.executionPresentation,
      toolName: toolName
    )
    #expect(resolvedFamily == customFamily)

    let itemResolvedFamily = ChatPresentationBridge.executionFamily(
      explicit: resultItem.canonicalExecutionPresentation,
      toolName: toolName
    )
    #expect(itemResolvedFamily == customFamily)

    let resolvedSizing = ChatPresentationBridge.sizingPreference(
      explicit: resultItem.canonicalEmbeddedPresentation?.sizing,
      for: resultItem.nativeUIBlocks,
      toolName: toolName
    )
    #expect(resolvedSizing.preset == .large)

    let resolvedExpansion = ChatPresentationBridge.expansionDescriptor(
      explicit: resultItem.canonicalEmbeddedPresentation?.expansion,
      for: resultItem.nativeUIBlocks,
      toolName: toolName
    )
    #expect(resolvedExpansion != nil)
  }

  @MainActor
  @Test("Scripting tool presentation descriptors survive into Chat presentation bridge")
  func scriptingToolPresentationSurvival() throws {
    let providerID = try HanlinProviderInstanceID(validating: "script.provider.test")
    let localToolID = try HanlinToolID(validating: "script_evaluator")
    let alias = "script__test__evaluator"

    #expect(ChatPresentationBridge.findCanonicalTool(named: alias) == nil)

    let schema = try HanlinJSONSchemaDocument(
      dialect: .draft2020_12,
      root: .object([
        "type": .string("object"),
        "properties": .object([
          "code": .object(["type": .string("string")])
        ]),
        "required": .array([.string("code")]),
      ])
    )
    let route = HanlinScriptBackendRoute(
      providerInstanceID: providerID,
      installedPackageID: try HanlinInstalledPackageID(
        validating: "script-package.11111111111111111111111111111111"),
      entrypointPath: "eval.js",
      localToolID: localToolID
    )

    let scriptExecution = HanlinToolExecutionPresentationDescriptor(
      familyID: .codeExecution,
      customHandler: "eval.runner"
    )
    let scriptEmbedded = HanlinEmbeddedPresentationDescriptor(
      handler: "eval.output",
      sizing: HanlinEmbeddedSizingPreference(preset: .compact),
      expansion: HanlinExpansionDescriptor(supportedModes: [.sheet])
    )
    let presentation = HanlinToolPresentationDescriptor(
      compactStyle: .code,
      supportsExpandedPresentation: true,
      executionPresentation: scriptExecution,
      embeddedPresentation: scriptEmbedded
    )

    var profile = ToolPresentationProfile.generic(toolName: alias)
    profile.canonicalExecutionPresentation = scriptExecution
    profile.canonicalEmbeddedPresentation = scriptEmbedded

    let scriptSource = HanlinCanonicalToolAuthority.ScriptSource(
      descriptor: HanlinToolDescriptor(
        logicalID: HanlinLogicalToolID(
          providerInstanceID: providerID,
          localToolID: localToolID
        ),
        descriptorRevision: try HanlinDescriptorRevision(1),
        owner: .package(try HanlinPackageID(validating: "com.hanlin.script.eval")),
        title: try LocalizedValue(["en": "Script Evaluator"]),
        summary: try LocalizedValue(["en": "Evaluates dynamic code"]),
        inputSchema: schema,
        risk: .read,
        presentation: presentation
      ),
      preferredAlias: alias,
      modelSchema: [
        "type": "function",
        "function": [
          "name": alias,
          "description": "Evaluates dynamic code",
          "parameters": ["type": "object", "properties": [:]],
        ],
      ],
      backendRoute: route,
      presentationProfile: profile,
      resultTitle: "Evaluator Result"
    )

    let authority = try HanlinCanonicalToolAuthority.build(
      nativeSources: [],
      mcpTools: [],
      scriptSources: [scriptSource]
    )

    let resolution = try #require(authority.resolution(alias: alias))
    #expect(resolution.toolPresentation.executionPresentation?.familyID == .codeExecution)
    #expect(
      resolution.presentationProfile.canonicalExecutionPresentation?.familyID == .codeExecution)
    #expect(resolution.presentationProfile.canonicalEmbeddedPresentation?.sizing.preset == .compact)

    // Verify ChatPresentationBridge consumes explicit script descriptors directly
    let family = ChatPresentationBridge.executionFamily(
      explicit: resolution.presentationProfile.canonicalExecutionPresentation,
      toolName: alias
    )
    #expect(family == .codeExecution)

    let sizing = ChatPresentationBridge.sizingPreference(
      explicit: resolution.presentationProfile.canonicalEmbeddedPresentation?.sizing,
      toolName: alias
    )
    #expect(sizing.preset == .compact)
  }

  @MainActor
  @Test(
    "Built-in canonical tools continue to resolve presentation via fallback when explicit is absent"
  )
  func builtinCanonicalToolsFallback() {
    let builtinToolName = "sefaria_search"

    // Verify built-in lookup finds the tool
    let tool = ChatPresentationBridge.findCanonicalTool(named: builtinToolName)
    #expect(tool != nil)
    #expect(tool?.presentation.executionPresentation?.familyID == .sourceSearch)

    // When explicit presentation is nil, bridge resolves via BuiltinCanonicalRegistrations fallback
    let resolvedFamily = ChatPresentationBridge.executionFamily(
      explicit: nil,
      toolName: builtinToolName
    )
    #expect(resolvedFamily == .sourceSearch)

    let resolvedSizing = ChatPresentationBridge.sizingPreference(
      explicit: nil as HanlinEmbeddedPresentationDescriptor?,
      toolName: builtinToolName
    )
    #expect(resolvedSizing.preset == .regular)

    let resolvedExpansion = ChatPresentationBridge.expansionDescriptor(
      explicit: nil as HanlinEmbeddedPresentationDescriptor?,
      toolName: builtinToolName
    )
    #expect(resolvedExpansion != nil)
  }

  @MainActor
  @Test("Canonical presentation metadata takes precedence over generic fallbacks and heuristics")
  func canonicalMetadataPrecedence() {
    // 1. Tool named "run_command" normally resolves to .command heuristic
    let heuristicFamily = ChatPresentationBridge.executionFamily(
      explicit: nil,
      toolName: "run_command"
    )
    #expect(heuristicFamily == .command)

    // With explicit presentation, explicit family takes precedence
    let customExplicit = HanlinToolExecutionPresentationDescriptor(familyID: "sandbox-terminal")
    let overriddenFamily = ChatPresentationBridge.executionFamily(
      explicit: customExplicit,
      toolName: "run_command"
    )
    #expect(overriddenFamily == "sandbox-terminal")

    // 2. Search results blocks normally resolve to .regular sizing
    let searchBlocks = [
      NativeUIBlock(
        id: "sb1",
        type: .searchResults,
        title: "Search Results",
        body: "Found 5 items"
      )
    ]
    let defaultSearchSizing = ChatPresentationBridge.sizingPreference(
      explicit: nil as HanlinEmbeddedPresentationDescriptor?,
      for: searchBlocks,
      toolName: "unknown_search"
    )
    #expect(defaultSearchSizing.preset == .regular)

    // With explicit compact sizing preference, explicit takes precedence
    let compactExplicit = HanlinEmbeddedPresentationDescriptor(
      sizing: HanlinEmbeddedSizingPreference(preset: .compact)
    )
    let overriddenSizing = ChatPresentationBridge.sizingPreference(
      explicit: compactExplicit,
      for: searchBlocks,
      toolName: "unknown_search"
    )
    #expect(overriddenSizing.preset == .compact)
  }
}
