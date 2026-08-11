import Foundation

public protocol WakeProcess: AnyObject {
    var isRunning: Bool { get }
    var processIdentifier: Int32 { get }

    func run() throws
    func setTerminationHandler(_ handler: @escaping @Sendable () -> Void)
    func terminate()
    func waitUntilExit()
}

extension Process: WakeProcess {
    public func setTerminationHandler(_ handler: @escaping @Sendable () -> Void) {
        terminationHandler = { _ in handler() }
    }
}

public typealias WakeProcessFactory = @MainActor (URL, [String]) -> any WakeProcess

@MainActor
public final class CaffeinateController {
    private let ownerPID: Int32
    private let processFactory: WakeProcessFactory
    private var process: (any WakeProcess)?
    private var activeProcessToken: UUID?

    public var unexpectedTerminationHandler: (() -> Void)?

    public init(
        ownerPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        processFactory: @escaping WakeProcessFactory = { executableURL, arguments in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            return process
        }
    ) {
        self.ownerPID = ownerPID
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
        if process?.isRunning == true {
            return false
        }

        process = nil
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

        activeProcessToken = nil
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        self.process = nil
        return true
    }

    private func processDidTerminate(token: UUID) {
        guard activeProcessToken == token else {
            return
        }

        process?.waitUntilExit()
        process = nil
        activeProcessToken = nil
        unexpectedTerminationHandler?()
    }
}
