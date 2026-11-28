# Navigate and decode within one read scope

Group related field reads under one finite cumulative budget.

```swift
import JSON

let response = try JSONParser().parse(
    #"{"users":[{"name":"Ada","age":9007199254740993,"nickname":null}]}"#)
let report = try response.readWithReport { root in
    let user = try root["users"][0]
    let name = try user["name"].requiredString()
    let age = try user["age"].requiredInteger(as: UInt64.self)
    return (name, age, try user.stringPresence(of: "nickname"))
}
```

``JSONReadCursor`` brackets require a present member or valid array element. An
integer bracket never means a numeric object key. Keys are literal decoded scalar
sequences: slash, tilde, empty and dotted keys need no special bracket syntax.
Use parent presence to distinguish absence, explicit null and a typed non-null
value. Wrong kinds and incompatible models throw; they do not select a default.

Required integer conversion preserves values above 2^53 and checks the target range.
For floating point, choose the fidelity explicitly: decimal 0.1 rejects
`requiredDouble(policy: .exact)` and permits finite `.rounded` conversion.
Native model projection uses `decode(_:coding:)`; native Float/Double models keep
their existing finite-rounding semantics.

Root admission runs once. Owned path/copy/search/conversion/model work shares one
ledger, including prior work when coding limits tighten it. The report's core domain
and numeric counters describe owned operations, not caller instructions or RSS.
Catching resource failure or cancellation inside the callback cannot produce success.

Cursors are synchronous and non-Sendable. Escaped handles become unusable, and the
scope releases its root and source references. Return ordinary values or models from
the callback. Later direct collection operations follow their existing contracts.
``JSONAccessFailure`` describes ordinary failures with a complete bounded typed path;
``JSONDocument`` reads can add coherent source locations. Replaced roots have none.
