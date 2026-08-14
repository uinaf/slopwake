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
    private let currentTime: @MainActor () -> MonotonicTime
    @ObservationIgnored
    private var policy = WakePolicy()
    @ObservationIgnored
    private var clockTask: Task<Void, Never>?
    @ObservationIgnored
    private var menuTrackingObserver: MenuTrackingObserver?
    @ObservationIgnored
    private var menuTrackingDepth = 0
    @ObservationIgnored
    private var latestAutomaticState: AutomaticWakeState
    @ObservationIgnored
    private var latestPolicyState: WakePolicyState
    @ObservationIgnored
    private var latestWakeErrorMessage: String?
    @ObservationIgnored
    private var wakeHoldFailed = false
    @ObservationIgnored
    private var failedLoginItemIntent: Bool?

    init(
        controller: any WakeHolding,
        automaticMonitor: any AutomaticWakeMonitoring,
        batteryMonitor: any BatteryMonitoring,
        preferenceStore: WakePreferencesStore,
        loginItemController: any LoginItemControlling,
        startsServices: Bool = true,
        currentTime: @escaping @MainActor () -> MonotonicTime = {
            MonotonicTime(seconds: UInt64(ProcessInfo.processInfo.systemUptime))
        }
    ) {
        let initialPolicyState = WakePolicyState(
            shouldHold: false,
            status: .idle,
            sources: []
        )
        self.controller = controller
        self.automaticMonitor = automaticMonitor
        self.batteryMonitor = batteryMonitor
        self.preferenceStore = preferenceStore
        self.loginItemController = loginItemController
        self.currentTime = currentTime
        isHolding = controller.isHolding
        automaticState = automaticMonitor.state
        latestAutomaticState = automaticMonitor.state
        loginItemState = loginItemController.state
        policyState = initialPolicyState
        latestPolicyState = initialPolicyState

        automaticMonitor.enabledSurfaces = preferenceStore.value.enabledSurfaces
        controller.stateChangeHandler = { [weak self] in
            guard let self else {
                return
            }
            reconcileWakeHold()
        }
        controller.unexpectedTerminationHandler = { [weak self] in
            guard let self else {
                return
            }
            wakeHoldFailed = true
            latestWakeErrorMessage = "wake hold stopped unexpectedly"
            publishPresentationState()
        }
        automaticMonitor.stateChangeHandler = { [weak self] state in
            guard let self else {
                return
            }
            latestAutomaticState = state
            reconcileWakeHold()
        }
        batteryMonitor.stateChangeHandler = { [weak self] _ in
            self?.reconcileWakeHold()
        }
        if startsServices {
            menuTrackingObserver = MenuTrackingObserver(
                didBeginTracking: { [weak self] in
                    self?.menuTrackingDidBegin()
                },
                didEndTracking: { [weak self] in
                    self?.menuTrackingDidEnd()
                }
            )
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
        latestAutomaticState = automaticMonitor.state.restricted(to: enabledSurfaces)
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
        } catch {
            // The Service Management state is authoritative even when the action throws.
        }
        refreshLoginItemState(afterAttempting: enabled)
    }

    func openLoginItemSettings() {
        loginItemController.openSystemSettings()
    }

    func quit() {
        clockTask?.cancel()
        clockTask = nil
        menuTrackingObserver = nil
        automaticMonitor.stop()
        batteryMonitor.stop()
        controller.stop()
        NSApplication.shared.terminate(nil)
    }

    func menuTrackingDidBegin() {
        menuTrackingDepth += 1
    }

    func menuTrackingDidEnd() {
        guard menuTrackingDepth > 0 else {
            return
        }
        menuTrackingDepth -= 1
        publishPresentationState()
    }

    func clockDidTick() {
        reconcileWakeHold()
    }

    private var now: MonotonicTime {
        currentTime()
    }

    private func startClock() {
        clockTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else {
                    return
                }
                clockDidTick()
            }
        }
    }

    private func reconcileWakeHold() {
        latestPolicyState = policy.evaluate(
            automatic: latestAutomaticState,
            battery: batteryMonitor.state,
            batteryCutoffPercentage: preferenceStore.value.batteryCutoffPercentage,
            at: now
        )
        do {
            if latestPolicyState.shouldHold {
                guard !wakeHoldFailed else {
                    publishPresentationState()
                    return
                }
                try controller.start(
                    preventDisplaySleep: preferenceStore.value.preventsDisplaySleep
                )
                if !wakeHoldFailed {
                    latestWakeErrorMessage = nil
                }
            } else {
                controller.stop()
                wakeHoldFailed = false
                latestWakeErrorMessage = nil
            }
        } catch {
            wakeHoldFailed = true
            latestWakeErrorMessage = "could not start wake hold"
        }
        publishPresentationState()
    }

    private func publishPresentationState() {
        guard menuTrackingDepth == 0 else {
            return
        }
        if automaticState != latestAutomaticState {
            automaticState = latestAutomaticState
        }
        if policyState != latestPolicyState {
            policyState = latestPolicyState
        }
        if wakeErrorMessage != latestWakeErrorMessage {
            wakeErrorMessage = latestWakeErrorMessage
        }
        let latestIsHolding = controller.isHolding
        if isHolding != latestIsHolding {
            isHolding = latestIsHolding
        }
    }

    private func refreshLoginItemState(afterAttempting attemptedState: Bool? = nil) {
        loginItemState = loginItemController.state
        if preferenceStore.value.startsAtLogin != startsAtLogin {
            preferenceStore.setStartsAtLogin(startsAtLogin)
        }

        if let attemptedState {
            failedLoginItemIntent = startsAtLogin == attemptedState ? nil : attemptedState
        } else if let failedLoginItemIntent, startsAtLogin == failedLoginItemIntent {
            self.failedLoginItemIntent = nil
        }

        guard failedLoginItemIntent == nil else {
            loginItemMessage = "could not change start at login"
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
