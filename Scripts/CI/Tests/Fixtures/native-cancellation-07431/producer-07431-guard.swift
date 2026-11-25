    private func shouldStartAnotherStep() async -> Bool {
        guard let lastStep = recordedSteps.last else { return false }
        let clientToolCalls = clientToolCalls(in: lastStep)
        let clientToolOutputCount = clientToolOutputCount(in: lastStep)
        let clientToolCallsComplete = !clientToolCalls.isEmpty && clientToolOutputCount == clientToolCalls.count
        // The completed tool outputs determine continuation, not the provider's
        // finish label: compatible providers can report stop after a tool call.
        guard clientToolCallsComplete || !pendingDeferredToolCalls.isEmpty else { return false }
        return !(await isStopConditionMet(stopConditions: stopConditions, steps: recordedSteps))
    }

