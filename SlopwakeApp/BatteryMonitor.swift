import Foundation
import IOKit.ps
import SlopwakeCore

struct BatterySnapshotSource: Sendable {
    func snapshot() -> BatteryState {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue()
                as? [CFTypeRef] else {
            return .unknown
        }

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(
                powerSourcesInfo,
                powerSource
            )?.takeUnretainedValue() as? [String: Any],
            description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else {
                continue
            }
            let current = description[kIOPSCurrentCapacityKey] as? Int
            let maximum = description[kIOPSMaxCapacityKey] as? Int
            let percentage: Int? = if let current, let maximum, maximum > 0 {
                Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                nil
            }
            let powerSource: BatteryPowerSource = switch description[kIOPSPowerSourceStateKey]
                as? String {
            case kIOPSBatteryPowerValue:
                .battery
            case kIOPSACPowerValue:
                .external
            default:
                .unknown
            }
            return BatteryState(
                percentage: percentage,
                powerSource: powerSource
            )
        }
        return .externalPower
    }
}

@MainActor
final class BatteryMonitor {
    private let snapshotSource: BatterySnapshotSource
    private var pollingTask: Task<Void, Never>?

    private(set) var state: BatteryState
    var stateChangeHandler: ((BatteryState) -> Void)?

    init(snapshotSource: BatterySnapshotSource = BatterySnapshotSource()) {
        self.snapshotSource = snapshotSource
        state = snapshotSource.snapshot()
    }

    func start() {
        guard pollingTask == nil else {
            return
        }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let source = snapshotSource
                let nextState = await Task.detached {
                    source.snapshot()
                }.value
                guard !Task.isCancelled else {
                    return
                }
                if nextState != state {
                    state = nextState
                    stateChangeHandler?(nextState)
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
