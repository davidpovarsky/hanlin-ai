import Foundation

@main
struct VerifyMessagePreviewMetrics {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let iPad = ChatMessagePreviewMetrics.fitting(preferredWidth: 560, windowWidth: 1024, windowHeight: 1366)
        check(iPad == .init(width: 480, height: 680), "iPad preview must have a bounded viewport")
        let narrow = ChatMessagePreviewMetrics.fitting(preferredWidth: 360, windowWidth: 390, windowHeight: 844)
        check(narrow == .init(width: 342, height: 680), "Compact window must keep margins")
        check(ChatMessagePreviewMetrics.fitting(preferredWidth: .nan, windowWidth: 1024, windowHeight: 768)?.width == 480,
              "A missing source measurement must not produce a one-point strip")
        for preferred in [-1.0, 0, 1, 100, 300, 10000, .infinity] {
            for window in [(320.0, 480.0), (600, 400), (2048, 2732)] {
                guard let result = ChatMessagePreviewMetrics.fitting(preferredWidth: preferred, windowWidth: window.0, windowHeight: window.1) else {
                    fatalError("Usable window incorrectly rejected")
                }
                check(result.width.isFinite && result.height.isFinite && result.width >= 260 && result.height > 0,
                      "Preview must stay finite and readable")
                check(result.width <= window.0 - 48 && result.height <= window.1 - 80 && result.height <= 680,
                      "Preview must fit both window axes regardless of message length")
            }
        }
        for dimensions in [(Double.nan, 600.0), (800.0, .infinity), (40.0, 600.0), (800.0, 0.0)] {
            check(ChatMessagePreviewMetrics.fitting(preferredWidth: 480, windowWidth: dimensions.0, windowHeight: dimensions.1) == nil,
                  "Detached or invalid windows must not be presented")
        }
        print("PASS: \(checks) message preview viewport checks")
    }
}
