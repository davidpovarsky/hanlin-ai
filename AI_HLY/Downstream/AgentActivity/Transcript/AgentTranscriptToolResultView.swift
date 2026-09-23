import HanlinPlatformContracts
import SwiftUI

struct AgentTranscriptToolResultView: View {
  let item: AgentTranscriptItem
  let temporaryRecord: Bool
  let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

  var body: some View {
    // 1. If canonical embedded handler exists AND resolves -> render arbitrary Mini-App surface in ChatEmbeddedResultHost
    if let embedded = item.canonicalEmbeddedPresentation,
       let handler = embedded.handler,
       let session = HanlinEmbeddedResultResolver.shared.resolve(
         handler: handler,
         toolName: item.toolName,
         payload: item.embeddedResultPayload
       ) {
      let sizing = embedded.sizing
      let expansion = ChatPresentationBridge.expansionDescriptor(
        explicit: embedded,
        for: item.nativeUIBlocks,
        toolName: item.toolName
      )
      let title = item.embeddedResultPayload?.title ?? item.nativeUIBlocks.compactMap(\.title).first ?? item.toolName

      ChatEmbeddedResultHost(
        title: title,
        sizingPreference: sizing,
        expansionDescriptor: expansion,
        containerStyle: .neutral,
        onLaunchRequest: onLaunchRequest
      ) {
        HanlinEmbeddedResultSurface(session: session)
      }
    }
    // 2. Else if modern NativeUIBlocks exist -> existing ModernNativeToolResultRenderer fallback
    else if !item.nativeUIBlocks.isEmpty && item.resultRendererKind == .modernNative {
      let sizing = ChatPresentationBridge.sizingPreference(
        explicit: item.canonicalEmbeddedPresentation,
        for: item.nativeUIBlocks,
        toolName: item.toolName
      )
      let expansion = ChatPresentationBridge.expansionDescriptor(
        explicit: item.canonicalEmbeddedPresentation,
        for: item.nativeUIBlocks,
        toolName: item.toolName
      )
      let title = item.nativeUIBlocks.compactMap(\.title).first ?? item.toolName

      ChatEmbeddedResultHost(
        title: title,
        sizingPreference: sizing,
        expansionDescriptor: expansion,
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
