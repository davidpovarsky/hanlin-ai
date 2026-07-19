import SwiftUI

struct AgentTranscriptToolResultView: View {
    let item: AgentTranscriptItem
    let temporaryRecord: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        if !item.nativeUIBlocks.isEmpty {
            switch item.resultRendererKind {
            case .modernNative:
                ModernNativeToolResultRenderer(
                    blocks: item.nativeUIBlocks,
                    onLaunchRequest: onLaunchRequest
                )
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
