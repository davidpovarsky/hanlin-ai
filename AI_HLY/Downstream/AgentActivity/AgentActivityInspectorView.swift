//
//  AgentActivityInspectorView.swift
//  AI_HLY
//

import SwiftUI

struct AgentActivityInspectorView: View {
    let run: AgentRun
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
                        AgentActivityStepView(
                            step: step,
                            isLast: index == run.steps.count - 1,
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
