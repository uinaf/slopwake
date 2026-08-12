import Darwin
import Foundation
import SlopwakeCore
import XCTest

@MainActor
final class CaffeinateControllerTests: XCTestCase {
    func testStartOwnsExactlyOneProcessAndStopReapsIt() async throws {
        var processes: [FakeWakeProcess] = []
        var invocations: [(URL, [String])] = []
        let controller = CaffeinateController(ownerPID: 42) { executableURL, arguments in
            invocations.append((executableURL, arguments))
            let process = FakeWakeProcess()
            processes.append(process)
            return process
        }

        XCTAssertTrue(try controller.start())
        XCTAssertFalse(try controller.start())
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(invocations.count, 1)
        XCTAssertEqual(invocations[0].0.path, "/usr/bin/caffeinate")
        XCTAssertEqual(invocations[0].1, ["-ims", "-w", "42"])
        XCTAssertTrue(controller.isHolding)
        XCTAssertEqual(controller.processIdentifier, 7_001)

        let stopped = expectation(description: "expected termination handled")
        controller.stateChangeHandler = stopped.fulfill
        XCTAssertTrue(controller.stop())
        processes[0].finishTermination()
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertFalse(controller.stop())
        XCTAssertEqual(processes[0].terminateCount, 1)
        XCTAssertEqual(processes[0].waitCount, 1)
        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
    }

