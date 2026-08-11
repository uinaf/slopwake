import AppKit
import Observation
import SlopwakeCore

@MainActor
@Observable
final class WakeMenuModel {
    private(set) var isHolding: Bool
    private(set) var manualHoldRequested = false
    private(set) var automaticState: AutomaticWakeState
    private(set) var errorMessage: String?

    @ObservationIgnored
    private let controller: CaffeinateController
    @ObservationIgnored
    private let automaticMonitor: AutomaticWakeMonitor

    init(
        controller: CaffeinateController,
        automaticMonitor: AutomaticWakeMonitor
    ) {
        self.controller = controller
        self.automaticMonitor = automaticMonitor
        isHolding = controller.isHolding
        automaticState = automaticMonitor.state
        controller.stateChangeHandler = { [weak self] in
            guard let self else {
                return
            }
            isHolding = self.controller.isHolding
        }
        controller.unexpectedTerminationHandler = { [weak self] in
            self?.errorMessage = "Wake hold stopped unexpectedly"
            self?.reconcileWakeHold()
        }
        automaticMonitor.stateChangeHandler = { [weak self] state in
            self?.automaticState = state
            self?.reconcileWakeHold()
        }
        automaticMonitor.start()
    }

    func start() {
        manualHoldRequested = true
        reconcileWakeHold()
    }

    func stop() {
        manualHoldRequested = false
        reconcileWakeHold()
    }

    func quit() {
        automaticMonitor.stop()
        controller.stop()
        NSApplication.shared.terminate(nil)
    }

    private func reconcileWakeHold() {
        let shouldHold = manualHoldRequested || automaticState.shouldHold
        do {
            if shouldHold {
                try controller.start()
            } else {
                controller.stop()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not start wake hold"
        }
        isHolding = controller.isHolding
    }
}
