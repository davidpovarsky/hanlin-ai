# Quick entry points and presence

Start with the JSON value type for common tasks, then use the owning facade for
reports, source documents, writing, coding strategies or a reusable configuration.
These additive E2 methods are in development until their feature branch merges.

```swift
let source = #"{"n":9007199254740993,"label":null}"#
let before = try JSONParser().parse(source)
let after = try JSON.parse(source)
precondition(before == after)
let built = try JSON.buildObject { try $0.append("n", value: 42) }
let builtBefore = JSON.object(try JSONObject.build { try $0.append("n", value: 42) })
precondition(built == builtBefore)
let decimal = try JSON.number(parsing: "0.1")
let decimalBefore = JSON.number(try JSONNumber(parsing: "0.1"))
precondition(decimal == decimalBefore)
let pointer = try JSONPointer(parsing: "/n")
let selected = try after.value(at: pointer)
let selectedBefore = try pointer.resolve(in: before)
precondition(selected == selectedBefore)
let object = try after.read { try $0.requiredObject() }
precondition(object.containsKey("label") && !object.containsKey("missing"))
let label = try after.presence(of: "label").map { try $0.decode(String.self) }
precondition(label.fold(absent: { "missing" }, null: { "null" }, value: { $0 }) == "null")
let scoped = try after.readWithReport { try $0["n"].requiredInteger(as: UInt64.self) }
precondition(scoped.result == 9_007_199_254_740_993 && scoped.statistics[.workUnits] > 0)
```

`JSON.parse` forwards each input kind and its options to the same parser overload.
String/Data parsing charges the delegate's owned input copy; a byte array follows
its own existing admission boundary. Do not compare counters across input kinds.
`buildObject` borrows the same noncopyable accumulator as `JSONObject.build` and
wraps its admitted result without another admission or meter. Callback work is
caller work. `number(parsing:)` keeps strict decimal tokens and their lexemes.

Pointer parsing is an explicit separate operation. `value(at:)` delegates only
resolution and does not hide a parse with a fresh quota. Use `readWithReport` for
selection, conversion and native model projection under one scoped meter.
An escaped read cursor remains invalid after scope exit; no new cursor API is added.

`containsKey` is an unmetered exact-key lookup. Null is present. Literals use
JSONKey; wrap a dynamic String explicitly in JSONKey. Swift String dictionaries
cannot preserve all JSON-distinct scalar keys. No dictionary bridge is added.
`map` transforms only a non-null payload; `fold` runs exactly one branch. Their
throwing callbacks propagate unchanged and are caller-owned work.

Keep `JSON.number(JSONNumber(integer: dynamic))` for trusted integers. A generic
same-named overload was deferred because Swift 6.4 changed the selected declaration
for existing `.number(42)` calls. No nested Pointer/schema/HTML aliases are added.
