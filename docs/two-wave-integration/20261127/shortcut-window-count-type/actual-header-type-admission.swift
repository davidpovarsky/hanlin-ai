import XCTest
import HanlinNativeScriptCoreSupport

@MainActor
func admitOriginalReturnAndReviewedAssertionShape() {
    let commands = ["first", "second", "third"]
    for index in commands.indices.reversed() {
        let _: UInt = HanlinNativeScriptWindowFactoryRegistry.openWindowCount()
        XCTAssertEqual(HanlinNativeScriptWindowFactoryRegistry.openWindowCount(), UInt(index + 1))
    }
}
