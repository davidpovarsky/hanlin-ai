# Spotlight protocol executor correction

The original paired MiniApps compile failed before tests because a non-Sendable SDK description entered a MainActor protocol witness. The reviewed change keeps both witnesses nonisolated and moves only the existing catalog/index work into a shared MainActor helper. This is a source review, not native acceptance. Full raw failure evidence and SDK declarations are retained in the adjacent paired-f103996c-index-conformance-failure archive.
