import Foundation
import Security

let key = "com.apple.security.app-sandbox"
var result: [String: Any] = [
    "status": "PUBLIC_SECTASK_READ_ONLY_DIAGNOSTIC",
    "entitlement": key,
    "processID": ProcessInfo.processInfo.processIdentifier,
    "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    "sourceContext": "b84d5ffb1c52361ac884a967f13e5500efe3d232",
    "boundary": "Read only for this native Swift CLI process; no entitlement, signing, app or test source changes."
]
if let task = SecTaskCreateFromSelf(nil) {
    result["taskCreated"] = true
    var error: Unmanaged<CFError>?
    let value = SecTaskCopyValueForEntitlement(task, key as CFString, &error)
    result["valuePresent"] = value != nil
    if let value {
        result["valueTypeID"] = CFGetTypeID(value)
        result["isBoolean"] = CFGetTypeID(value) == CFBooleanGetTypeID()
        if let number = value as? NSNumber { result["booleanValue"] = number.boolValue }
        result["valueDescription"] = String(describing: value)
    }
    if let actual = error?.takeRetainedValue() {
        result["errorPresent"] = true
        result["error"] = [
            "domain": CFErrorGetDomain(actual) as String,
            "code": CFErrorGetCode(actual),
            "description": CFErrorCopyDescription(actual) as String,
        ]
    } else {
        result["errorPresent"] = false
        result["entitlementAbsentWithoutError"] = value == nil
    }
} else {
    result["taskCreated"] = false
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try data.write(to: output, options: .atomic)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
