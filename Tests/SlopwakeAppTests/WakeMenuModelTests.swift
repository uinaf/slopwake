import SlopwakeCore
@testable import slopwake
import XCTest

@MainActor
final class WakeMenuModelTests: XCTestCase {
    func testManualActionUpdatesHoldingStatusAndDisplayPreference() {
        withModel { model, controller, _, _, _ in
            model.startManualHold(.thirtyMinutes)

            XCTAssertTrue(model.isHolding)
            XCTAssertTrue(model.statusText.hasPrefix("awake · manual ·"))

            model.setPreventsDisplaySleep(true)
            XCTAssertEqual(controller.preventDisplaySleepInvocations.last, true)
        }
    }

    func testUnexpectedExitRecoveryClearsWakeErrorAndRestoresHolding() {
        withModel { model, controller, _, _, _ in
            model.startManualHold(.oneHour)
            controller.simulateUnexpectedExit()

            XCTAssertTrue(model.isHolding)
            XCTAssertNil(model.wakeErrorMessage)
            XCTAssertTrue(model.statusText.hasPrefix("awake · manual ·"))
        }
    }

    func testDisablingTheOnlyActiveDetectorReleasesImmediately() {
        let automatic = AutomaticWakeState(
            shouldHold: true,
            sources: [
                AutomaticWakeSource(surface: .codexCLI, evidence: .activeProcess),
            ],
            isCeilingLimited: false
        )
        withModel(automaticState: automatic) { model, controller, _, _, _ in
            XCTAssertTrue(model.isHolding)

            model.setSurface(.codexCLI, enabled: false)

            XCTAssertFalse(model.isHolding)
            XCTAssertGreaterThan(controller.stopCount, 0)
            XCTAssertFalse(model.preferences.enabledSurfaces.contains(.codexCLI))
        }
    }

    func testUnavailableLoginItemDoesNotPersistAnEnabledToggle() {
        withModel(loginItemState: .unavailable) { model, _, _, _, loginItem in
            loginItem.setError = TestError.unavailable
            model.setStartsAtLogin(true)

            XCTAssertFalse(model.startsAtLogin)
            XCTAssertFalse(model.preferences.startsAtLogin)
            XCTAssertEqual(model.loginItemMessage, "could not change start at login")
        }
    }

    private func withModel(
        automaticState: AutomaticWakeState = AutomaticWakeState(
            shouldHold: false,
            sources: [],
            isCeilingLimited: false
        ),
        loginItemState: LoginItemState = .disabled,
        operation: (
            WakeMenuModel,
            FakeWakeController,
            FakeAutomaticMonitor,
            FakeBatteryMonitor,
            FakeLoginItemController
        ) -> Void
    ) {
        let suiteName = "dev.uinaf.slopwake.app-tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create isolated UserDefaults")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let controller = FakeWakeController()
        let automaticMonitor = FakeAutomaticMonitor(state: automaticState)
        let batteryMonitor = FakeBatteryMonitor()
        let loginItemController = FakeLoginItemController(state: loginItemState)
        let model = WakeMenuModel(
            controller: controller,
            automaticMonitor: automaticMonitor,
            batteryMonitor: batteryMonitor,
            preferenceStore: WakePreferencesStore(defaults: defaults),
            loginItemController: loginItemController
        )
        operation(
            model,
            controller,
            automaticMonitor,
            batteryMonitor,
            loginItemController
        )
    }
}

@MainActor
private final class FakeWakeController: WakeHolding {
    var isHolding = false
    var stateChangeHandler: (() -> Void)?
    var unexpectedTerminationHandler: (() -> Void)?
    private(set) var preventDisplaySleepInvocations: [Bool] = []
    private(set) var stopCount = 0

    func start(preventDisplaySleep: Bool) throws -> Bool {
        preventDisplaySleepInvocations.append(preventDisplaySleep)
        let started = !isHolding
        isHolding = true
        return started
    }

    func stop() -> Bool {
        stopCount += 1
        let stopped = isHolding
        isHolding = false
        return stopped
    }

    func simulateUnexpectedExit() {
        isHolding = false
        unexpectedTerminationHandler?()
        stateChangeHandler?()
    }
}

@MainActor
private final class FakeAutomaticMonitor: AutomaticWakeMonitoring {
    var state: AutomaticWakeState
    var enabledSurfaces = Set(AgentSurface.allCases)
    var stateChangeHandler: ((AutomaticWakeState) -> Void)?

    init(state: AutomaticWakeState) {
        self.state = state
    }

    func start() {}
    func stop() {}
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    var state = BatteryState.unknown
    var stateChangeHandler: ((BatteryState) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class FakeLoginItemController: LoginItemControlling {
    var state: LoginItemState
    var setError: Error?

    init(state: LoginItemState) {
        self.state = state
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setError {
            throw setError
        }
        state = enabled ? .enabled : .disabled
    }
}

private enum TestError: Error {
    case unavailable
}
