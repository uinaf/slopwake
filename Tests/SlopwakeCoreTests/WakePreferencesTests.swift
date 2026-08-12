import Foundation
import SlopwakeCore
import XCTest

final class WakePreferencesTests: XCTestCase {
    func testFreshPreferencesUseSafeDefaults() {
        withDefaults { defaults in
            let preferences = WakePreferences.load(from: defaults)

            XCTAssertEqual(preferences.enabledSurfaces, Set(AgentSurface.allCases))
            XCTAssertFalse(preferences.preventsDisplaySleep)
            XCTAssertEqual(preferences.batteryCutoffPercentage, 15)
            XCTAssertFalse(preferences.startsAtLogin)
        }
    }

    func testLegacyAutomaticToggleMigratesToSixIndependentValues() {
        withDefaults { defaults in
            defaults.set(false, forKey: "automatic-detection-enabled")

            let migrated = WakePreferences.load(from: defaults)
            XCTAssertTrue(migrated.enabledSurfaces.isEmpty)
            XCTAssertNil(defaults.object(forKey: "automatic-detection-enabled"))

            var updated = migrated
            updated.enabledSurfaces.insert(.codexCLI)
            updated.save(to: defaults)
            let reloaded = WakePreferences.load(from: defaults)
            XCTAssertEqual(reloaded.enabledSurfaces, Set([.codexCLI]))
        }
    }

    func testPreferencesRoundTripWithoutSessionState() {
        withDefaults { defaults in
            let preferences = WakePreferences(
                enabledSurfaces: Set([.claudeDesktop, .cursorCLI]),
                preventsDisplaySleep: true,
                batteryCutoffPercentage: nil,
                startsAtLogin: true
            )
            preferences.save(to: defaults)

            XCTAssertEqual(WakePreferences.load(from: defaults), preferences)
            let expectedKeys = Set([
                    "preferences.schema-version",
                    "detector.codexDesktop.enabled",
                    "detector.codexCLI.enabled",
                    "detector.claudeDesktop.enabled",
                    "detector.claudeCLI.enabled",
                    "detector.cursorDesktop.enabled",
                    "detector.cursorCLI.enabled",
                    "prevents-display-sleep",
                    "battery-cutoff-percentage",
                    "starts-at-login",
                ])
            let storedKeys = Set(defaults.dictionaryRepresentation().keys.filter { key in
                key.hasPrefix("detector.") || expectedKeys.contains(key)
            })
            XCTAssertEqual(storedKeys, expectedKeys)
        }
    }

    func testOutOfRangeBatteryCutoffIsNormalized() {
        XCTAssertEqual(WakePreferences(batteryCutoffPercentage: 1).batteryCutoffPercentage, 5)
        XCTAssertEqual(WakePreferences(batteryCutoffPercentage: 99).batteryCutoffPercentage, 30)
        XCTAssertNil(WakePreferences(batteryCutoffPercentage: 0).batteryCutoffPercentage)
    }

    func testLoadingCurrentPreferencesDoesNotRewriteFutureSchemaVersion() {
        withDefaults { defaults in
            defaults.set(2, forKey: "preferences.schema-version")
            defaults.set(false, forKey: "detector.codexCLI.enabled")

            let loaded = WakePreferences.load(from: defaults)

            XCTAssertFalse(loaded.enabledSurfaces.contains(.codexCLI))
            XCTAssertEqual(defaults.integer(forKey: "preferences.schema-version"), 2)
            loaded.save(to: defaults)
            XCTAssertEqual(defaults.integer(forKey: "preferences.schema-version"), 2)
        }
    }

    private func withDefaults(_ operation: (UserDefaults) -> Void) {
        let suiteName = "dev.uinaf.slopwake.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create isolated UserDefaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        operation(defaults)
    }
}
