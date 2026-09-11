import HanlinPlatformContracts
import SwiftUI

struct AgentTranscriptToolResultView: View {
  let item: AgentTranscriptItem
  let temporaryRecord: Bool
  let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

  var body: some View {
    if !item.nativeUIBlocks.isEmpty {
      switch item.resultRendererKind {
      case .modernNative:
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
      case .legacyExisting, .none:
        NativeUIToolResultContainer(
          blocks: item.nativeUIBlocks,
          temporaryRecord: temporaryRecord,
          onLaunchRequest: onLaunchRequest
        )
      }
    }
  }
}
