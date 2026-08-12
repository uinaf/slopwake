import Foundation

public protocol WakeProcess: AnyObject {
    var isRunning: Bool { get }
    var processIdentifier: Int32 { get }

    func run() throws
    func setTerminationHandler(_ handler: @escaping @Sendable () -> Void)
    func terminate()
    func forceTerminate()
    func waitUntilExit()
}

extension Process: WakeProcess {
    public func setTerminationHandler(_ handler: @escaping @Sendable () -> Void) {
        terminationHandler = { _ in handler() }
    }

    public func forceTerminate() {
        let processIdentifier = processIdentifier
        guard processIdentifier > 0 else {
            return
        }
        kill(processIdentifier, SIGKILL)
    }
}

public typealias WakeProcessFactory = @MainActor (URL, [String]) -> any WakeProcess

@MainActor
public final class CaffeinateController {
    private let ownerPID: Int32
    private let processFactory: WakeProcessFactory
    private let terminationGracePeriod: Duration
    private var process: (any WakeProcess)?
    private var activeProcessToken: UUID?
    private var requestedTerminationToken: UUID?

    public var stateChangeHandler: (() -> Void)?
    public var unexpectedTerminationHandler: (() -> Void)?

    public init(
        ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        terminationGracePeriod: Duration = .seconds(2),
        processFactory: @escaping WakeProcessFactory = { executableURL, arguments in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            return process
        }
    ) {
        self.ownerPID = ownerPID
        self.terminationGracePeriod = terminationGracePeriod
        self.processFactory = processFactory
    }

    public var isHolding: Bool {
        process?.isRunning == true
    }

    public var processIdentifier: Int32? {
        guard let process, process.isRunning else {
            return nil
        }

        return process.processIdentifier
    }

    @discardableResult
    public func start() throws -> Bool {
        if let process {
            if process.isRunning {
                guard requestedTerminationToken == activeProcessToken,
                      let activeProcessToken else {
                    return false
                }
                process.forceTerminate()
                processDidTerminate(token: activeProcessToken)
            }
            if let activeProcessToken = self.activeProcessToken {
                processDidTerminate(token: activeProcessToken)
            }
        }

        let newProcess = processFactory(
            URL(fileURLWithPath: "/usr/bin/caffeinate"),
            ["-ims", "-w", String(ownerPID)]
        )
        let processToken = UUID()
        process = newProcess
        activeProcessToken = processToken
        newProcess.setTerminationHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.processDidTerminate(token: processToken)
            }
        }

        do {
            try newProcess.run()
        } catch {
            process = nil
            activeProcessToken = nil
            throw error
        }
        return true
    }

    @discardableResult
    public func stop() -> Bool {
        guard let process else {
            return false
        }

        guard let activeProcessToken,
              requestedTerminationToken != activeProcessToken else {
            return false
        }

        guard process.isRunning else {
            processDidTerminate(token: activeProcessToken)
            return true
        }

        requestedTerminationToken = activeProcessToken
        process.terminate()
        scheduleForcedTermination(token: activeProcessToken)
        return true
    }

    private func scheduleForcedTermination(token: UUID) {
        Task { @MainActor [weak self, terminationGracePeriod] in
            try? await Task.sleep(for: terminationGracePeriod)
            guard let self,
                  self.activeProcessToken == token,
                  self.process?.isRunning == true else {
                return
            }
            self.process?.forceTerminate()
        }
    }

    private func processDidTerminate(token: UUID) {
        guard activeProcessToken == token else {
            return
        }

        process?.waitUntilExit()
        let wasRequested = requestedTerminationToken == token
        process = nil
        activeProcessToken = nil
        requestedTerminationToken = nil
        stateChangeHandler?()
        if !wasRequested {
            unexpectedTerminationHandler?()
        }
    }
}
