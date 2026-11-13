import Foundation

/// CPython uses the same native queue/cancellation state as other linked engines.
typealias PythonQueuedExecution = RuntimeQueuedExecution<String, Data>
