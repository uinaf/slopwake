import AppKit
import ServiceManagement
import SlopwakeCore
@testable import slopwake
import XCTest

@MainActor
final class WakeMenuModelTests: XCTestCase {
    func testDetectorMenuGroupsCoverEverySurfaceExactlyOnce() {
        let groupedSurfaces = DetectorMenuGroup.all.flatMap { [$0.desktop, $0.cli] }

        XCTAssertEqual(Set(groupedSurfaces), Set(AgentSurface.allCases))
        XCTAssertEqual(groupedSurfaces.count, Set(groupedSurfaces).count)
    }

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
            ]
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
            sources: [AutomaticWakeSource(surface: .codexCLI, evidence: .activeProcess)]
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

    func testNotFoundMainAppCanRegisterAtLogin() throws {
        let service = FakeLoginItemService(status: .notFound)
        let controller = LoginItemController(service: service)

        XCTAssertEqual(controller.state, .disabled)

        try controller.setEnabled(true)

        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(controller.state, .enabled)
    }

    func testFailedLoginItemEnableClearsAfterExternalStateCatchesUp() {
        withModel { model, _, _, _, loginItem in
            loginItem.setError = TestError.unavailable
            model.setStartsAtLogin(true)
            XCTAssertEqual(model.loginItemMessage, "could not change start at login")

            loginItem.state = .enabled
            model.refreshExternalState()

            XCTAssertTrue(model.startsAtLogin)
            XCTAssertTrue(model.preferences.startsAtLogin)
            XCTAssertNil(model.loginItemMessage)
        }
    }

    func testFailedLoginItemDisableClearsAfterExternalStateCatchesUp() {
        withModel(loginItemState: .enabled) { model, _, _, _, loginItem in
            loginItem.setError = TestError.unavailable
            model.setStartsAtLogin(false)
            XCTAssertEqual(model.loginItemMessage, "could not change start at login")

            loginItem.state = .disabled
            model.refreshExternalState()

            XCTAssertFalse(model.startsAtLogin)
            XCTAssertFalse(model.preferences.startsAtLogin)
            XCTAssertNil(model.loginItemMessage)
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

    func testDeniedLoginItemRegistrationReportsRequiredApproval() {
        withModel { model, _, _, _, loginItem in
            loginItem.stateOnError = .requiresApproval
            loginItem.setError = TestError.unavailable

            model.setStartsAtLogin(true)

            XCTAssertTrue(model.startsAtLogin)
            XCTAssertTrue(model.preferences.startsAtLogin)
            XCTAssertEqual(
                model.loginItemMessage,
                "start at login needs approval in System Settings"
            )
        }
    }

    func testLoginItemSettingsActionUsesController() {
        withModel { model, _, _, _, loginItem in
            model.openLoginItemSettings()

            XCTAssertEqual(loginItem.openSettingsCount, 1)
        }
    }

    func testBatteryCutoffIsNormalizedAtTheMenuBoundary() {
        withModel { model, _, _, _, _ in
            model.setBatteryCutoffPercentage(1)

            XCTAssertEqual(model.preferences.batteryCutoffPercentage, 5)
        }
    }

    func testElapsedStatusAndMenuWidthStayFrozenWhileMenuIsTracked() {
        var time = MonotonicTime(seconds: 0)
        let automatic = AutomaticWakeState(
            shouldHold: true,
            sources: [AutomaticWakeSource(surface: .codexDesktop, evidence: .activeProcess)]
        )
        withModel(automaticState: automatic, currentTime: { time }) { model, _, _, _, _ in
            XCTAssertEqual(model.statusText, "awake · automatic · 0:00 elapsed")

            NotificationCenter.default.post(
                name: NSMenu.didBeginTrackingNotification,
                object: NSMenu()
            )
            time = MonotonicTime(seconds: 600)
            model.clockDidTick()

            XCTAssertEqual(model.statusText, "awake · automatic · 0:00 elapsed")

            NotificationCenter.default.post(
                name: NSMenu.didEndTrackingNotification,
                object: NSMenu()
            )

            XCTAssertEqual(model.statusText, "awake · automatic · 10:00 elapsed")
        }
    }

    func testManualExpirationStillReleasesHoldWhileMenuPresentationIsFrozen() {
        var time = MonotonicTime(seconds: 0)
        withModel(currentTime: { time }) { model, controller, _, _, _ in
            model.startManualHold(.thirtyMinutes)
            XCTAssertTrue(model.isHolding)

            model.menuTrackingDidBegin()
            time = MonotonicTime(seconds: ManualHoldDuration.thirtyMinutes.rawValue)
            model.clockDidTick()

            XCTAssertFalse(controller.isHolding)
            XCTAssertTrue(model.isHolding)

            model.menuTrackingDidEnd()

            XCTAssertFalse(model.isHolding)
            XCTAssertEqual(model.statusText, "idle · sleep allowed")
        }
    }

    private func withModel(
        automaticState: AutomaticWakeState = AutomaticWakeState(
            shouldHold: false,
            sources: []
        ),
        loginItemState: LoginItemState = .disabled,
        currentTime: @escaping @MainActor () -> MonotonicTime = {
            MonotonicTime(seconds: UInt64(ProcessInfo.processInfo.systemUptime))
        },
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
            loginItemController: loginItemController,
            currentTime: currentTime
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
    var stateOnError: LoginItemState?
    private(set) var openSettingsCount = 0

    init(state: LoginItemState) {
        self.state = state
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setError {
            if let stateOnError {
                state = stateOnError
            }
            throw setError
        }
        state = enabled ? enabledState : .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    private(set) var registerCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }
}

private enum TestError: Error {
    case unavailable
}
