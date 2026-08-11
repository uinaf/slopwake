import AppKit
import Foundation
import SlopwakeCore

@MainActor
final class AutomaticWakeMonitor {
    private let snapshotSource: SystemProcessSnapshotSource
    private var detector: AgentActivityDetector
    private var pollingTask: Task<Void, Never>?

    var enabledSurfaces = Set(AgentSurface.allCases)

    private(set) var state = AutomaticWakeState(
        shouldHold: false,
        sources: [],
        isCeilingLimited: false
    )
    var stateChangeHandler: ((AutomaticWakeState) -> Void)?

    init(
        snapshotSource: SystemProcessSnapshotSource = SystemProcessSnapshotSource(),
        detector: AgentActivityDetector = AgentActivityDetector()
    ) {
        self.snapshotSource = snapshotSource
        self.detector = detector
    }

    func start() {
        guard pollingTask == nil else {
            return
        }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard !Task.isCancelled, let self else {
                    return
                }
                await poll()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() async {
        var bundleIdentifiers: [pid_t: String] = [:]
        for application in NSWorkspace.shared.runningApplications {
            if let bundleIdentifier = application.bundleIdentifier {
                bundleIdentifiers[application.processIdentifier] = bundleIdentifier
            }
        }
        let snapshotSource = snapshotSource
        let sampledProcesses = await Task.detached {
            snapshotSource.snapshot(bundleIdentifiers: bundleIdentifiers)
        }.value
        guard !Task.isCancelled else {
            return
        }
        let now = MonotonicTime(seconds: UInt64(ProcessInfo.processInfo.systemUptime))
        let nextState: AutomaticWakeState
        if let snapshot = sampledProcesses {
            nextState = detector.update(
                processes: snapshot.processes,
                at: now,
                unavailableProcessIdentifiers: snapshot.unavailableProcessIdentifiers,
                enabledSurfaces: enabledSurfaces
            )
        } else {
            nextState = detector.tickWithoutSnapshot(at: now)
        }
        guard nextState != state else {
            return
        }
        state = nextState
        stateChangeHandler?(nextState)
    }
}
