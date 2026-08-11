import Foundation

public enum AgentSurface: String, CaseIterable, Hashable, Sendable {
    case codexDesktop
    case codexCLI
    case claudeDesktop
    case claudeCLI
    case cursorDesktop
    case cursorCLI

    public var displayName: String {
        switch self {
        case .codexDesktop: "Codex Desktop"
        case .codexCLI: "Codex CLI"
        case .claudeDesktop: "Claude Desktop"
        case .claudeCLI: "Claude CLI"
        case .cursorDesktop: "Cursor Desktop"
        case .cursorCLI: "Cursor CLI"
        }
    }
}

public enum AgentActivityEvidence: String, Equatable, Sendable {
    case activeProcess = "active process"
    case recentActivity = "recent activity"
}

public struct MonotonicTime: Equatable, Sendable {
    public let seconds: UInt64

    public init(seconds: UInt64) {
        self.seconds = seconds
    }
}

public struct AgentProcessIdentity: Hashable, Sendable {
    public let processIdentifier: Int32
    public let startTimeMicroseconds: UInt64

    public init(processIdentifier: Int32, startTimeMicroseconds: UInt64) {
        self.processIdentifier = processIdentifier
        self.startTimeMicroseconds = startTimeMicroseconds
    }
}

public struct AgentProcessSample: Equatable, Sendable {
    public let identity: AgentProcessIdentity
    public let parentProcessIdentifier: Int32?
    public let executableName: String
    public let bundleIdentifier: String?
    public let hasControllingTerminal: Bool
    public let cumulativeCPUTimeNanoseconds: UInt64

    public init(
        identity: AgentProcessIdentity,
        parentProcessIdentifier: Int32? = nil,
        executableName: String,
        bundleIdentifier: String? = nil,
        hasControllingTerminal: Bool,
        cumulativeCPUTimeNanoseconds: UInt64
    ) {
        self.identity = identity
        self.parentProcessIdentifier = parentProcessIdentifier
        self.executableName = executableName
        self.bundleIdentifier = bundleIdentifier
        self.hasControllingTerminal = hasControllingTerminal
        self.cumulativeCPUTimeNanoseconds = cumulativeCPUTimeNanoseconds
    }
}

public struct AutomaticWakeSource: Equatable, Sendable {
    public let surface: AgentSurface
    public let evidence: AgentActivityEvidence

    public init(surface: AgentSurface, evidence: AgentActivityEvidence) {
        self.surface = surface
        self.evidence = evidence
    }
}

public struct AutomaticWakeState: Equatable, Sendable {
    public let shouldHold: Bool
    public let sources: [AutomaticWakeSource]
    public let isCeilingLimited: Bool

    public init(
        shouldHold: Bool,
        sources: [AutomaticWakeSource],
        isCeilingLimited: Bool
    ) {
        self.shouldHold = shouldHold
        self.sources = sources
        self.isCeilingLimited = isCeilingLimited
    }

    public func restricted(to enabledSurfaces: Set<AgentSurface>) -> AutomaticWakeState {
        let restrictedSources = sources.filter { enabledSurfaces.contains($0.surface) }
        return AutomaticWakeState(
            shouldHold: shouldHold && !restrictedSources.isEmpty,
            sources: restrictedSources,
            isCeilingLimited: isCeilingLimited && !restrictedSources.isEmpty
        )
    }
}

public struct AgentActivityDetector: Sendable {
    public static let defaultQuietPeriodSeconds: UInt64 = 30 * 60
    public static let defaultHoldCeilingSeconds: UInt64 = 8 * 60 * 60
    public static let minimumActivityCPUTimeNanoseconds: UInt64 = 50_000_000

    private struct SessionKey: Hashable, Sendable {
        let surface: AgentSurface
        let identity: AgentProcessIdentity
    }

    private struct SessionState: Sendable {
        var lastCPUTimeNanoseconds: UInt64
        var lastActivity: MonotonicTime?
    }

    private let quietPeriodSeconds: UInt64
    private let holdCeilingSeconds: UInt64
    private var sessions: [SessionKey: SessionState] = [:]
    private var holdStartedAt: MonotonicTime?
    private var ceilingBlocked = false

    public init(
        quietPeriodSeconds: UInt64 = Self.defaultQuietPeriodSeconds,
        holdCeilingSeconds: UInt64 = Self.defaultHoldCeilingSeconds
    ) {
        self.quietPeriodSeconds = quietPeriodSeconds
        self.holdCeilingSeconds = holdCeilingSeconds
    }

