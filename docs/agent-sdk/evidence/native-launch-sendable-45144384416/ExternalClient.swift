import HanlinNativeLaunchProof

// The original failing app boundary, exercised through an imported public module.
struct ExpansionBoundary: Sendable {
    var legacyLaunchRequest: NativeAppLaunchRequest?
}
func requireSendable<T: Sendable>(_ value: T) {}
func publicValueContracts(
    _ style: NativeAppPresentationStyle,
    _ route: NativeAppRoute,
    _ payload: NativeAppRoutePayload,
    _ request: NativeAppLaunchRequest
) {
    requireSendable(style)
    requireSendable(route)
    requireSendable(payload)
    requireSendable(request)
}
