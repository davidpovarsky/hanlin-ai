# Notification content conformance isolation

The original MiniApps build on759e5cf9 stopped with Swift ConformanceIsolation at the existing UNNotificationContentExtension conformance. The compiler recommended isolating that conformance to MainActor. Commitd7d10dff makes exactly that declaration change; the class was already MainActor-isolated and all callback bodies, imports and receipt logic remain byte-identical. The reachability auditor keeps its exact fail-closed matcher and now requires the explicit actor-isolated conformance.

Four original source/reachability write-and-check command records were recovered unchanged; they passed102 sources/200 exports and100 source-backed reachability cells. A prior missing-mode invocation is preserved as a failed usage attempt. A scoped in-memory negative control confirms that removing the conformance isolation still fails the original auditor. No passing tests were repeated during this resumption.

Generated inventories retain the same routes, target declarations, entitlements and acceptance statuses. Native compilation and actual system notification presentation on the corrected source remain with the original Mac runner; source audits do not satisfy those gates.
