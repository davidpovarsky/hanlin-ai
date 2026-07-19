import SwiftUI

struct ModernNativeToolResultRenderer: View {
    let blocks: [NativeUIBlock]
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var expandedBlock: NativeUIBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.type {
                case .searchResults:
                    NativeToolSearchResultCard(
                        block: block,
                        onLaunchRequest: onLaunchRequest,
                        onViewAll: { expandedBlock = block }
                    )
                case .error:
                    NativeToolErrorCard(block: block, onLaunchRequest: onLaunchRequest)
                case .text, .markdown, .card, .source, .wikipediaSummary, .calculation, .keyValueList:
                    NativeToolEntityCard(
                        block: block,
                        onLaunchRequest: onLaunchRequest,
                        onViewAll: { expandedBlock = block }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $expandedBlock) { block in
            NavigationStack {
                ScrollView {
                    NativeUIRenderer(
                        blocks: [block],
                        presentationMode: .expanded,
                        onLaunchRequest: onLaunchRequest
                    )
                    .padding()
                }
                .navigationTitle(block.title ?? String(localized: "Result card"))
                .navigationBarTitleDisplayMode(.inline)
                .presentationDragIndicator(.visible)
            }
        }
    }
}
