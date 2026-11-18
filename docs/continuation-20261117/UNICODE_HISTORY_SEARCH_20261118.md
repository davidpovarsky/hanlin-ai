# Original history Unicode search — 2026-11-18

The original history snippet builder took String.Index values from a lowercased copy and used them to slice the original message and construct its highlight range. Lowercasing capital dotted I (U+0130) expands its UTF-8 representation. A message containing that character, sixty x characters, then END reliably trapped with Swift/StringIndexValidation.swift:210: Fatal error: String index range is out of bounds in the installed Swift 6.3.3 toolchain.

The shipping ListView now performs case-insensitive Foundation matching on the original message and computes its forty-Character context on that same String. The highlight also uses a range from the actual snippet. The original reverse message order, message UUID navigation, gray context, blue/bold match, pinned history order and pinyin title matching remain intact. Message filtering uses the same case-insensitive comparison.

Three native regression methods were added to the existing CompactRecentConversationsTests suite: the reproduced expanding case-fold input; emoji/pointed-Hebrew context boundaries; short, absent and empty matches. The exact production helper passed five assertions when compiled and executed with Windows Swift/Foundation. Both modified Swift files parsed. These are not substitutes for the selected Apple host tests, whose native result remains pending.

No conversations, database schema or stored user data were changed.
