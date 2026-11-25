import XCTest

@MainActor
final class HanlinExpoModifierOwnershipTests: XCTestCase {
    func testOnlyFirstOwnerRegistersAndOnlyLastOwnerUnregisters() {
        let ownership = HanlinExpoModifierOwnership()
        XCTAssertTrue(ownership.acquire(sessionID: "A"))
        XCTAssertFalse(ownership.acquire(sessionID: "B"))
        XCTAssertEqual(ownership.owners, ["A", "B"])
        XCTAssertFalse(ownership.release(sessionID: "B"))
        XCTAssertEqual(ownership.owners, ["A"])
        XCTAssertTrue(ownership.release(sessionID: "A"))
        XCTAssertTrue(ownership.owners.isEmpty)
    }

    func testRepeatedStartAndShutdownAreIdempotent() {
        let ownership = HanlinExpoModifierOwnership()
        XCTAssertTrue(ownership.acquire(sessionID: "A"))
        XCTAssertFalse(ownership.acquire(sessionID: "A"))
        XCTAssertEqual(ownership.owners.count, 1)
        XCTAssertTrue(ownership.release(sessionID: "A"))
        XCTAssertFalse(ownership.release(sessionID: "A"))
        XCTAssertTrue(ownership.acquire(sessionID: "A"))
    }

    func testFailedUnstartedWindowCannotUnregisterALiveWindow() {
        let ownership = HanlinExpoModifierOwnership()
        XCTAssertFalse(ownership.release(sessionID: "never-started"))
        XCTAssertTrue(ownership.acquire(sessionID: "A"))
        XCTAssertFalse(ownership.release(sessionID: "never-started"))
        XCTAssertEqual(ownership.owners, ["A"])
        XCTAssertFalse(ownership.acquire(sessionID: "B"))
        XCTAssertFalse(ownership.release(sessionID: "B"))
        XCTAssertEqual(ownership.owners, ["A"])
    }
}
