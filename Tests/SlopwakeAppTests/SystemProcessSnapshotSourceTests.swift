@testable import slopwake
import XCTest

final class SystemProcessSnapshotSourceTests: XCTestCase {
    func testAbsoluteCPUTimeIsConvertedToNanoseconds() {
        XCTAssertEqual(
            SystemProcessSnapshotSource.nanoseconds(
                fromAbsoluteTime: 3,
                numerator: 125,
                denominator: 3
            ),
            125
        )
    }

    func testInvalidOrOverflowingTimebaseCannotCreateACounter() {
        XCTAssertNil(
            SystemProcessSnapshotSource.nanoseconds(
                fromAbsoluteTime: 1,
                numerator: 125,
                denominator: 0
            )
        )
        XCTAssertNil(
            SystemProcessSnapshotSource.nanoseconds(
                fromAbsoluteTime: .max,
                numerator: 125,
                denominator: 3
            )
        )
    }
}
