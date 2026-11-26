# Expo widget property construction

MAIN13 failed while compiling the new publication validation statement: the
`HanlinValue.object` case accepts `HanlinObject<HanlinValue>`, whereas the
public publication method receives `[String: HanlinValue]`.

The single production change uses the existing throwing
`HanlinObject(uniqueMembers: Array(props))` constructor. The same outer `try`
covers construction and the unchanged `.canonicalJSONData(limits: .unbounded)`
validation. The store transaction, authenticated program, identity checks,
state replacement, revision, callback nonces and receipt are untouched.

## Focused real compiler proof

The primary Scaleway Mac compiled the unchanged real value/error source files
plus the verbatim error-payload declarations, then compiled the exact corrected
statement in a separate consumer. Execution verified property and exact UTF-8
key retention, a canonical JSON round trip and existing non-finite rejection.
All three commands succeeded in under four seconds. Inputs, commands, toolchain,
capacity observation and raw outputs are retained here.

This is an Xcode 27.0 / Swift 6.4 source-closure proof, not a complete package,
store, app, simulator or WidgetKit acceptance result. The required Xcode 27.2
app gate remains root-owned. MAIN13 still failed before AI and all 52 cases ran;
the two downstream widget consumer modules had not reached Swift compilation.
