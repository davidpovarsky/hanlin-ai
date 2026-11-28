# Contextual original text tools

Historical obligation: PARITY-NAV-26.

Translation, polishing and summarization now open from Text actions in the existing message text-selection screen. They receive the selected range, or the original message when no range is selected. Each opening captures the source text and presents the existing tool view. Native Done returns to the same selection and original conversation. The three permanent Home/sidebar buttons and their unused callbacks/sheets were removed; the original tools, models, provider handling and data remain.

The original QuickTools views accept initialText with an empty default, preserving other callers. No new summarizer, translator, agent or stored conversation is created. Existing selection/copy/save actions remain.

Added original-app selector:
AI_HLYUITests/HanlinContextualTextToolsUITests/testOriginalTextToolsReceiveTheMessageWithoutReplacingTheConversation

This checks all three retained input views receive the real source message and return to its original conversation. It does not claim a successful provider translation or summarization. The test input is created through the existing isolated UUID-scoped SwiftData acceptance store.

Windows Swift syntax checks and stale-call-site search passed. Native compilation/UI acceptance remain PENDING.
