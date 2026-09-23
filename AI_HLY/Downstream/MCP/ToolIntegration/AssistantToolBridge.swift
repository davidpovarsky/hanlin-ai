import Foundation

import HanlinPlatformContracts

@MainActor
enum AssistantToolBridge {
  struct Executors {
    let executeNative:
      @MainActor (
        HanlinProviderInstanceID,
        String,
        String,
        NativeToolExecutionContext
      ) async -> NativeToolResult
    let executeMCP:
      @MainActor (
        UUID,
        String,
        String,
        String
      ) async -> NativeToolResult
    let executeScripting:
      @MainActor (
        HanlinScriptBackendRoute,
        String
      ) async -> NativeToolResult
    let executeLegacy:
      @MainActor (
        String,
        String,
        NativeToolExecutionContext
      ) async -> NativeToolResult

    init(
      executeNative: @escaping @MainActor (
        HanlinProviderInstanceID,
        String,
        String,
        NativeToolExecutionContext
      ) async -> NativeToolResult,
      executeMCP: @escaping @MainActor (
        UUID,
        String,
        String,
        String
      ) async -> NativeToolResult = { _, _, _, _ in
        NativeToolResult(modelText: "MCP not configured", outcome: .failed)
      },
      executeScripting: @escaping @MainActor (
        HanlinScriptBackendRoute,
        String
      ) async -> NativeToolResult,
      executeLegacy: (@MainActor (
        String,
        String,
        NativeToolExecutionContext
      ) async -> NativeToolResult)? = nil
    ) {
      self.executeNative = executeNative
      self.executeMCP = executeMCP
      self.executeScripting = executeScripting
      self.executeLegacy = executeLegacy ?? { toolName, _, _ in
        NativeToolResult(
          modelText: "Legacy tool '\(toolName)' executed.",
          userText: nil,
          uiBlocks: [],
          outcome: .succeeded
        )
      }
    }

    static var live: Self {
      live(scriptingRegistry: .shared)
    }

    static func live(
      scriptingRegistry: HanlinScriptingProviderRegistry,
      executeLegacy: (@MainActor (String, String, NativeToolExecutionContext) async -> NativeToolResult)? = nil
    ) -> Self {
      Self(
        executeNative: { providerInstanceID, toolName, argumentsJSON, context in
          await NativeToolBridge.executeCanonical(
            providerInstanceID: providerInstanceID,
            toolName: toolName,
            argumentsJSON: argumentsJSON,
            context: context
          )
        },
        executeMCP: { serverID, toolName, resultTitle, argumentsJSON in
          await MCPToolBridge.execute(
            serverID: serverID,
            toolName: toolName,
            resultTitle: resultTitle,
            argumentsJSON: argumentsJSON
          )
        },
        executeScripting: { route, argumentsJSON in
          do {
            let result = try await scriptingRegistry.execute(
              route: route,
              argumentsJSON: argumentsJSON
            )
            if result.isStructured {
              return try nativeResult(for: result)
            }
            let modelText: String
            if let data = result.data {
              let payload = HanlinJSONValue.object([
                "success": .bool(result.success),
                "message": .string(result.message),
                "data": try data.jsonValue(),
              ])
              modelText = String(
                decoding: try payload.canonicalJSONData(),
                as: UTF8.self
              )
            } else {
              modelText = result.message
            }
            return NativeToolResult(
              modelText: modelText,
              userText: result.success ? nil : result.message,
              uiBlocks: result.success
                ? []
                : [
                  .init(
                    type: .error,
                    title: "Script tool failed",
                    body: result.message,
                    systemImage: "exclamationmark.triangle"
                  )
                ],
              outcome: result.success ? .succeeded : .failed
            )
          } catch let error as HanlinScriptingError {
            return NativeToolResult(
              modelText: "Script tool failed (\(error.diagnosticCode)).",
              userText: error.localizedDescription,
              uiBlocks: [
                .init(
                  type: .error,
                  title: "Script tool failed",
                  body: error.localizedDescription,
                  systemImage: "exclamationmark.triangle"
                )
              ],
              outcome: .failed
            )
          } catch {
            return NativeToolResult(
              modelText: "Script tool failed (unexpected_failure).",
              userText: "The Script tool could not complete.",
              uiBlocks: [
                .init(
                  type: .error,
                  title: "Script tool failed",
                  body: "The Script tool could not complete.",
                  systemImage: "exclamationmark.triangle"
                )
              ],
              outcome: .failed
            )
          }
        },
        executeLegacy: executeLegacy ?? { toolName, _, _ in
          NativeToolResult(
            modelText: "Legacy tool '\(toolName)' executed.",
            userText: nil,
            outcome: .succeeded
          )
        }
      )
    }

