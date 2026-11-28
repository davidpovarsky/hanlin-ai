# Controlled Owner stream completion

The real original90 run at de7758a9 reported two Owner test errors while draining a controlled provider stream: incompleteProviderResponse(stop). Its shared test source emitted a stop event without text, tools or structured content. The unchanged real engine rejects that empty response.

Source commit 0edf7784 adds only the original V3 textStart, textDelta and textEnd events immediately before the existing stop/finish. The fixture still emits nothing until the existing test releases it through finish. No production code, model contract, cancellation or deletion assertion, deadline, task, delay or native selector changed. Removing those three event lines recovers the entire previous file. All 655 assertion lines, 15 timing lines and 93 other function blocks remain exact.

Six original test definitions consume this helper. Two previously failed during normal completion; four previously passed their cancelled or revoked paths. Those prior results remain attributed to their original execution and do not qualify the changed fixture. Native validation is pending. The original engine guard and existing known V3 fixture examples are retained as source authorities.

The lossless patch, source qualification and exact prior failed result nodes are included. Complete original logs remain bound by their raw hashes and the retained original terminal manifest. No test was weakened or rerun during this source correction.

Both independent source reviews are retained verbatim. Their approval leaves the six original native consumer obligations pending.
