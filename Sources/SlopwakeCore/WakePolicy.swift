import Foundation

public enum ManualHoldDuration: UInt64, CaseIterable, Sendable {
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case eightHours = 28_800

    public var displayName: String {
        switch self {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        case .eightHours: "8 hours"
        }
    }
}

public enum AutomaticPauseDuration: UInt64, CaseIterable, Sendable {
    case thirtyMinutes = 1_800
    case oneHour = 3_600

    public var displayName: String {
        switch self {
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }
}

public enum BatteryPowerSource: Equatable, Sendable {
    case battery
    case external
    case unknown
}

public struct BatteryState: Equatable, Sendable {
    public let percentage: Int?
    public let powerSource: BatteryPowerSource

    public static let unknown = BatteryState(
        percentage: nil,
        powerSource: .unknown
    )

    public static let externalPower = BatteryState(
        percentage: nil,
        powerSource: .external
    )

    public init(percentage: Int?, powerSource: BatteryPowerSource) {
        self.percentage = percentage
        self.powerSource = powerSource
    }
}

public enum WakeMenuStatus: Equatable, Sendable {
    case idle
    case automatic(elapsedSeconds: UInt64)
    case manual(remainingSeconds: UInt64, automaticAlsoActive: Bool)
    case paused(remainingSeconds: UInt64?)
    case batteryLimited(percentage: Int?, cutoffPercentage: Int)

    public var displayText: String {
        switch self {
        case .idle:
            "idle · sleep allowed"
        case let .automatic(elapsedSeconds):
            "awake · automatic · \(Self.duration(elapsedSeconds)) elapsed"
        case let .manual(remainingSeconds, automaticAlsoActive):
            "awake · \(automaticAlsoActive ? "manual + automatic" : "manual") · " +
                "\(Self.duration(remainingSeconds)) left"
        case let .paused(remainingSeconds):
            remainingSeconds.map { "paused · \(Self.duration($0)) left" } ??
                "paused · until resumed"
        case let .batteryLimited(percentage, cutoffPercentage):
            if let percentage {
                "battery limited · \(percentage)% ≤ \(cutoffPercentage)%"
            } else {
                "battery limited · charge unavailable · cutoff \(cutoffPercentage)%"
            }
        }
    }

    private static func duration(_ seconds: UInt64) -> String {
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        let seconds = seconds % 60
        if hours > 0 {
            return String(format: "%llu:%02llu:%02llu", hours, minutes, seconds)
        }
        return String(format: "%llu:%02llu", minutes, seconds)
    }
}

public struct WakePolicyState: Equatable, Sendable {
    public let shouldHold: Bool
    public let status: WakeMenuStatus
    public let sources: [AutomaticWakeSource]
    public let isManualActive: Bool
    public let isAutomaticPaused: Bool

    public init(
        shouldHold: Bool,
        status: WakeMenuStatus,
        sources: [AutomaticWakeSource],
        isManualActive: Bool = false,
        isAutomaticPaused: Bool = false
    ) {
        self.shouldHold = shouldHold
        self.status = status
        self.sources = sources
        self.isManualActive = isManualActive
        self.isAutomaticPaused = isAutomaticPaused
    }
}

public struct WakePolicy: Sendable {
    private var manualStartedAt: MonotonicTime?
    private var manualDurationSeconds: UInt64?
    private var automaticStartedAt: MonotonicTime?
    private var pauseStartedAt: MonotonicTime?
    private var pauseDurationSeconds: UInt64?
    private var isPausedUntilResumed = false

    public init() {}

    public mutating func startManualHold(
        _ duration: ManualHoldDuration,
        at now: MonotonicTime
    ) {
        manualStartedAt = now
        manualDurationSeconds = duration.rawValue
    }

    public mutating func endManualHold() {
        manualStartedAt = nil
        manualDurationSeconds = nil
    }

    public mutating func pauseAutomatic(
        for duration: AutomaticPauseDuration,
        at now: MonotonicTime
    ) {
        pauseStartedAt = now
        pauseDurationSeconds = duration.rawValue
        isPausedUntilResumed = false
        automaticStartedAt = nil
    }

