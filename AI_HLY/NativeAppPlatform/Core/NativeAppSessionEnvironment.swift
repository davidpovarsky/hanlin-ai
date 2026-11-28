import SwiftUI

private struct NativeAppSessionEnvironmentKey: EnvironmentKey {
    static let defaultValue: NativeAppSession? = nil
}

extension EnvironmentValues {
    var nativeAppSession: NativeAppSession? {
        get { self[NativeAppSessionEnvironmentKey.self] }
        set { self[NativeAppSessionEnvironmentKey.self] = newValue }
    }
}
