import SlopwakeCore
import XCTest

final class AgentActivityDetectorTests: XCTestCase {
    func testHeadlessCLIHoldsForProcessLifetime() {
        var detector = AgentActivityDetector()
        let process = sample(pid: 10, name: "codex", terminal: false)

        XCTAssertEqual(
            detector.update(processes: [process], at: time(0)),
            state(.codexCLI, .activeProcess)
        )
        XCTAssertEqual(
            detector.update(processes: [process], at: time(10_000)),
            state(.codexCLI, .activeProcess)
        )
        XCTAssertEqual(
            detector.update(processes: [], at: time(10_001)),
            AutomaticWakeState(shouldHold: false, sources: [], isCeilingLimited: false)
        )
    }

    func testInteractiveCLIRequiresObservedCounterActivityAndExpiresAfterQuietPeriod() {
        var detector = AgentActivityDetector()
        let baseline = sample(pid: 10, name: "claude", terminal: true, cpu: 100)

        XCTAssertFalse(detector.update(processes: [baseline], at: time(0)).shouldHold)
        XCTAssertEqual(
            detector.update(
                processes: [sample(pid: 10, name: "claude", terminal: true, cpu: 50_000_100)],
                at: time(1)
            ),
            state(.claudeCLI, .activeProcess)
        )
        XCTAssertEqual(
            detector.update(
                processes: [sample(pid: 10, name: "claude", terminal: true, cpu: 50_000_100)],
                at: time(1_800)
            ),
            state(.claudeCLI, .recentActivity)
        )
        XCTAssertFalse(
            detector.update(
                processes: [sample(pid: 10, name: "claude", terminal: true, cpu: 50_000_100)],
                at: time(1_801)
            ).shouldHold
        )
    }

    func testBackgroundCPUNoiseDoesNotCountAsInteractiveActivity() {
        var detector = AgentActivityDetector()
        let baseline = sample(pid: 11, name: "codex", terminal: true, cpu: 100)

        XCTAssertFalse(detector.update(processes: [baseline], at: time(0)).shouldHold)
        XCTAssertFalse(
            detector.update(
                processes: [sample(pid: 11, name: "codex", terminal: true, cpu: 49_999_999)],
                at: time(5)
            ).shouldHold
        )
    }

    func testDesktopDetectorsUseRootCountersAndClaudeLocalAgentLifetime() {
        var detector = AgentActivityDetector()
        let codex = sample(
            pid: 20,
            name: "Codex",
            bundle: "com.openai.codex",
            cpu: 100
        )
        let claude = sample(
            pid: 30,
            name: "Claude",
            bundle: "com.anthropic.claudefordesktop",
            cpu: 200
        )
        let localAgent = sample(pid: 31, parent: 30, name: "claude", terminal: false)

        let initial = detector.update(processes: [codex, claude, localAgent], at: time(0))
        XCTAssertEqual(initial.sources, [AutomaticWakeSource(surface: .claudeDesktop, evidence: .activeProcess)])

        let active = detector.update(
            processes: [
                sample(pid: 20, name: "Codex", bundle: "com.openai.codex", cpu: 50_000_100),
                claude,
                localAgent,
            ],
            at: time(1)
        )
        XCTAssertTrue(active.shouldHold)
        XCTAssertEqual(
            Set(active.sources.map(\.surface)),
            Set([.codexDesktop, .claudeDesktop])
        )
    }

    func testCursorDesktopChildIsNotAlsoReportedAsCursorCLI() {
        var detector = AgentActivityDetector()
        let desktop = sample(
            pid: 40,
            name: "Cursor",
            bundle: "com.todesktop.230313mzl4w4u92",
            cpu: 100
        )
        let child = sample(pid: 41, parent: 40, name: "cursor-agent", terminal: false)

        let result = detector.update(processes: [desktop, child], at: time(0))
        XCTAssertFalse(result.shouldHold)
        XCTAssertTrue(result.sources.isEmpty)
    }

    func testIntegratedTerminalCLIRemainsIndependentFromDesktopParent() {
        var detector = AgentActivityDetector()
        let desktop = sample(
            pid: 40,
            name: "Cursor",
            bundle: "com.todesktop.230313mzl4w4u92",
            cpu: 100
        )
        let baseline = sample(
            pid: 41,
            parent: 40,
            name: "cursor-agent",
            terminal: true,
            cpu: 200
        )
        _ = detector.update(processes: [desktop, baseline], at: time(0))

        XCTAssertEqual(
            detector.update(
                processes: [
                    desktop,
                    sample(
                        pid: 41,
                        parent: 40,
                        name: "cursor-agent",
                        terminal: true,
                        cpu: 50_000_200
                    ),
                ],
                at: time(1)
            ),
            state(.cursorCLI, .activeProcess)
        )
    }

