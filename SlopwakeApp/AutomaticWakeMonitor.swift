import AppKit
import Foundation
import SlopwakeCore

@MainActor
final class AutomaticWakeMonitor {
    private let snapshotSource: any ProcessSnapshotSourcing
    private let bundleIdentifiers: @MainActor () -> [pid_t: String]
    private let currentTime: @MainActor () -> MonotonicTime
    private var detector: AgentActivityDetector
    private var pollingTask: Task<Void, Never>?

    var enabledSurfaces = Set(AgentSurface.allCases)

    private(set) var state = AutomaticWakeState(
        shouldHold: false,
        sources: []
    )
    var stateChangeHandler: ((AutomaticWakeState) -> Void)?

    init(
        snapshotSource: any ProcessSnapshotSourcing = SystemProcessSnapshotSource(),
        detector: AgentActivityDetector = AgentActivityDetector(),
        bundleIdentifiers: @escaping @MainActor () -> [pid_t: String] = {
            var identifiers: [pid_t: String] = [:]
            for application in NSWorkspace.shared.runningApplications {
                if let bundleIdentifier = application.bundleIdentifier {
                    identifiers[application.processIdentifier] = bundleIdentifier
                }
            }
            return identifiers
        },
        currentTime: @escaping @MainActor () -> MonotonicTime = {
            MonotonicTime(seconds: UInt64(ProcessInfo.processInfo.systemUptime))
        }
    ) {
        self.snapshotSource = snapshotSource
        self.detector = detector
        self.bundleIdentifiers = bundleIdentifiers
        self.currentTime = currentTime
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

    func poll() async {
        let bundleIdentifiers = bundleIdentifiers()
        let snapshotSource = snapshotSource
        let sampledProcesses = await Task.detached {
            snapshotSource.snapshot(bundleIdentifiers: bundleIdentifiers)
        }.value
        guard !Task.isCancelled else {
            return
        }
        let now = currentTime()
        let nextState: AutomaticWakeState
        if let snapshot = sampledProcesses {
            nextState = detector.update(
                processes: snapshot.processes,
                at: now,
                unavailableProcessIdentifiers: snapshot.unavailableProcessIdentifiers,
                enabledSurfaces: enabledSurfaces
            )
        } else {
            nextState = detector.tickWithoutSnapshot(
                at: now,
                enabledSurfaces: enabledSurfaces
            )
        }
        guard nextState != state else {
            return
        }
        state = nextState
        stateChangeHandler?(nextState)
    }
}
