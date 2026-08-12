import SlopwakeCore

@MainActor
protocol WakeHolding: AnyObject {
    var isHolding: Bool { get }
    var stateChangeHandler: (() -> Void)? { get set }
    var unexpectedTerminationHandler: (() -> Void)? { get set }

    @discardableResult
    func start(preventDisplaySleep: Bool) throws -> Bool

    @discardableResult
    func stop() -> Bool
}

extension CaffeinateController: WakeHolding {}

@MainActor
protocol AutomaticWakeMonitoring: AnyObject {
    var state: AutomaticWakeState { get }
    var enabledSurfaces: Set<AgentSurface> { get set }
    var stateChangeHandler: ((AutomaticWakeState) -> Void)? { get set }

    func start()
    func stop()
}

extension AutomaticWakeMonitor: AutomaticWakeMonitoring {}

@MainActor
protocol BatteryMonitoring: AnyObject {
    var state: BatteryState { get }
    var stateChangeHandler: ((BatteryState) -> Void)? { get set }

    func start()
    func stop()
}

extension BatteryMonitor: BatteryMonitoring {}
