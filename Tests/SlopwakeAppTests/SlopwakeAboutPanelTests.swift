import AppKit
@testable import slopwake
import XCTest

@MainActor
final class SlopwakeAboutPanelTests: XCTestCase {
    func testCreditsLinkToProjectRepository() {
        let credits = SlopwakeAboutPanel.credits
        let linkRange = (credits.string as NSString).range(of: "View on GitHub")

        XCTAssertNotEqual(linkRange.location, NSNotFound)
        guard linkRange.location != NSNotFound else {
            return
        }

        XCTAssertEqual(
            credits.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://github.com/uinaf/slopwake")
        )
    }
}