    public mutating func update(
        processes: [AgentProcessSample],
        at now: MonotonicTime,
        unavailableProcessIdentifiers: Set<Int32> = [],
        enabledSurfaces: Set<AgentSurface> = Set(AgentSurface.allCases)
    ) -> AutomaticWakeState {
        var processesByIdentifier: [Int32: AgentProcessSample] = [:]
        for process in processes {
            processesByIdentifier[process.identity.processIdentifier] = process
        }
        let normalizedProcesses = Array(processesByIdentifier.values)
        let desktopRoots = desktopRootProcesses(in: normalizedProcesses)
        var currentSessionKeys: Set<SessionKey> = []
        var evidenceBySurface: [AgentSurface: AgentActivityEvidence] = [:]

        for (surface, roots) in desktopRoots {
            guard enabledSurfaces.contains(surface) else {
                continue
            }
            for root in roots {
                let sessionKey = SessionKey(surface: surface, identity: root.identity)
                currentSessionKeys.insert(sessionKey)
                let hasLocalAgent = surface == .claudeDesktop && normalizedProcesses.contains { process in
                    Self.claudeLocalAgentNames.contains(process.executableName.lowercased()) &&
                        isDescendant(
                            process,
                            of: root.identity.processIdentifier,
                            processesByIdentifier: processesByIdentifier
                        )
                }
                if let evidence = activityEvidence(
                    for: sessionKey,
                    sample: root,
                    at: now,
                    forceActive: hasLocalAgent
                ) {
                    evidenceBySurface[surface] = stronger(evidenceBySurface[surface], evidence)
                }
            }
        }

        for process in normalizedProcesses {
            guard let surface = cliSurface(for: process.executableName),
                  enabledSurfaces.contains(surface),
                  process.bundleIdentifier == nil,
                  process.hasControllingTerminal || !belongsToDesktopApp(
                      process,
                      surface: surface,
                      desktopRoots: desktopRoots,
                      processesByIdentifier: processesByIdentifier
                  ) else {
                continue
            }

            let sessionKey = SessionKey(surface: surface, identity: process.identity)
            currentSessionKeys.insert(sessionKey)
            let evidence: AgentActivityEvidence?
            if process.hasControllingTerminal {
                evidence = activityEvidence(
                    for: sessionKey,
                    sample: process,
                    at: now,
                    forceActive: false
                )
            } else {
                sessions[sessionKey] = SessionState(
                    lastCPUTimeNanoseconds: process.cumulativeCPUTimeNanoseconds,
                    lastActivity: now
                )
                evidence = .activeProcess
            }
            if let evidence {
                evidenceBySurface[surface] = stronger(evidenceBySurface[surface], evidence)
            }
        }

        for (sessionKey, session) in sessions
        where unavailableProcessIdentifiers.contains(sessionKey.identity.processIdentifier) &&
            enabledSurfaces.contains(sessionKey.surface) {
            if let evidence = retainedEvidence(for: session, at: now) {
                currentSessionKeys.insert(sessionKey)
                evidenceBySurface[sessionKey.surface] = stronger(
                    evidenceBySurface[sessionKey.surface],
                    evidence
                )
            }
        }

        sessions = sessions.filter { currentSessionKeys.contains($0.key) }
        let sources = evidenceBySurface
            .map { AutomaticWakeSource(surface: $0.key, evidence: $0.value) }
            .sorted { $0.surface.rawValue < $1.surface.rawValue }
        return resolveHoldState(sources: sources, at: now)
    }

    public mutating func tickWithoutSnapshot(at now: MonotonicTime) -> AutomaticWakeState {
        var evidenceBySurface: [AgentSurface: AgentActivityEvidence] = [:]
        for (sessionKey, session) in sessions {
            if let evidence = retainedEvidence(for: session, at: now) {
                evidenceBySurface[sessionKey.surface] = stronger(
                    evidenceBySurface[sessionKey.surface],
                    evidence
                )
            }
        }
        let sources = evidenceBySurface
            .map { AutomaticWakeSource(surface: $0.key, evidence: $0.value) }
            .sorted { $0.surface.rawValue < $1.surface.rawValue }
        return resolveHoldState(sources: sources, at: now)
    }

    private mutating func resolveHoldState(
        sources: [AutomaticWakeSource],
        at now: MonotonicTime
    ) -> AutomaticWakeState {
        guard !sources.isEmpty else {
            holdStartedAt = nil
            ceilingBlocked = false
            return AutomaticWakeState(shouldHold: false, sources: [], isCeilingLimited: false)
        }

        if ceilingBlocked {
            return AutomaticWakeState(shouldHold: false, sources: sources, isCeilingLimited: true)
        }

        if let holdStartedAt,
           elapsedSeconds(from: holdStartedAt, to: now) >= holdCeilingSeconds {
            self.holdStartedAt = nil
            ceilingBlocked = true
            return AutomaticWakeState(shouldHold: false, sources: sources, isCeilingLimited: true)
        }

        if holdStartedAt == nil {
            holdStartedAt = now
        }
        return AutomaticWakeState(shouldHold: true, sources: sources, isCeilingLimited: false)
    }