    static func nativeResult(
      for result: HanlinScriptToolExecutionResult
    ) throws -> NativeToolResult {
      let assistantParts = result.assistantParts ?? []
      let assistantPayload = HanlinValue.object([
        "success": .bool(result.success),
        "output": .object([
          "assistantParts": .array(assistantParts.map(\.value))
        ]),
      ])
      let modelText = String(
        decoding: try assistantPayload.canonicalJSONData(),
        as: UTF8.self
      )
      let userParts = result.userParts ?? []
      let userText = userParts.compactMap { part -> String? in
        switch part {
        case .string(let text), .text(let text): text
        case .image: nil
        }
      }.joined(separator: "\n")
      let blocks = userParts.map { part -> NativeUIBlock in
        switch part {
        case .string(let text), .text(let text):
          return NativeUIBlock(type: .markdown, body: text)
        case .image(let base64, let mimeType):
          return NativeUIBlock(
            type: .card,
            title: String(localized: "Image"),
            systemImage: "photo",
            embeddedImageBase64: base64,
            embeddedImageMIMEType: mimeType
          )
        }
      }
      return NativeToolResult(
        modelText: modelText,
        userText: userText.isEmpty ? nil : userText,
        uiBlocks: blocks,
        outcome: result.success ? .succeeded : .failed
      )
    }
  }

  @MainActor
  struct PreparedTools {
    let authority: HanlinCanonicalToolAuthority
    let executors: Executors

    init(
      authority: HanlinCanonicalToolAuthority,
      executors: Executors = .live
    ) {
      self.authority = authority
      self.executors = executors
    }

    var schemas: [[String: Any]] {
      authority.modelSchemas
    }

    func schemas(for exposedAliases: Set<String>) -> [[String: Any]] {
      authority.schemas(forAliases: exposedAliases)
    }

    func schemaSizes() -> [String: Int] {
      var sizes: [String: Int] = [:]
      for (alias, schema) in authority.schemasByAlias {
        if let data = try? JSONSerialization.data(withJSONObject: schema) {
          sizes[alias] = data.count
        } else {
          sizes[alias] = 250
        }
      }
      return sizes
    }

