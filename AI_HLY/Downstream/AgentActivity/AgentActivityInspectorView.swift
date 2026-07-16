//
//  AgentActivityInspectorView.swift
//  AI_HLY
//

import SwiftUI

struct AgentActivityInspectorView: View {
    let run: AgentRun
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(timeline.activities.enumerated()), id: \.element.id) { index, activity in
                        AgentActivityStepView(
                            activity: activity,
                            isLast: index == timeline.activities.count - 1,
                            onLaunchRequest: onLaunchRequest
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Thinking"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label(String(localized: "Close"), systemImage: "xmark")
                    }
                }
            }
        }
    }
}