    func testMultipleDesktopInstancesAreUnionedBySurface() {
        var detector = AgentActivityDetector()
        let first = sample(
            pid: 42,
            name: "Cursor",
            bundle: "com.todesktop.230313mzl4w4u92",
            cpu: 100
        )
        let second = sample(
            pid: 43,
            name: "Cursor",
            bundle: "com.todesktop.230313mzl4w4u92",
            cpu: 200
        )
        _ = detector.update(processes: [first, second], at: time(0))

        XCTAssertEqual(
            detector.update(
                processes: [
                    first,
                    sample(
                        pid: 43,
                        name: "Cursor",
                        bundle: "com.todesktop.230313mzl4w4u92",
                        cpu: 50_000_200
                    ),
                ],
                at: time(1)
            ),
            state(.cursorDesktop, .activeProcess)
        )
    }

    func testClaudeLocalAgentExitBecomesRecentThenExpires() {
        var detector = AgentActivityDetector()
        let desktop = sample(
            pid: 44,
            name: "Claude",
            bundle: "com.anthropic.claudefordesktop",
            cpu: 100
        )
        let localAgent = sample(pid: 45, parent: 44, name: "claude", terminal: false)

        XCTAssertEqual(
            detector.update(processes: [desktop, localAgent], at: time(0)),
            state(.claudeDesktop, .activeProcess)
        )
        XCTAssertEqual(
            detector.update(processes: [desktop], at: time(1)),
            state(.claudeDesktop, .recentActivity)
        )
        XCTAssertFalse(detector.update(processes: [desktop], at: time(1_800)).shouldHold)
    }

    func testMultipleAutomaticSourcesAreUnionedAndExitIndependently() {
        var detector = AgentActivityDetector()
        let codex = sample(pid: 50, name: "codex", terminal: false)
        let cursor = sample(pid: 60, name: "cursor-agent", terminal: false)

        let both = detector.update(processes: [codex, cursor], at: time(0))
        XCTAssertEqual(Set(both.sources.map(\.surface)), Set([.codexCLI, .cursorCLI]))
        XCTAssertTrue(both.shouldHold)

        XCTAssertEqual(
            detector.update(processes: [cursor], at: time(1)),
            state(.cursorCLI, .activeProcess)
        )
    }

    func testPIDReuseDoesNotInheritRecentActivity() {
        var detector = AgentActivityDetector()
        _ = detector.update(
            processes: [sample(pid: 70, start: 1, name: "codex", terminal: true, cpu: 100)],
            at: time(0)
        )
        XCTAssertTrue(
            detector.update(
                processes: [sample(pid: 70, start: 1, name: "codex", terminal: true, cpu: 50_000_100)],
                at: time(1)
            ).shouldHold
        )

        let reused = detector.update(
            processes: [sample(pid: 70, start: 2, name: "codex", terminal: true, cpu: 500)],
            at: time(2)
        )
        XCTAssertFalse(reused.shouldHold)
    }

    func testClockRegressionDoesNotExpireRecentActivity() {
        var detector = AgentActivityDetector()
        _ = detector.update(
            processes: [sample(pid: 80, name: "cursor", terminal: true, cpu: 100)],
            at: time(100)
        )
        _ = detector.update(
            processes: [sample(pid: 80, name: "cursor", terminal: true, cpu: 50_000_100)],
            at: time(101)
        )

        XCTAssertEqual(
            detector.update(
                processes: [sample(pid: 80, name: "cursor", terminal: true, cpu: 50_000_100)],
                at: time(99)
            ),
            state(.cursorCLI, .recentActivity)
        )
    }

    func testEightHourCeilingRequiresIdleToActiveTransitionToRearm() {
        var detector = AgentActivityDetector(quietPeriodSeconds: 10, holdCeilingSeconds: 100)
        let headless = sample(pid: 90, name: "codex", terminal: false)

        XCTAssertTrue(detector.update(processes: [headless], at: time(0)).shouldHold)
        let limited = detector.update(processes: [headless], at: time(100))
        XCTAssertFalse(limited.shouldHold)
        XCTAssertTrue(limited.isCeilingLimited)
        XCTAssertTrue(detector.update(processes: [headless], at: time(101)).isCeilingLimited)

        XCTAssertFalse(detector.update(processes: [], at: time(102)).isCeilingLimited)
        XCTAssertTrue(
            detector.update(
                processes: [sample(pid: 91, name: "codex", terminal: false)],
                at: time(103)
            ).shouldHold
        )
    }

