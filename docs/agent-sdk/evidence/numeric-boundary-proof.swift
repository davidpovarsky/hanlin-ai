// Standalone read-only contract evidence. Compile with the ACTUAL pinned JSONValue.swift;
// no replacement provider/engine/host declarations. Not full agent/native runtime proof.
import Foundation
import HanlinPlatformContracts

private func describe(_ value: HanlinJSONValue) -> String {
    switch value {
    case .integer(let n): return "integer:\(n)"
    case .number(let n): return "number:\(n)"
    default: return "other"
    }
}

@main struct NumericBoundaryProof {
    static func main() throws {
        var observed: [[String: String]] = []
        for input in ["1", "1.0", "1e0", "9007199254740993", "9223372036854775807"] {
            let data = Data(input.utf8)
            let exact = try HanlinJSONValue.decodeCanonicalJSON(data)
            // Same pinned JSONValue Codable boundary used before the existing core tool
            // executor jsonString(input). This is an isolated boundary reproduction.
            let sdk = try JSONDecoder().decode(JSONValue.self, from: data)
            let forwarded = try JSONEncoder().encode(sdk)
            let delivered: String
            do { delivered = describe(try HanlinJSONValue.decodeCanonicalJSON(forwarded)) }
            catch { delivered = "rejected:after-SDK-numeric-normalization" }
            observed.append(["input": input, "directCanonical": describe(exact),
                             "SDKReencoded": String(decoding: forwarded, as: UTF8.self),
                             "afterSDK": delivered])
        }
        let overflow = Data("18446744073709551615".utf8)
        do {
            _ = try HanlinJSONValue.decodeCanonicalJSON(overflow)
            throw NSError(domain: "NumericBoundaryProof", code: 1, userInfo: [NSLocalizedDescriptionKey: "UInt64 overflow unexpectedly accepted as Int64"])
        } catch is HanlinContractError {
            observed.append(["input": "18446744073709551615", "directCanonical": "rejected:outside-Int64"])
        }
        guard observed[1]["directCanonical"] == "number:1.0", observed[1]["afterSDK"] == "integer:1",
              observed[3]["directCanonical"] == "integer:9007199254740993",
              observed[3]["afterSDK"] != "integer:9007199254740993" else {
            throw NSError(domain: "NumericBoundaryProof", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unexpected boundary behavior; inspect evidence before drawing conclusions"])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys]), as: UTF8.self))
    }
}
