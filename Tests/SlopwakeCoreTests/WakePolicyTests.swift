import SlopwakeCore
import XCTest

final class WakePolicyTests: XCTestCase {
    func testManualAndAutomaticDemandAreUnionedAndManualExpires() {
        var policy = WakePolicy()
        policy.startManualHold(.thirtyMinutes, at: time(0))

        XCTAssertEqual(
            policy.evaluate(
                automatic: automatic(.codexCLI),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(10)
            ),
            WakePolicyState(
                shouldHold: true,
                status: .manual(
                    remainingSeconds: 1_790,
                    automaticAlsoActive: true
                ),
                sources: [source(.codexCLI)],
                isManualActive: true
            )
        )

        XCTAssertEqual(
            policy.evaluate(
                automatic: automatic(.codexCLI),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(1_800)
            ).status,
            .automatic(elapsedSeconds: 1_790)
        )
    }

    func testEveryBoundedManualDurationExpires() {
        for duration in ManualHoldDuration.allCases {
            var policy = WakePolicy()
            policy.startManualHold(duration, at: time(100))
            XCTAssertTrue(
                policy.evaluate(
                    automatic: idle,
                    battery: .externalPower,
                    batteryCutoffPercentage: 15,
                    at: time(100 + duration.rawValue - 1)
                ).shouldHold
            )
            XCTAssertEqual(
                policy.evaluate(
                    automatic: idle,
                    battery: .externalPower,
                    batteryCutoffPercentage: 15,
                    at: time(100 + duration.rawValue)
                ).status,
                .idle
            )
        }
    }

    func testTimedPauseExpiresWithoutChangingAutomaticEvidence() {
        var policy = WakePolicy()
        policy.pauseAutomatic(for: .thirtyMinutes, at: time(0))

        let paused = policy.evaluate(
            automatic: automatic(.claudeDesktop),
            battery: .externalPower,
            batteryCutoffPercentage: 15,
            at: time(1)
        )
        XCTAssertEqual(paused.status, .paused(remainingSeconds: 1_799))
        XCTAssertEqual(paused.sources, [source(.claudeDesktop)])
        XCTAssertFalse(paused.shouldHold)

        XCTAssertEqual(
            policy.evaluate(
                automatic: automatic(.claudeDesktop),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(1_800)
            ).status,
            .automatic(elapsedSeconds: 0)
        )
    }

    func testPauseUntilResumedAndManualDemandRemainIndependent() {
        var policy = WakePolicy()
        policy.pauseAutomaticUntilResumed(at: time(0))
        policy.startManualHold(.oneHour, at: time(10))

        let manual = policy.evaluate(
            automatic: automatic(.cursorCLI),
            battery: .externalPower,
            batteryCutoffPercentage: 15,
            at: time(20)
        )
        XCTAssertEqual(
            manual.status,
            .manual(remainingSeconds: 3_590, automaticAlsoActive: false)
        )
        XCTAssertTrue(manual.shouldHold)

        policy.endManualHold()
        XCTAssertEqual(
            policy.evaluate(
                automatic: automatic(.cursorCLI),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(21)
            ).status,
            .paused(remainingSeconds: nil)
        )

        policy.resumeAutomatic()
        XCTAssertTrue(
            policy.evaluate(
                automatic: automatic(.cursorCLI),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(22)
            ).shouldHold
        )
    }

    func testBatteryCutoffReleasesAndRecoveryRearmsDemand() {
        var policy = WakePolicy()
        let automatic = automatic(.codexDesktop)

        let limited = policy.evaluate(
            automatic: automatic,
            battery: BatteryState(percentage: 15, powerSource: .battery),
            batteryCutoffPercentage: 15,
            at: time(0)
        )
        XCTAssertEqual(limited.status, .batteryLimited(percentage: 15, cutoffPercentage: 15))
        XCTAssertFalse(limited.shouldHold)

        XCTAssertTrue(
            policy.evaluate(
                automatic: automatic,
                battery: BatteryState(percentage: 16, powerSource: .battery),
                batteryCutoffPercentage: 15,
                at: time(1)
            ).shouldHold
        )
        XCTAssertTrue(
            policy.evaluate(
                automatic: automatic,
                battery: BatteryState(percentage: 1, powerSource: .battery),
                batteryCutoffPercentage: nil,
                at: time(2)
            ).shouldHold
        )
    }

