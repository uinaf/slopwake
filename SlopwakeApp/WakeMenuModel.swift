import AppKit
import Observation
import SlopwakeCore

@MainActor
@Observable
final class WakeMenuModel {
    private(set) var isHolding: Bool
    private(set) var automaticState: AutomaticWakeState
    private(set) var policyState: WakePolicyState
    private(set) var wakeErrorMessage: String?
    private(set) var loginItemMessage: String?
    private(set) var loginItemState: LoginItemState

    var preferences: WakePreferences {
        preferenceStore.value
    }

    var startsAtLogin: Bool {
        loginItemState == .enabled || loginItemState == .requiresApproval
    }

    var statusText: String {
        if policyState.shouldHold && !isHolding {
            return "idle · wake hold unavailable"
        }
        if !policyState.shouldHold && isHolding {
            return "awake · releasing hold"
        }
        return policyState.status.displayText
    }

    var errorMessage: String? {
        wakeErrorMessage ?? loginItemMessage
    }

    @ObservationIgnored
    private let controller: any WakeHolding
    @ObservationIgnored
    private let automaticMonitor: any AutomaticWakeMonitoring
    @ObservationIgnored
    private let batteryMonitor: any BatteryMonitoring
    @ObservationIgnored
    private let preferenceStore: WakePreferencesStore
    @ObservationIgnored
    private let loginItemController: any LoginItemControlling
    @ObservationIgnored
    private var policy = WakePolicy()
    @ObservationIgnored
    private var clockTask: Task<Void, Never>?
    @ObservationIgnored
    private var wakeHoldFailed = false
    @ObservationIgnored
    private var loginItemActionFailed = false

    init(
        controller: any WakeHolding,
        automaticMonitor: any AutomaticWakeMonitoring,
        batteryMonitor: any BatteryMonitoring,
        preferenceStore: WakePreferencesStore,
        loginItemController: any LoginItemControlling,
        startsServices: Bool = true
    ) {
        self.controller = controller
        self.automaticMonitor = automaticMonitor
        self.batteryMonitor = batteryMonitor
        self.preferenceStore = preferenceStore
        self.loginItemController = loginItemController
        isHolding = controller.isHolding
        automaticState = automaticMonitor.state
        loginItemState = loginItemController.state
        policyState = WakePolicyState(
            shouldHold: false,
            status: .idle,
            sources: []
        )

        automaticMonitor.enabledSurfaces = preferenceStore.value.enabledSurfaces
        controller.stateChangeHandler = { [weak self] in
            guard let self else {
                return
            }
            isHolding = self.controller.isHolding
            reconcileWakeHold()
        }
        controller.unexpectedTerminationHandler = { [weak self] in
            self?.wakeHoldFailed = true
            self?.wakeErrorMessage = "wake hold stopped unexpectedly"
        }
        automaticMonitor.stateChangeHandler = { [weak self] state in
            self?.automaticState = state
            self?.reconcileWakeHold()
        }
        batteryMonitor.stateChangeHandler = { [weak self] _ in
            self?.reconcileWakeHold()
        }
        if startsServices {
            automaticMonitor.start()
            batteryMonitor.start()
            refreshLoginItemState()
            startClock()
            reconcileWakeHold()
        }
    }

    func startManualHold(_ duration: ManualHoldDuration) {
        policy.startManualHold(duration, at: now)
        reconcileWakeHold()
    }

    func endManualHold() {
        policy.endManualHold()
        reconcileWakeHold()
    }

    func retryWakeHold() {
        wakeHoldFailed = false
        reconcileWakeHold()
    }

    func refreshExternalState() {
        refreshLoginItemState()
    }

    func pauseAutomatic(_ duration: AutomaticPauseDuration) {
        policy.pauseAutomatic(for: duration, at: now)
        reconcileWakeHold()
    }

    func pauseAutomaticUntilResumed() {
        policy.pauseAutomaticUntilResumed(at: now)
        reconcileWakeHold()
    }

    func resumeAutomatic() {
        policy.resumeAutomatic()
        reconcileWakeHold()
    }

    func setSurface(_ surface: AgentSurface, enabled: Bool) {
        preferenceStore.setSurface(surface, enabled: enabled)
        let enabledSurfaces = preferenceStore.value.enabledSurfaces
        automaticMonitor.enabledSurfaces = enabledSurfaces
        automaticState = automaticMonitor.state.restricted(to: enabledSurfaces)
        reconcileWakeHold()
    }

    func setPreventsDisplaySleep(_ enabled: Bool) {
        preferenceStore.setPreventsDisplaySleep(enabled)
        reconcileWakeHold()
    }

    func setBatteryCutoffPercentage(_ percentage: Int?) {
        preferenceStore.setBatteryCutoffPercentage(percentage)
        reconcileWakeHold()
    }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            loginItemState = loginItemController.state
            guard startsAtLogin == enabled else {
                loginItemActionFailed = true
                loginItemMessage = "could not change start at login"
                return
            }
            loginItemActionFailed = false
            preferenceStore.setStartsAtLogin(enabled)
            if loginItemState == .requiresApproval {
                loginItemMessage = "start at login needs approval in System Settings"
            } else {
                loginItemMessage = nil
            }
        } catch {
            loginItemState = loginItemController.state
            loginItemActionFailed = true
            loginItemMessage = "could not change start at login"
        }
    }

    func quit() {
        clockTask?.cancel()
        clockTask = nil
        automaticMonitor.stop()
        batteryMonitor.stop()
        controller.stop()
        NSApplication.shared.terminate(nil)
    }

    private var now: MonotonicTime {
        MonotonicTime(seconds: UInt64(ProcessInfo.processInfo.systemUptime))
    }

    private func startClock() {
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else {
                    return
                }
                reconcileWakeHold()
            }
        }
    }

    private func reconcileWakeHold() {
        policyState = policy.evaluate(
            automatic: automaticState,
            battery: batteryMonitor.state,
            batteryCutoffPercentage: preferenceStore.value.batteryCutoffPercentage,
            at: now
        )
        do {
            if policyState.shouldHold {
                guard !wakeHoldFailed else {
                    isHolding = controller.isHolding
                    return
                }
                try controller.start(
                    preventDisplaySleep: preferenceStore.value.preventsDisplaySleep
                )
                if !wakeHoldFailed {
                    wakeErrorMessage = nil
                }
            } else {
                controller.stop()
                wakeHoldFailed = false
                wakeErrorMessage = nil
            }
        } catch {
            wakeErrorMessage = "could not start wake hold"
        }
        isHolding = controller.isHolding
    }

    private func refreshLoginItemState() {
        loginItemState = loginItemController.state
        if preferenceStore.value.startsAtLogin != startsAtLogin {
            preferenceStore.setStartsAtLogin(startsAtLogin)
        }
        guard !loginItemActionFailed else {
            return
        }
        switch loginItemState {
        case .enabled, .disabled:
            loginItemMessage = nil
        case .requiresApproval:
            loginItemMessage = "start at login needs approval in System Settings"
        case .unavailable:
            break
        }
    }
}
