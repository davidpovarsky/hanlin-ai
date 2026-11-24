    private func shouldStartAnotherStep() async -> Bool {
        guard let lastStep = recordedSteps.last else { return false }
        guard lastStep.finishReason == .toolCalls else { return false }
        let clientToolCalls = clientToolCalls(in: lastStep)
        let clientToolOutputCount = clientToolOutputCount(in: lastStep)
        let clientToolCallsComplete = !clientToolCalls.isEmpty && clientToolOutputCount == clientToolCalls.count
        let stopMet = await isStopConditionMet(stopConditions: stopConditions, steps: recordedSteps)
        return (clientToolCallsComplete || !pendingDeferredToolCalls.isEmpty) && !stopMet
    }

