import Darwin
import SlopwakeCore

struct SystemProcessSnapshot: Sendable {
    let processes: [AgentProcessSample]
    let unavailableProcessIdentifiers: Set<Int32>
}

struct SystemProcessSnapshotSource: Sendable {
    func snapshot(bundleIdentifiers: [pid_t: String]) -> SystemProcessSnapshot? {
        let processCount = proc_listallpids(nil, 0)
        guard processCount > 0 else {
            return nil
        }

        var processIdentifiers = [pid_t](
            repeating: 0,
            count: Int(processCount) + 64
        )
        let listedCount = processIdentifiers.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard listedCount > 0 else {
            return nil
        }

        var processes: [AgentProcessSample] = []
        var unavailableProcessIdentifiers: Set<Int32> = []
        for processIdentifier in processIdentifiers.prefix(Int(listedCount)) {
            switch sample(
                processIdentifier: processIdentifier,
                bundleIdentifier: bundleIdentifiers[processIdentifier]
            ) {
            case let .available(process):
                processes.append(process)
            case .unavailable:
                unavailableProcessIdentifiers.insert(processIdentifier)
            case .ignored:
                break
            }
        }
        return SystemProcessSnapshot(
            processes: processes,
            unavailableProcessIdentifiers: unavailableProcessIdentifiers
        )
    }

    private enum SampleResult {
        case available(AgentProcessSample)
        case unavailable
        case ignored
    }

    private func sample(
        processIdentifier: pid_t,
        bundleIdentifier: String?
    ) -> SampleResult {
        guard processIdentifier > 0 else {
            return .ignored
        }

        var bsdInfo = proc_bsdinfo()
        let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &bsdInfo,
            bsdInfoSize
        ) == bsdInfoSize else {
            return .unavailable
        }
        guard bsdInfo.pbi_uid == getuid() else {
            return .ignored
        }

        var taskInfo = proc_taskinfo()
        let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(
            processIdentifier,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            taskInfoSize
        ) == taskInfoSize else {
            return .unavailable
        }

        var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let nameLength = proc_name(
            processIdentifier,
            &nameBuffer,
            UInt32(nameBuffer.count)
        )
        guard nameLength > 0 else {
            return .unavailable
        }

        let startTimeMicroseconds = bsdInfo.pbi_start_tvsec.multipliedReportingOverflow(by: 1_000_000)
        guard !startTimeMicroseconds.overflow else {
            return .unavailable
        }
        let fullStartTime = startTimeMicroseconds.partialValue.addingReportingOverflow(
            bsdInfo.pbi_start_tvusec
        )
        guard !fullStartTime.overflow else {
            return .unavailable
        }
        let cpuTime = taskInfo.pti_total_user.addingReportingOverflow(taskInfo.pti_total_system)
        guard !cpuTime.overflow else {
            return .unavailable
        }
        let terminalFlags = UInt32(PROC_FLAG_CTTY | PROC_FLAG_CONTROLT)

        return .available(AgentProcessSample(
            identity: AgentProcessIdentity(
                processIdentifier: processIdentifier,
                startTimeMicroseconds: fullStartTime.partialValue
            ),
            parentProcessIdentifier: bsdInfo.pbi_ppid == 0 ? nil : Int32(bsdInfo.pbi_ppid),
            executableName: String(
                decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
                as: UTF8.self
            ),
            bundleIdentifier: bundleIdentifier,
            hasControllingTerminal: bsdInfo.pbi_flags & terminalFlags != 0,
            cumulativeCPUTimeNanoseconds: cpuTime.partialValue
        ))
    }
}
