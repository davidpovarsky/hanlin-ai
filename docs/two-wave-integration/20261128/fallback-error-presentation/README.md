# Fallback tool error presentation

The original production tool-recovery case reported a missing suppression diagnostic. Source inspection also shows that the fallback emitted only a failed activity event, while canonical user-visible result insertion occurs through the completed-result branch.

This single-file change constructs an actual NativeUIBlock.error using the existing redacted AgentSafeError message, asks the unchanged presentation coordinator, and emits an error-semantic AgentToolResult only when that decision permits a card. Otherwise the existing failed event remains. The recorder receives the same decision. Invalid-arguments outcome, failed status, tool-result continuation, duplicate protection, original test assertions and time allowances remain unchanged.

Independent review verifies the exact three-hunk inverse and the actual accumulator, coordinator, recorder, type declarations and renderer paths. This is source approval only: no compiler, test, Simulator or native result is claimed. The original production conversation and presentation acceptance remain required.
