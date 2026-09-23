import HanlinPlatformContracts
import SwiftUI

struct AgentTranscriptToolResultView: View {
  let item: AgentTranscriptItem
  let temporaryRecord: Bool
  let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

  var body: some View {
    // 1. If canonical embedded handler exists (or declared on payload) AND resolves -> render arbitrary Mini-App surface in ChatEmbeddedResultHost
    let effectiveEmbedded: HanlinEmbeddedPresentationDescriptor? = item.canonicalEmbeddedPresentation
      ?? item.embeddedResultPayload?.ownerID.map { ownerID in
        HanlinEmbeddedPresentationDescriptor(
          handler: ownerID,
          sizing: HanlinEmbeddedSizingPreference(preset: .regular),
          expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
        )
      }

    if let embedded = effectiveEmbedded,
       let handler = embedded.handler,
       let session = HanlinEmbeddedResultResolver.shared.resolve(
         handler: handler,
         ownerID: item.embeddedResultPayload?.ownerID,
         toolName: item.toolName,
         payload: item.embeddedResultPayload
       ) {
      let sizing = embedded.sizing
      let title = item.embeddedResultPayload?.title ?? item.nativeUIBlocks.compactMap(\.title).first ?? item.toolName

      // Resolve all valid expansion modes, validating expandedHandler if specified
      let expansions = ChatPresentationBridge.resolveExpansions(
        descriptor: embedded,
        title: title,
        handler: handler,
        canResolveHandler: { expHandler in
          HanlinEmbeddedResultResolver.shared.resolve(
            handler: expHandler,
            ownerID: item.embeddedResultPayload?.ownerID,
            toolName: item.toolName,
            payload: item.embeddedResultPayload
          ) != nil
        }
      )

      let contentActions = item.embeddedResultPayload?.actions ?? []

      ChatEmbeddedResultHost(
        title: title,
        sizingPreference: sizing,
        expansions: expansions,
        contentActions: contentActions,
        containerStyle: .neutral,
        onLaunchRequest: onLaunchRequest
      ) {
        HanlinEmbeddedResultSurface(session: session)
      } expandedContent: {
        // If an expandedHandler is declared and resolves, present that; otherwise reuse session
        if let expHandler = embedded.expandedHandler,
           let expandedSession = HanlinEmbeddedResultResolver.shared.resolve(
             handler: expHandler,
             ownerID: item.embeddedResultPayload?.ownerID,
             toolName: item.toolName,
             payload: item.embeddedResultPayload
           ) {
          HanlinEmbeddedResultSurface(session: expandedSession)
        } else {
          HanlinEmbeddedResultSurface(session: session)
        }
      }
    }
    // 2. Else if modern NativeUIBlocks exist -> existing ModernNativeToolResultRenderer fallback
    else if !item.nativeUIBlocks.isEmpty && item.resultRendererKind == .modernNative {
      let sizing = ChatPresentationBridge.sizingPreference(
        explicit: item.canonicalEmbeddedPresentation,
        for: item.nativeUIBlocks,
        toolName: item.toolName
      )
      let title = item.nativeUIBlocks.compactMap(\.title).first ?? item.toolName
      let expansions = ChatPresentationBridge.resolveExpansions(
        descriptor: item.canonicalEmbeddedPresentation,
        title: title
      )

      ChatEmbeddedResultHost(
        title: title,
        sizingPreference: sizing,
        expansions: expansions,
        contentActions: item.embeddedResultPayload?.actions ?? [],
        containerStyle: .neutral,
        onLaunchRequest: onLaunchRequest
      ) {
        ModernNativeToolResultRenderer(
          blocks: item.nativeUIBlocks,
          onLaunchRequest: onLaunchRequest
        )
      }
    }
    // 3. Else if legacyExisting -> preserve legacy rendering path exactly
    else if !item.nativeUIBlocks.isEmpty && (item.resultRendererKind == .legacyExisting || item.resultRendererKind == nil) {
      NativeUIToolResultContainer(
        blocks: item.nativeUIBlocks,
        temporaryRecord: temporaryRecord,
        onLaunchRequest: onLaunchRequest
      )
    }
  }
}
