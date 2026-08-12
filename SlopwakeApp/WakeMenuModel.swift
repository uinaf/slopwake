import AppKit
import SlopwakeCore

@MainActor
final class WakeMenuModel: ObservableObject {
    @Published private(set) var isHolding: Bool
    @Published private(set) var errorMessage: String?

    private let controller: CaffeinateController

    init(controller: CaffeinateController) {
        self.controller = controller
        isHolding = controller.isHolding
        controller.stateChangeHandler = { [weak self] in
            guard let self else {
                return
            }
            isHolding = self.controller.isHolding
        }
        controller.unexpectedTerminationHandler = { [weak self] in
            self?.errorMessage = "Wake hold stopped unexpectedly"
        }
    }

    func start() {
        do {
            try controller.start()
            errorMessage = nil
        } catch {
            errorMessage = "Could not start wake hold"
        }
        isHolding = controller.isHolding
    }

    func stop() {
        controller.stop()
        errorMessage = nil
        isHolding = controller.isHolding
    }

    func quit() {
        controller.stop()
        NSApplication.shared.terminate(nil)
    }
}
