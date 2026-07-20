import Foundation

@_silgen_name("HanlinNodeStart")
private func HanlinNodeStart(_ argumentsJSON: UnsafePointer<CChar>) -> Int32

enum NodeRuntimeBridge {
    static func start(arguments: [String]) throws {
        let data = try JSONEncoder().encode(arguments)
        guard let json = String(data: data, encoding: .utf8) else {
            throw MCPError.runtimeUnavailable("Could not encode Node launch arguments.")
        }
        let result = json.withCString(HanlinNodeStart)
        guard result == 0 || result == 1 else {
            throw MCPError.runtimeUnavailable("NodeMobile rejected launch arguments (\(result)).")
        }
    }
}