    func testBatteryCutoffFailsSafeWhenChargeIsUnavailable() {
        var policy = WakePolicy()
        let limited = policy.evaluate(
            automatic: automatic(.codexCLI),
            battery: BatteryState(percentage: nil, powerSource: .battery),
            batteryCutoffPercentage: 15,
            at: time(0)
        )

        XCTAssertFalse(limited.shouldHold)
        XCTAssertEqual(
            limited.status,
            .batteryLimited(percentage: nil, cutoffPercentage: 15)
        )
        XCTAssertEqual(
            limited.status.displayText,
            "battery limited · charge unavailable · cutoff 15%"
        )
    }

    func testBatteryCutoffFailsSafeWhenPowerSourceIsUnknown() {
        var policy = WakePolicy()
        let limited = policy.evaluate(
            automatic: automatic(.codexCLI),
            battery: .unknown,
            batteryCutoffPercentage: 15,
            at: time(0)
        )

        XCTAssertFalse(limited.shouldHold)
        XCTAssertEqual(
            limited.status,
            .batteryLimited(percentage: nil, cutoffPercentage: 15)
        )
    }

    func testBatteryCutoffDoesNotLimitExternalPowerWithoutABattery() {
        var policy = WakePolicy()

        XCTAssertTrue(
            policy.evaluate(
                automatic: automatic(.codexCLI),
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(0)
            ).shouldHold
        )
    }

    func testMonotonicClockRegressionDoesNotExpireManualOrPause() {
        var policy = WakePolicy()
        policy.startManualHold(.thirtyMinutes, at: time(100))
        XCTAssertEqual(
            policy.evaluate(
                automatic: idle,
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(99)
            ).status,
            .manual(remainingSeconds: 1_800, automaticAlsoActive: false)
        )

        policy.endManualHold()
        policy.pauseAutomatic(for: .oneHour, at: time(100))
        XCTAssertEqual(
            policy.evaluate(
                automatic: idle,
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(99)
            ).status,
            .paused(remainingSeconds: 3_600)
        )
    }

    func testNewPolicyAfterAppRestartContainsNoSessionState() {
        var priorSession = WakePolicy()
        priorSession.startManualHold(.eightHours, at: time(0))
        priorSession.pauseAutomaticUntilResumed(at: time(0))

        var restarted = WakePolicy()
        XCTAssertEqual(
            restarted.evaluate(
                automatic: idle,
                battery: .externalPower,
                batteryCutoffPercentage: 15,
                at: time(1)
            ),
            WakePolicyState(shouldHold: false, status: .idle, sources: [])
        )
    }

    func testMenuStatusTextCoversEveryState() {
        XCTAssertEqual(WakeMenuStatus.idle.displayText, "idle · sleep allowed")
        XCTAssertEqual(
            WakeMenuStatus.automatic(elapsedSeconds: 3_661).displayText,
            "awake · automatic · 1:01:01 elapsed"
        )
        XCTAssertEqual(
            WakeMenuStatus.manual(
                remainingSeconds: 90,
                automaticAlsoActive: false
            ).displayText,
            "awake · manual · 1:30 left"
        )
        XCTAssertEqual(
            WakeMenuStatus.manual(
                remainingSeconds: 90,
                automaticAlsoActive: true
            ).displayText,
            "awake · manual + automatic · 1:30 left"
        )
        XCTAssertEqual(
            WakeMenuStatus.paused(remainingSeconds: 60).displayText,
            "paused · 1:00 left"
        )
        XCTAssertEqual(
            WakeMenuStatus.paused(remainingSeconds: nil).displayText,
            "paused · until resumed"
        )
        XCTAssertEqual(
            WakeMenuStatus.batteryLimited(
                percentage: 14,
                cutoffPercentage: 15
            ).displayText,
            "battery limited · 14% ≤ 15%"
        )
    }

    private var idle: AutomaticWakeState {
        AutomaticWakeState(shouldHold: false, sources: [])
    }

    private func automatic(_ surface: AgentSurface) -> AutomaticWakeState {
        AutomaticWakeState(
            shouldHold: true,
            sources: [source(surface)]
        )
    }

    private func source(_ surface: AgentSurface) -> AutomaticWakeSource {
        AutomaticWakeSource(surface: surface, evidence: .activeProcess)
    }

    private func time(_ seconds: UInt64) -> MonotonicTime {
        MonotonicTime(seconds: seconds)
    }
}
