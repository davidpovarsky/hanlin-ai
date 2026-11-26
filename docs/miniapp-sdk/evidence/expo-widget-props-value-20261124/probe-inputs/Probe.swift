import Foundation
import HanlinPlatformContracts

func validatePublishedProps(_ props: [String: HanlinValue]) throws {
    _ = try HanlinValue.object(HanlinObject(uniqueMembers: Array(props))).canonicalJSONData(limits: .unbounded)
}

let decomposedKey = "e\u{301}"
let props: [String: HanlinValue] = [
    "count": .integer(Int64.max),
    "nested": .object(["enabled": .bool(true), "items": .array([.null, .string("שלום")])]),
    decomposedKey: .string("exact UTF-8 key")
]
try validatePublishedProps(props)
let object = try HanlinObject(uniqueMembers: Array(props))
guard object.count == props.count,
      object.allSatisfy({ props[$0.key] == $0.value }),
      object.keys.contains(where: { $0.utf8.elementsEqual(decomposedKey.utf8) }) else {
    fatalError("Received property members changed")
}
let value = HanlinValue.object(object)
let data = try value.canonicalJSONData(limits: .unbounded)
guard try HanlinValue.decodeCanonicalJSON(data, limits: .unbounded) == value else {
    fatalError("Canonical value round trip changed properties")
}
print("REAL_PUBLICATION_CONSTRUCTION_PASS")
print("CANONICAL_ROUNDTRIP_PASS bytes=\(data.count)")
print(String(decoding: data, as: UTF8.self))
do {
    try validatePublishedProps(["invalid": .number(.nan)])
    fatalError("Non-finite value unexpectedly accepted")
} catch HanlinContractError.invalidNumber {
    print("NONFINITE_VALIDATION_PRESERVED")
}
