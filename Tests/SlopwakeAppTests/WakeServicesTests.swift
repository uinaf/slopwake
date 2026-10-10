@testable import slopwake
import XCTest

@MainActor
final class WakeServicesTests: XCTestCase {
    func testHostedAppDoesNotCreateLiveServices() {
        XCTAssertNil(WakeServices.shared)
    }
}