    public mutating func pauseAutomaticUntilResumed(at now: MonotonicTime) {
        pauseStartedAt = now
        pauseDurationSeconds = nil
        isPausedUntilResumed = true
        automaticStartedAt = nil
    }

    public mutating func resumeAutomatic() {
        pauseStartedAt = nil
        pauseDurationSeconds = nil
        isPausedUntilResumed = false
    }

    public mutating func evaluate(
        automatic: AutomaticWakeState,
        battery: BatteryState,
        batteryCutoffPercentage: Int?,
        at now: MonotonicTime
    ) -> WakePolicyState {
        let manualRemaining = resolveManualRemaining(at: now)
        let pauseRemaining = resolvePauseRemaining(at: now)
        let isPaused = isPausedUntilResumed || pauseRemaining != nil
        let automaticRequested = automatic.shouldHold && !isPaused
        let hasDemand = manualRemaining != nil || automaticRequested

        if let cutoff = batteryCutoffPercentage,
           cutoff > 0,
           battery.powerSource != .external,
           battery.powerSource == .unknown ||
               battery.percentage.map({ $0 <= cutoff }) ?? true,
           hasDemand {
            automaticStartedAt = nil
            return WakePolicyState(
                shouldHold: false,
                status: .batteryLimited(
                    percentage: battery.percentage,
                    cutoffPercentage: cutoff
                ),
                sources: automatic.sources,
                isManualActive: manualRemaining != nil,
                isAutomaticPaused: isPaused
            )
        }

        if let manualRemaining {
            if automaticRequested {
                beginAutomaticIfNeeded(at: now)
            } else {
                automaticStartedAt = nil
            }
            return WakePolicyState(
                shouldHold: true,
                status: .manual(
                    remainingSeconds: manualRemaining,
                    automaticAlsoActive: automaticRequested
                ),
                sources: automatic.sources,
                isManualActive: true,
                isAutomaticPaused: isPaused
            )
        }

        if isPaused {
            automaticStartedAt = nil
            return WakePolicyState(
                shouldHold: false,
                status: .paused(remainingSeconds: pauseRemaining),
                sources: automatic.sources,
                isAutomaticPaused: true
            )
        }

        if automaticRequested {
            beginAutomaticIfNeeded(at: now)
            return WakePolicyState(
                shouldHold: true,
                status: .automatic(
                    elapsedSeconds: elapsedSeconds(
                        from: automaticStartedAt ?? now,
                        to: now
                    )
                ),
                sources: automatic.sources
            )
        }

        automaticStartedAt = nil
        return WakePolicyState(shouldHold: false, status: .idle, sources: [])
    }

    private mutating func resolveManualRemaining(at now: MonotonicTime) -> UInt64? {
        guard let manualStartedAt, let manualDurationSeconds else {
            return nil
        }
        let elapsed = elapsedSeconds(from: manualStartedAt, to: now)
        guard elapsed < manualDurationSeconds else {
            endManualHold()
            return nil
        }
        return manualDurationSeconds - elapsed
    }

    private mutating func resolvePauseRemaining(at now: MonotonicTime) -> UInt64? {
        guard !isPausedUntilResumed,
              let pauseStartedAt,
              let pauseDurationSeconds else {
            return nil
        }
        let elapsed = elapsedSeconds(from: pauseStartedAt, to: now)
        guard elapsed < pauseDurationSeconds else {
            resumeAutomatic()
            return nil
        }
        return pauseDurationSeconds - elapsed
    }

    private mutating func beginAutomaticIfNeeded(at now: MonotonicTime) {
        if automaticStartedAt == nil {
            automaticStartedAt = now
        }
    }

    private func elapsedSeconds(
        from start: MonotonicTime,
        to end: MonotonicTime
    ) -> UInt64 {
        guard end.seconds >= start.seconds else {
            return 0
        }
        return end.seconds - start.seconds
    }
}