    func testExitedProcessCanBeReplaced() async throws {
        var processes: [FakeWakeProcess] = []
        let controller = CaffeinateController { _, _ in
            let process = FakeWakeProcess(processIdentifier: Int32(7_001 + processes.count))
            processes.append(process)
            return process
        }

        XCTAssertTrue(try controller.start())
        processes[0].isRunning = false

        XCTAssertTrue(try controller.start())
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].waitCount, 1)
        XCTAssertEqual(controller.processIdentifier, 7_002)

        let stopped = expectation(description: "replacement process stopped")
        controller.stateChangeHandler = stopped.fulfill
        controller.stop()
        processes[1].finishTermination()
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testStartReplacesAProcessWithPendingTermination() async throws {
        var processes: [FakeWakeProcess] = []
        let controller = CaffeinateController { _, _ in
            let process = FakeWakeProcess(
                processIdentifier: Int32(7_001 + processes.count),
                ignoresTerminate: true
            )
            processes.append(process)
            return process
        }

        XCTAssertTrue(try controller.start())
        XCTAssertTrue(controller.stop())
        XCTAssertFalse(try controller.start())

        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].forceTerminateCount, 1)
        XCTAssertEqual(processes[0].waitCount, 0)

        let replaced = expectation(description: "replacement process started")
        controller.stateChangeHandler = replaced.fulfill
        processes[0].finishTermination()
        await fulfillment(of: [replaced], timeout: 1)

        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].waitCount, 1)
        XCTAssertEqual(controller.processIdentifier, 7_002)

        let stopped = expectation(description: "replacement process stopped")
        controller.stateChangeHandler = stopped.fulfill
        XCTAssertTrue(controller.stop())
        processes[1].finishTermination()
        await fulfillment(of: [stopped], timeout: 1)
    }

    func testDefaultOwnerPIDIsPassedToCaffeinate() throws {
        var arguments: [String] = []
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, receivedArguments in
            arguments = receivedArguments
            return process
        }

        XCTAssertTrue(try controller.start())
        XCTAssertEqual(
            arguments,
            ["-ims", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        )
        XCTAssertTrue(controller.stop())
        process.finishTermination()
    }

    func testLaunchFailureDoesNotClaimAHoldAndCanBeRetried() async throws {
        var invocations: [(URL, [String])] = []
        var processes: [FakeWakeProcess] = []
        let controller = CaffeinateController(ownerPID: 42) { executableURL, arguments in
            invocations.append((executableURL, arguments))
            let process = FakeWakeProcess(
                processIdentifier: Int32(7_001 + processes.count),
                runError: processes.isEmpty ? TestError.launchFailed : nil
            )
            processes.append(process)
            return process
        }

        XCTAssertThrowsError(try controller.start())
        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
        XCTAssertFalse(controller.stop())

        XCTAssertTrue(try controller.start())
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[1].0.path, "/usr/bin/caffeinate")
        XCTAssertEqual(invocations[1].1, ["-ims", "-w", "42"])
        XCTAssertEqual(controller.processIdentifier, 7_002)

        let stopped = expectation(description: "retry process stopped")
        controller.stateChangeHandler = stopped.fulfill
        XCTAssertTrue(controller.stop())
        processes[1].finishTermination()
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertFalse(controller.isHolding)
    }

    func testUnexpectedExitClearsTheHoldAndReportsIt() async throws {
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, _ in process }
        var terminationCount = 0
        let terminated = expectation(description: "unexpected termination handled")
        controller.unexpectedTerminationHandler = {
            terminationCount += 1
            terminated.fulfill()
        }

        try controller.start()
        process.exit()
        await fulfillment(of: [terminated], timeout: 1)

        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
        XCTAssertEqual(terminationCount, 1)
    }

    func testStoppedProcessCannotReportAnUnexpectedExit() async throws {
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, _ in process }
        var terminationCount = 0
        let stopped = expectation(description: "expected termination handled")
        controller.stateChangeHandler = stopped.fulfill
        controller.unexpectedTerminationHandler = {
            terminationCount += 1
        }

        try controller.start()
        controller.stop()
        process.finishTermination()
        await fulfillment(of: [stopped], timeout: 1)

        XCTAssertEqual(terminationCount, 0)
    }

    func testStopReportsAChildThatAlreadyExitedAsUnexpected() async throws {
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, _ in process }
        let terminated = expectation(description: "prior exit reported")
        controller.unexpectedTerminationHandler = terminated.fulfill

        try controller.start()
        process.isRunning = false
        XCTAssertTrue(controller.stop())
        await fulfillment(of: [terminated], timeout: 1)

        XCTAssertFalse(controller.isHolding)
    }

    func testStopForceTerminatesAChildAfterTheGracePeriod() async throws {
        let process = FakeWakeProcess(ignoresTerminate: true)
        let controller = CaffeinateController(terminationGracePeriod: .zero) { _, _ in
            process
        }
        let stopped = expectation(description: "forced termination handled")
        controller.stateChangeHandler = stopped.fulfill

        try controller.start()
        XCTAssertTrue(controller.stop())
        await fulfillment(of: [stopped], timeout: 1)

        XCTAssertEqual(process.terminateCount, 1)
        XCTAssertEqual(process.forceTerminateCount, 1)
        XCTAssertFalse(controller.isHolding)
    }

    func testRealCaffeinateChildStartsAndStops() async throws {
        let child = Process()
        let controller = CaffeinateController { executableURL, arguments in
            child.executableURL = executableURL
            child.arguments = arguments
            return child
        }
        let stopped = expectation(description: "real termination handled")
        controller.stateChangeHandler = stopped.fulfill

        XCTAssertTrue(try controller.start())
        defer {
            if child.isRunning {
                child.terminate()
                let deadline = ContinuousClock.now + .milliseconds(250)
                while child.isRunning, ContinuousClock.now < deadline {
                    usleep(10_000)
                }
            }
            if child.isRunning {
                child.forceTerminate()
            }
            child.waitUntilExit()
        }
        let processIdentifier = try XCTUnwrap(controller.processIdentifier)
        XCTAssertEqual(kill(processIdentifier, 0), 0)

        XCTAssertTrue(controller.stop())
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertFalse(controller.isHolding)
        XCTAssertEqual(kill(processIdentifier, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testCaffeinateExitsWhenItsOwnerCrashes() throws {
        let output = Pipe()
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/sh")
        owner.arguments = [
            "-c",
            "/usr/bin/caffeinate -ims -w $$ & child=$!; echo $child; wait $child",
        ]
        owner.standardOutput = output
        try owner.run()
        try output.fileHandleForWriting.close()
        defer {
            if owner.isRunning {
                owner.terminate()
                owner.waitUntilExit()
            }
        }

        let line = try readLine(
            from: output.fileHandleForReading,
            timeoutMilliseconds: 1_000
        )
        let childPID = try XCTUnwrap(Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer {
            terminateAndConfirmExit(processIdentifier: childPID)
        }
        XCTAssertEqual(kill(childPID, 0), 0)

        XCTAssertEqual(kill(owner.processIdentifier, SIGKILL), 0)
        owner.waitUntilExit()

        let deadline = ContinuousClock.now + .seconds(2)
        while kill(childPID, 0) == 0, ContinuousClock.now < deadline {
            usleep(10_000)
        }
        XCTAssertEqual(kill(childPID, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private func terminateAndConfirmExit(processIdentifier: Int32) {
        guard kill(processIdentifier, 0) == 0 else {
            return
        }

        kill(processIdentifier, SIGTERM)
        var deadline = ContinuousClock.now + .milliseconds(250)
        while kill(processIdentifier, 0) == 0, ContinuousClock.now < deadline {
            usleep(10_000)
        }

        if kill(processIdentifier, 0) == 0 {
            kill(processIdentifier, SIGKILL)
            deadline = ContinuousClock.now + .seconds(1)
            while kill(processIdentifier, 0) == 0, ContinuousClock.now < deadline {
                usleep(10_000)
            }
        }

        XCTAssertEqual(kill(processIdentifier, 0), -1)
    }

    private func readLine(
        from handle: FileHandle,
        timeoutMilliseconds: Int32
    ) throws -> String {
        var descriptor = pollfd(
            fd: handle.fileDescriptor,
            events: Int16(POLLIN),
            revents: 0
        )
        let pollResult = poll(&descriptor, 1, timeoutMilliseconds)
        XCTAssertGreaterThan(pollResult, 0, "timed out waiting for child process identifier")
        guard pollResult > 0 else {
            throw TestError.readTimedOut
        }

        var data = Data()
        while true {
            guard let byte = try handle.read(upToCount: 1), !byte.isEmpty else {
                break
            }
            if byte[0] == UInt8(ascii: "\n") {
                break
            }
            data.append(byte)
        }
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}

private enum TestError: Error {
    case launchFailed
    case readTimedOut
}

private final class FakeWakeProcess: WakeProcess {
    var isRunning = false
    let processIdentifier: Int32
    private let runError: Error?
    private let ignoresTerminate: Bool
    private var terminationHandler: (@Sendable () -> Void)?
    private(set) var terminateCount = 0
    private(set) var forceTerminateCount = 0
    private(set) var waitCount = 0

    init(
        processIdentifier: Int32 = 7_001,
        runError: Error? = nil,
        ignoresTerminate: Bool = false
    ) {
        self.processIdentifier = processIdentifier
        self.runError = runError
        self.ignoresTerminate = ignoresTerminate
    }

    func run() throws {
        if let runError {
            throw runError
        }
        isRunning = true
    }

    func terminate() {
        terminateCount += 1
        guard !ignoresTerminate else {
            return
        }
        isRunning = false
    }

    func setTerminationHandler(_ handler: @escaping @Sendable () -> Void) {
        terminationHandler = handler
    }

    func waitUntilExit() {
        waitCount += 1
    }

    func forceTerminate() {
        forceTerminateCount += 1
        isRunning = false
        finishTermination()
    }

    func exit() {
        isRunning = false
        finishTermination()
    }

    func finishTermination() {
        terminationHandler?()
    }
}