    func testSamplingFailureStillEnforcesCeilingWithoutCreatingIdleTransition() {
        var detector = AgentActivityDetector(holdCeilingSeconds: 100)
        let headless = sample(pid: 92, name: "codex", terminal: false)
        _ = detector.update(processes: [headless], at: time(0))

        let limited = detector.tickWithoutSnapshot(at: time(100))
        XCTAssertFalse(limited.shouldHold)
        XCTAssertTrue(limited.isCeilingLimited)
        XCTAssertEqual(limited.sources, [
            AutomaticWakeSource(surface: .codexCLI, evidence: .recentActivity),
        ])
        XCTAssertTrue(detector.tickWithoutSnapshot(at: time(101)).isCeilingLimited)
        XCTAssertTrue(detector.update(processes: [headless], at: time(102)).isCeilingLimited)
    }

    func testPerProcessSamplingFailureRetainsEvidenceAndCeilingLatch() {
        var detector = AgentActivityDetector(holdCeilingSeconds: 100)
        let headless = sample(pid: 93, name: "codex", terminal: false)
        _ = detector.update(processes: [headless], at: time(0))

        let limited = detector.update(
            processes: [],
            at: time(100),
            unavailableProcessIdentifiers: Set([93])
        )
        XCTAssertFalse(limited.shouldHold)
        XCTAssertTrue(limited.isCeilingLimited)
        XCTAssertTrue(
            detector.update(
                processes: [],
                at: time(101),
                unavailableProcessIdentifiers: Set([93])
            ).isCeilingLimited
        )
        XCTAssertTrue(detector.update(processes: [headless], at: time(102)).isCeilingLimited)
        XCTAssertFalse(detector.update(processes: [], at: time(103)).isCeilingLimited)
    }

    func testSamplingFailureEvidenceExpiresAfterQuietPeriod() {
        var detector = AgentActivityDetector(quietPeriodSeconds: 10)
        let headless = sample(pid: 94, name: "codex", terminal: false)
        _ = detector.update(processes: [headless], at: time(0))

        XCTAssertEqual(
            detector.update(
                processes: [],
                at: time(9),
                unavailableProcessIdentifiers: Set([94])
            ),
            state(.codexCLI, .recentActivity)
        )
        XCTAssertFalse(
            detector.update(
                processes: [],
                at: time(10),
                unavailableProcessIdentifiers: Set([94])
            ).shouldHold
        )
    }

    func testDisabledSurfaceDoesNotCreateSessionState() {
        var detector = AgentActivityDetector()
        let codex = sample(pid: 100, name: "codex", terminal: false)

        XCTAssertFalse(
            detector.update(
                processes: [codex],
                at: time(0),
                enabledSurfaces: Set([.claudeCLI])
            ).shouldHold
        )
        XCTAssertTrue(detector.update(processes: [codex], at: time(1)).shouldHold)
    }

    func testDisabledDesktopHelperIsNotReclassifiedAsCLI() {
        var detector = AgentActivityDetector()
        let desktop = sample(
            pid: 110,
            name: "Claude",
            bundle: "com.anthropic.claudefordesktop"
        )
        let helper = sample(pid: 111, parent: 110, name: "claude", terminal: false)

        let state = detector.update(
            processes: [desktop, helper],
            at: time(0),
            enabledSurfaces: Set([.claudeCLI])
        )
        XCTAssertFalse(state.shouldHold)
        XCTAssertTrue(state.sources.isEmpty)
    }

    func testUnknownDesktopBundleIsNotClassifiedAsHeadlessCLI() {
        var detector = AgentActivityDetector()
        let desktop = sample(
            pid: 120,
            name: "Cursor",
            bundle: "com.example.cursor-preview"
        )

        let state = detector.update(processes: [desktop], at: time(0))
        XCTAssertFalse(state.shouldHold)
        XCTAssertTrue(state.sources.isEmpty)
    }

    private func time(_ seconds: UInt64) -> MonotonicTime {
        MonotonicTime(seconds: seconds)
    }

    private func state(
        _ surface: AgentSurface,
        _ evidence: AgentActivityEvidence
    ) -> AutomaticWakeState {
        AutomaticWakeState(
            shouldHold: true,
            sources: [AutomaticWakeSource(surface: surface, evidence: evidence)],
            isCeilingLimited: false
        )
    }

    private func sample(
        pid: Int32,
        start: UInt64 = 1,
        parent: Int32? = nil,
        name: String,
        bundle: String? = nil,
        terminal: Bool = false,
        cpu: UInt64 = 0
    ) -> AgentProcessSample {
        AgentProcessSample(
            identity: AgentProcessIdentity(
                processIdentifier: pid,
                startTimeMicroseconds: start
            ),
            parentProcessIdentifier: parent,
            executableName: name,
            bundleIdentifier: bundle,
            hasControllingTerminal: terminal,
            cumulativeCPUTimeNanoseconds: cpu
        )
    }
}
