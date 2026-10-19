import AppKit
import Darwin
import Foundation

/// Snapshot lifetime evidence, not a remembered app authorization or signer check.
struct SnapshotProcessIdentity: Equatable {
    let pid: pid_t
    let launchedAt: Date?
    let executablePath: String?

    init(pid: pid_t, launchedAt: Date?, executablePath: String?) {
        self.pid = pid
        self.launchedAt = launchedAt
        self.executablePath = executablePath
    }

    init(_ app: NSRunningApplication) {
        self = Self.read(pid: app.processIdentifier)
    }

    static func read(pid: pid_t) -> SnapshotProcessIdentity {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathCount = proc_pidpath(pid, &path, UInt32(path.count))
        let started = count == size && info.pbi_start_tvsec > 0
            ? Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
            : nil
        let executable = pathCount > 0 ? String(bytes: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) : nil
        return SnapshotProcessIdentity(
            pid: pid, launchedAt: started,
            executablePath: executable.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        )
    }

    func matches(_ current: SnapshotProcessIdentity?) -> Bool {
        guard pid > 0, launchedAt != nil, let executablePath, !executablePath.isEmpty else { return false }
        return self == current
    }
}

/// All aliases share one captured incarnation. Refusal removes every alias so
/// later input cannot recover stale indices by choosing another app name.
struct AppSnapshotCache {
    private var entries: [String: AppSnapshot] = [:]

    mutating func store(_ snapshot: AppSnapshot, query: String) {
        let keys = [query, snapshot.app.name, snapshot.app.bundleIdentifier ?? ""]
        for key in keys where !key.isEmpty { entries[key.lowercased()] = snapshot }
    }

    mutating func require(_ query: String, isCurrent: (RunningAppDescriptor) -> Bool) throws -> AppSnapshot {
        guard let snapshot = entries[query.lowercased()] else {
            throw ComputerUseError.stateUnavailable("Call get_app_state for this app before sending input.")
        }
        guard isCurrent(snapshot.app) else {
            let identity = snapshot.app.snapshotProcessIdentity
            entries = entries.filter { $0.value.app.snapshotProcessIdentity != identity }
            throw ComputerUseError.stateUnavailable("The app process changed or exited. Call get_app_state again before sending more input.")
        }
        return snapshot
    }
}

func snapshotAppIsCurrent(_ app: RunningAppDescriptor) -> Bool {
    guard !app.runningApplication.isTerminated else { return false }
    return app.snapshotProcessIdentity.matches(SnapshotProcessIdentity.read(pid: app.pid))
}