    private mutating func activityEvidence(
        for sessionKey: SessionKey,
        sample: AgentProcessSample,
        at now: MonotonicTime,
        forceActive: Bool
    ) -> AgentActivityEvidence? {
        var session = sessions[sessionKey] ?? SessionState(
            lastCPUTimeNanoseconds: sample.cumulativeCPUTimeNanoseconds,
            lastActivity: nil
        )
        let cpuTimeDelta = sample.cumulativeCPUTimeNanoseconds >= session.lastCPUTimeNanoseconds
            ? sample.cumulativeCPUTimeNanoseconds - session.lastCPUTimeNanoseconds
            : 0
        let counterAdvanced = cpuTimeDelta >= Self.minimumActivityCPUTimeNanoseconds
        session.lastCPUTimeNanoseconds = sample.cumulativeCPUTimeNanoseconds
        if forceActive || counterAdvanced {
            session.lastActivity = now
        }
        let evidence: AgentActivityEvidence?
        if forceActive || counterAdvanced {
            evidence = .activeProcess
        } else if let lastActivity = session.lastActivity,
                  elapsedSeconds(from: lastActivity, to: now) < quietPeriodSeconds {
            evidence = .recentActivity
        } else {
            evidence = nil
        }
        sessions[sessionKey] = session
        return evidence
    }

    private func retainedEvidence(
        for session: SessionState,
        at now: MonotonicTime
    ) -> AgentActivityEvidence? {
        guard let lastActivity = session.lastActivity,
              elapsedSeconds(from: lastActivity, to: now) < quietPeriodSeconds else {
            return nil
        }
        return .recentActivity
    }

    private func desktopRootProcesses(
        in processes: [AgentProcessSample]
    ) -> [AgentSurface: [AgentProcessSample]] {
        var roots: [AgentSurface: [AgentProcessSample]] = [:]
        for process in processes {
            guard let bundleIdentifier = process.bundleIdentifier?.lowercased(),
                  let surface = Self.desktopBundleIdentifiers[bundleIdentifier] else {
                continue
            }
            roots[surface, default: []].append(process)
        }
        return roots
    }

    private func cliSurface(for executableName: String) -> AgentSurface? {
        switch executableName.lowercased() {
        case "codex": .codexCLI
        case "claude": .claudeCLI
        case "cursor", "cursor-agent": .cursorCLI
        default: nil
        }
    }

    private func belongsToDesktopApp(
        _ process: AgentProcessSample,
        surface: AgentSurface,
        desktopRoots: [AgentSurface: [AgentProcessSample]],
        processesByIdentifier: [Int32: AgentProcessSample]
    ) -> Bool {
        let desktopSurface: AgentSurface
        switch surface {
        case .codexCLI: desktopSurface = .codexDesktop
        case .claudeCLI: desktopSurface = .claudeDesktop
        case .cursorCLI: desktopSurface = .cursorDesktop
        default: return false
        }
        return desktopRoots[desktopSurface, default: []].contains { root in
            process.identity == root.identity || isDescendant(
                process,
                of: root.identity.processIdentifier,
                processesByIdentifier: processesByIdentifier
            )
        }
    }

    private func isDescendant(
        _ process: AgentProcessSample,
        of rootProcessIdentifier: Int32,
        processesByIdentifier: [Int32: AgentProcessSample]
    ) -> Bool {
        var parentProcessIdentifier = process.parentProcessIdentifier
        var visited: Set<Int32> = []
        while let parent = parentProcessIdentifier, visited.insert(parent).inserted {
            if parent == rootProcessIdentifier {
                return true
            }
            parentProcessIdentifier = processesByIdentifier[parent]?.parentProcessIdentifier
        }
        return false
    }

    private func elapsedSeconds(from start: MonotonicTime, to end: MonotonicTime) -> UInt64 {
        end.seconds >= start.seconds ? end.seconds - start.seconds : 0
    }

    private func stronger(
        _ current: AgentActivityEvidence?,
        _ candidate: AgentActivityEvidence
    ) -> AgentActivityEvidence {
        if current == .activeProcess || candidate == .activeProcess {
            return .activeProcess
        }
        return .recentActivity
    }

    private static let desktopBundleIdentifiers: [String: AgentSurface] = [
        "com.openai.codex": .codexDesktop,
        "com.anthropic.claudefordesktop": .claudeDesktop,
        "com.todesktop.230313mzl4w4u92": .cursorDesktop,
    ]

    private static let claudeLocalAgentNames: Set<String> = [
        "claude",
        "claude-agent",
        "claude-code",
    ]
}
