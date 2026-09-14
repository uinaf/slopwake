import SlopwakeCore
import Synchronization
@testable import slopwake
import XCTest

@MainActor
final class AutomaticWakeMonitorTests: XCTestCase {
    func testHeadlessCLISnapshotPublishesHoldState() async {
        let snapshotSource = FakeProcessSnapshotSource(
            result: SystemProcessSnapshot(
                processes: [sample(pid: 10, name: "codex")],
                unavailableProcessIdentifiers: []
            )
        )
        let monitor = AutomaticWakeMonitor(
            snapshotSource: snapshotSource,
            bundleIdentifiers: { [:] },
            currentTime: { MonotonicTime(seconds: 0) }
        )
        var publications = 0
        monitor.stateChangeHandler = { _ in publications += 1 }

        await monitor.poll()

        XCTAssertEqual(
            monitor.state,
            AutomaticWakeState(
                shouldHold: true,
                sources: [AutomaticWakeSource(surface: .codexCLI, evidence: .activeProcess)]
            )
        )
        XCTAssertEqual(publications, 1)

        await monitor.poll()
        XCTAssertEqual(publications, 1)
    }

    func testDisabledSurfaceDoesNotPublishHoldState() async {
        let snapshotSource = FakeProcessSnapshotSource(
            result: SystemProcessSnapshot(
                processes: [sample(pid: 10, name: "codex")],
                unavailableProcessIdentifiers: []
            )
        )
        let monitor = AutomaticWakeMonitor(
            snapshotSource: snapshotSource,
            bundleIdentifiers: { [:] },
            currentTime: { MonotonicTime(seconds: 0) }
        )
        monitor.enabledSurfaces = []
        var publications = 0
        monitor.stateChangeHandler = { _ in publications += 1 }

        await monitor.poll()

        XCTAssertFalse(monitor.state.shouldHold)
        XCTAssertEqual(publications, 0)
    }

    func testSamplingFailureRetainsHoldWithoutCallingNSWorkspace() async {
        let snapshotSource = FakeProcessSnapshotSource(
            result: SystemProcessSnapshot(
                processes: [sample(pid: 10, name: "codex")],
                unavailableProcessIdentifiers: []
            )
        )
        let clock = Mutex(MonotonicTime(seconds: 0))
        let monitor = AutomaticWakeMonitor(
            snapshotSource: snapshotSource,
            bundleIdentifiers: { [:] },
            currentTime: { clock.withLock { $0 } }
        )
        await monitor.poll()
        XCTAssertTrue(monitor.state.shouldHold)

        snapshotSource.setResult(nil)
        clock.withLock { $0 = MonotonicTime(seconds: 5) }
        await monitor.poll()

        XCTAssertTrue(monitor.state.shouldHold)
        XCTAssertEqual(monitor.state.sources.map(\.surface), [.codexCLI])
    }
}

private final class FakeProcessSnapshotSource: ProcessSnapshotSourcing {
    private let storage: Mutex<SystemProcessSnapshot?>

    init(result: SystemProcessSnapshot?) {
        storage = Mutex(result)
    }

    func setResult(_ result: SystemProcessSnapshot?) {
        storage.withLock { $0 = result }
    }

    func snapshot(bundleIdentifiers: [pid_t: String]) -> SystemProcessSnapshot? {
        storage.withLock { $0 }
    }
}

private func sample(pid: Int32, name: String) -> AgentProcessSample {
    AgentProcessSample(
        identity: AgentProcessIdentity(processIdentifier: pid, startTimeMicroseconds: 1),
        executableName: name,
        hasControllingTerminal: false,
        cumulativeCPUTimeNanoseconds: 0
    )
}
