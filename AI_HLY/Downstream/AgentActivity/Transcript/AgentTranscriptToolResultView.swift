import SwiftUI

struct AgentTranscriptToolResultView: View {
    let item: AgentTranscriptItem
    let temporaryRecord: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    var body: some View {
        if !item.nativeUIBlocks.isEmpty {
            NativeUIToolResultContainer(
                blocks: item.nativeUIBlocks,
                temporaryRecord: temporaryRecord,
                onLaunchRequest: onLaunchRequest
            )
        }
    }
}
