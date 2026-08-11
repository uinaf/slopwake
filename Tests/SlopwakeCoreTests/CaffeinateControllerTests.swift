import Darwin
import Foundation
import SlopwakeCore
import XCTest

@MainActor
final class CaffeinateControllerTests: XCTestCase {
    func testStartOwnsExactlyOneProcessAndStopReapsIt() throws {
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

        XCTAssertTrue(controller.stop())
        XCTAssertFalse(controller.stop())
        XCTAssertEqual(processes[0].terminateCount, 1)
        XCTAssertEqual(processes[0].waitCount, 1)
        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
    }

    func testExitedProcessCanBeReplaced() throws {
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
        XCTAssertEqual(controller.processIdentifier, 7_002)

        controller.stop()
    }

    func testLaunchFailureDoesNotClaimAHold() {
        let controller = CaffeinateController { _, _ in
            FakeWakeProcess(runError: TestError.launchFailed)
        }

        XCTAssertThrowsError(try controller.start())
        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
        XCTAssertFalse(controller.stop())
    }

    func testUnexpectedExitClearsTheHoldAndReportsIt() async throws {
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, _ in process }
        var terminationCount = 0
        controller.unexpectedTerminationHandler = {
            terminationCount += 1
        }

        try controller.start()
        process.exit()
        await Task.yield()

        XCTAssertFalse(controller.isHolding)
        XCTAssertNil(controller.processIdentifier)
        XCTAssertEqual(terminationCount, 1)
    }

    func testStoppedProcessCannotReportAnUnexpectedExit() async throws {
        let process = FakeWakeProcess()
        let controller = CaffeinateController { _, _ in process }
        var terminationCount = 0
        controller.unexpectedTerminationHandler = {
            terminationCount += 1
        }

        try controller.start()
        controller.stop()
        process.finishTermination()
        await Task.yield()

        XCTAssertEqual(terminationCount, 0)
    }

    func testRealCaffeinateChildStartsAndStops() throws {
        let controller = CaffeinateController()

        XCTAssertTrue(try controller.start())
        let processIdentifier = try XCTUnwrap(controller.processIdentifier)
        XCTAssertEqual(kill(processIdentifier, 0), 0)

        XCTAssertTrue(controller.stop())
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

        let line = try readLine(from: output.fileHandleForReading)
        let childPID = try XCTUnwrap(Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)))
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

    private func readLine(from handle: FileHandle) throws -> String {
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
}

private final class FakeWakeProcess: WakeProcess {
    var isRunning = false
    let processIdentifier: Int32
    private let runError: Error?
    private var terminationHandler: (@Sendable () -> Void)?
    private(set) var terminateCount = 0
    private(set) var waitCount = 0

    init(
        processIdentifier: Int32 = 7_001,
        runError: Error? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.runError = runError
    }

    func run() throws {
        if let runError {
            throw runError
        }
        isRunning = true
    }

    func terminate() {
        terminateCount += 1
        isRunning = false
    }

    func setTerminationHandler(_ handler: @escaping @Sendable () -> Void) {
        terminationHandler = handler
    }

    func waitUntilExit() {
        waitCount += 1
    }

    func exit() {
        isRunning = false
        finishTermination()
    }

    func finishTermination() {
        terminationHandler?()
    }
}
