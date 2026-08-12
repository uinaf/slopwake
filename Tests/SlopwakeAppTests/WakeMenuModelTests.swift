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

    func testUnexpectedExitReportsErrorWithoutRespawning() {
        withModel { model, controller, automatic, _, _ in
            model.startManualHold(.oneHour)
            controller.simulateUnexpectedExit()
            automatic.publish(automatic.state)

            XCTAssertFalse(model.isHolding)
            XCTAssertEqual(model.wakeErrorMessage, "wake hold stopped unexpectedly")
            XCTAssertEqual(model.statusText, "idle · wake hold unavailable")
            XCTAssertEqual(controller.startCount, 1)

            model.retryWakeHold()
            XCTAssertTrue(model.isHolding)
            XCTAssertNil(model.wakeErrorMessage)
            XCTAssertEqual(controller.startCount, 2)
        }
    }

    func testLaunchFailureRequiresExplicitRetry() {
        withModel { model, controller, automatic, _, _ in
            controller.startError = TestError.unavailable
            model.startManualHold(.oneHour)
            automatic.publish(automatic.state)
            automatic.publish(automatic.state)

            XCTAssertFalse(model.isHolding)
            XCTAssertEqual(model.wakeErrorMessage, "could not start wake hold")
            XCTAssertEqual(controller.startCount, 1)

            controller.startError = nil
            model.retryWakeHold()

            XCTAssertTrue(model.isHolding)
            XCTAssertNil(model.wakeErrorMessage)
            XCTAssertEqual(controller.startCount, 2)
        }
    }

    func testExitObservedDuringReconcileKeepsRetryMessageVisible() {
        withModel { model, controller, automatic, _, _ in
            model.startManualHold(.oneHour)
            controller.observeUnexpectedExitOnNextStart = true

            automatic.publish(automatic.state)

            XCTAssertFalse(model.isHolding)
            XCTAssertEqual(model.wakeErrorMessage, "wake hold stopped unexpectedly")
            XCTAssertEqual(model.statusText, "idle · wake hold unavailable")
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

    func testReenablingDetectorRestoresCurrentMonitorEvidenceImmediately() {
        let automatic = AutomaticWakeState(
            shouldHold: true,
            sources: [AutomaticWakeSource(surface: .codexCLI, evidence: .activeProcess)],
            isCeilingLimited: false
        )
        withModel(automaticState: automatic) { model, _, _, _, _ in
            model.setSurface(.codexCLI, enabled: false)
            XCTAssertFalse(model.isHolding)

            model.setSurface(.codexCLI, enabled: true)
            XCTAssertTrue(model.isHolding)
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

    func testSuccessfulLoginItemChangePersistsTheLiveState() {
        withModel { model, _, _, _, loginItem in
            model.setStartsAtLogin(true)

            XCTAssertEqual(loginItem.state, .enabled)
            XCTAssertTrue(model.startsAtLogin)
            XCTAssertTrue(model.preferences.startsAtLogin)
            XCTAssertNil(model.loginItemMessage)
        }
    }

    func testLoginItemApprovalMessageClearsAfterApproval() {
        withModel(loginItemState: .requiresApproval) { model, _, _, _, loginItem in
            loginItem.enabledState = .requiresApproval
            model.setStartsAtLogin(true)
            XCTAssertEqual(
                model.loginItemMessage,
                "start at login needs approval in System Settings"
            )

            loginItem.state = .enabled
            loginItem.enabledState = .enabled
            model.setStartsAtLogin(true)
            XCTAssertNil(model.loginItemMessage)
        }
    }

    func testBatteryCutoffIsNormalizedAtTheMenuBoundary() {
        withModel { model, _, _, _, _ in
            model.setBatteryCutoffPercentage(1)

            XCTAssertEqual(model.preferences.batteryCutoffPercentage, 5)
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
    private(set) var startCount = 0
    var observeUnexpectedExitOnNextStart = false
    var startError: Error?

    func start(preventDisplaySleep: Bool) throws -> Bool {
        startCount += 1
        if let startError {
            throw startError
        }
        if observeUnexpectedExitOnNextStart {
            observeUnexpectedExitOnNextStart = false
            isHolding = false
            unexpectedTerminationHandler?()
            stateChangeHandler?()
            return false
        }
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

    func publish(_ state: AutomaticWakeState) {
        self.state = state
        stateChangeHandler?(state)
    }
}

@MainActor
private final class FakeBatteryMonitor: BatteryMonitoring {
    var state = BatteryState.externalPower
    var stateChangeHandler: ((BatteryState) -> Void)?

    func start() {}
    func stop() {}
}

@MainActor
private final class FakeLoginItemController: LoginItemControlling {
    var state: LoginItemState
    var setError: Error?
    var enabledState: LoginItemState = .enabled

    init(state: LoginItemState) {
        self.state = state
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setError {
            throw setError
        }
        state = enabled ? enabledState : .disabled
    }
}

private enum TestError: Error {
    case unavailable
}