    func search(query: String, limit: Int = 10) -> [CanonicalToolSearchRecord] {
      let terms = query.lowercased().split(separator: " ").map(String.init)
      let all = authority.searchableMetadata()
      guard !terms.isEmpty else { return Array(all.prefix(limit)) }
      let scored = all.compactMap { record -> (CanonicalToolSearchRecord, Int)? in
        var score = 0
        let alias = record.alias.lowercased()
        let title = record.title.lowercased()
        let summary = record.summary.lowercased()
        for term in terms {
          if alias == term { score += 50 }
          else if alias.contains(term) { score += 20 }
          if title.contains(term) { score += 15 }
          if summary.contains(term) { score += 10 }
          for kw in record.keywords where kw.lowercased().contains(term) {
            score += 5
          }
        }
        return score > 0 ? (record, score) : nil
      }
      return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func presentationProfile(for alias: String) -> ToolPresentationProfile? {
      guard let resolution = authority.resolution(alias: alias) else { return nil }
      var profile = resolution.presentationProfile
      if profile.canonicalExecutionPresentation == nil {
        profile.canonicalExecutionPresentation = resolution.toolPresentation.executionPresentation
      }
      if profile.canonicalEmbeddedPresentation == nil {
        profile.canonicalEmbeddedPresentation = resolution.toolPresentation.embeddedPresentation
      }
      return profile
    }

    func toolPresentation(for alias: String) -> HanlinToolPresentationDescriptor? {
      authority.resolution(alias: alias)?.toolPresentation
    }

    func toolDescriptor(for alias: String) -> HanlinToolDescriptor? {
      authority.toolDescriptor(for: alias)
    }

    func execute(
      alias: String,
      argumentsJSON: String,
      context: NativeToolExecutionContext
    ) async -> NativeToolResult? {
      guard let resolution = authority.resolution(alias: alias) else {
        return nil
      }
      var result: NativeToolResult
      switch resolution.backend {
      case .native(let providerInstanceID, let toolName):
        result = await executors.executeNative(
          providerInstanceID,
          toolName,
          argumentsJSON,
          context
        )
      case .mcp(let serverID, let toolName):
        result = await executors.executeMCP(
          serverID,
          toolName,
          resolution.resultTitle ?? toolName,
          argumentsJSON
        )
      case .scripting(let route):
        result = await executors.executeScripting(route, argumentsJSON)
      case .legacy(let toolName):
        result = await executors.executeLegacy(toolName, argumentsJSON, context)
      }
      let logicalID = resolution.route.logicalToolID
      result.diagnostics.canonicalLogicalToolID =
        "\(logicalID.providerInstanceID.rawValue)|\(logicalID.localToolID.rawValue)"
      result.diagnostics.modelFacingAlias = alias
      result.diagnostics.backendRoute = backendRouteDescription(resolution.backend)
      result.diagnostics.source = backendSource(resolution.backend)
      return result
    }

    private func backendRouteDescription(
      _ backend: HanlinCanonicalToolBackendRoute
    ) -> String {
      switch backend {
      case .native(let providerInstanceID, let toolName):
        "native:\(providerInstanceID.rawValue):\(toolName)"
      case .mcp(let serverID, let toolName):
        "mcp:\(serverID.uuidString.lowercased()):\(toolName)"
      case .scripting(let route):
        "scripting:\(route.providerInstanceID.rawValue)"
      case .legacy(let toolName):
        "legacy:\(toolName)"
      }
    }

    private func backendSource(_ backend: HanlinCanonicalToolBackendRoute) -> String {
      switch backend {
      case .native: "native"
      case .mcp: "mcp"
      case .scripting: "scripting"
      case .legacy: "legacy"
      }
    }
  }

  static func prepare(
    scope: AssistantToolRequestScope,
    legacySources: [HanlinCanonicalToolAuthority.LegacySource] = [],
    legacyExecutor: (@MainActor (String, String, NativeToolExecutionContext) async -> NativeToolResult)? = nil,
    scriptingRegistry: HanlinScriptingProviderRegistry = .shared
  ) async throws -> PreparedTools {
    do {
      let nativeSources = try NativeToolBridge.canonicalSourcesForRequest()
      let mcpTools = await MCPToolBridge.resolveDescriptors(scope: scope)
      let scriptSources = try HanlinScriptCanonicalAdapter.project(
        await scriptingRegistry.snapshots()
      )
      let executors = Executors.live(
        scriptingRegistry: scriptingRegistry,
        executeLegacy: legacyExecutor
      )
      return PreparedTools(
        authority: try HanlinCanonicalToolAuthority.build(
          nativeSources: nativeSources,
          mcpTools: mcpTools,
          scriptSources: scriptSources,
          legacySources: legacySources
        ),
        executors: executors
      )
    } catch {
      NativeToolTraceLogger.shared.log(
        "canonical_tool_authority_build_failed",
        [
          "errorType": String(describing: type(of: error)),
          "message": error.localizedDescription,
        ]
      )
      throw error
    }
  }
}
