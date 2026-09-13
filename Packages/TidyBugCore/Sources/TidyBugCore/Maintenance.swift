import Darwin
import Foundation

// MARK: - Model

public enum MaintenanceCategory: String, CaseIterable, Sendable {
    case network = "Network"
    case finder = "Finder & Launch Services"
    case memory = "Memory"
    case databases = "Databases"
    case storage = "Storage"
    case spotlight = "Spotlight"

    public var symbol: String {
        switch self {
        case .network: "network"
        case .finder: "macwindow"
        case .memory: "memorychip"
        case .databases: "cylinder.split.1x2"
        case .storage: "externaldrive"
        case .spotlight: "magnifyingglass"
        }
    }
}

public enum TaskReadiness: Sendable, Equatable {
    case ready
    /// Not needed right now (or unsafe at the moment) — the reason says why.
    case skip(String)
    /// Can't run on this Mac.
    case unavailable(String)

    public var isReady: Bool { self == .ready }
    public var reason: String? {
        switch self {
        case .ready: nil
        case .skip(let r), .unavailable(let r): r
        }
    }
}

/// One bounded, explainable maintenance step. Commands are run with `/bin/sh -c`,
/// joined with `&&`; admin tasks run together behind a single password prompt.
public struct MaintenanceTask: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let category: MaintenanceCategory
    public let requiresAdmin: Bool
    public let preselected: Bool
    public let warning: String?
    let commandsProvider: @Sendable () -> [String]
    let check: @Sendable () -> TaskReadiness

    public var commands: [String] { commandsProvider() }
    public var script: String { commands.joined(separator: " && ") }
    public func readiness() -> TaskReadiness { check() }
}

public enum MaintenanceOutcome: Sendable, Equatable {
    case applied
    case failed(String)
}

public struct MaintenanceResult: Sendable, Identifiable {
    public let id: String
    public let outcome: MaintenanceOutcome
    public let output: String
    public let duration: TimeInterval
}

// MARK: - Catalog

public enum Maintenance {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    public static var tasks: [MaintenanceTask] {
        [flushDNS, quickLook, launchServices, fontCaches, restartFinder, purgeMemory,
         mailIndex, safariHistory, thinSnapshots, detachImages, periodicScripts, spotlight]
    }

    static let flushDNS = MaintenanceTask(
        id: "flush-dns", title: "Flush DNS cache",
        detail: "Clears cached name lookups. Fixes sites that moved or stale VPN / hosts-file entries.",
        category: .network, requiresAdmin: true, preselected: true, warning: nil,
        commandsProvider: { ["dscacheutil -flushcache", "killall -HUP mDNSResponder"] },
        check: { .ready })

    static let quickLook = MaintenanceTask(
        id: "quicklook", title: "Reset Quick Look thumbnails",
        detail: "Clears the thumbnail cache and reloads preview generators. Fixes blank or outdated previews.",
        category: .finder, requiresAdmin: false, preselected: true, warning: nil,
        commandsProvider: { ["qlmanage -r cache", "qlmanage -r"] },
        check: { exists("/usr/bin/qlmanage") ? .ready : .unavailable("qlmanage not found") })

    static let launchServices = MaintenanceTask(
        id: "launch-services", title: "Rebuild Launch Services database",
        detail: "Re-registers apps and compacts the database. Fixes duplicate or stale “Open With” entries and wrong default apps.",
        category: .finder, requiresAdmin: false, preselected: false, warning: "Takes up to a minute.",
        commandsProvider: { ["\"\(lsregister)\" -gc -f -all local,system,user"] },
        check: { exists(lsregister) ? .ready : .unavailable("lsregister not found") })

    static let fontCaches = MaintenanceTask(
        id: "font-caches", title: "Clear user font caches",
        detail: "Removes your fontd databases so they are regenerated. Fixes garbled or missing fonts.",
        category: .finder, requiresAdmin: false, preselected: false,
        warning: "Restart open apps (or log out) afterwards.",
        commandsProvider: { ["atsutil databases -removeUser"] },
        check: { exists("/usr/bin/atsutil") ? .ready : .unavailable("atsutil not found") })

    static let restartFinder = MaintenanceTask(
        id: "restart-finder", title: "Restart Finder and Dock",
        detail: "Relaunches Finder and the Dock to refresh icons, badges and sidebar state.",
        category: .finder, requiresAdmin: false, preselected: false, warning: "Open Finder windows close and reopen.",
        commandsProvider: { ["killall Finder", "killall Dock"] },
        check: { .ready })

    static let purgeMemory = MaintenanceTask(
        id: "purge-memory", title: "Free inactive memory",
        detail: "Flushes the disk cache and inactive pages. Only useful under memory pressure.",
        category: .memory, requiresAdmin: true, preselected: true, warning: nil,
        commandsProvider: { ["purge"] },
        check: {
            guard exists("/usr/sbin/purge") else { return .unavailable("purge not found") }
            let level = Diagnosis.memoryPressureLevel()
            return level > 1 ? .ready : .skip("Memory pressure is normal; nothing to reclaim.")
        })

    static let mailIndex = MaintenanceTask(
        id: "mail-vacuum", title: "Compact Mail envelope index",
        detail: "Runs SQLite VACUUM on Mail's Envelope Index. Speeds up search and message lists in large mailboxes.",
        category: .databases, requiresAdmin: false, preselected: true, warning: nil,
        commandsProvider: {
            guard let db = mailEnvelopeIndex() else { return [] }
            return vacuum(db)
        },
        check: { sqliteCheck(path: mailEnvelopeIndex(), app: "Mail") })

    static let safariHistory = MaintenanceTask(
        id: "safari-vacuum", title: "Compact Safari history",
        detail: "Runs SQLite VACUUM on Safari's History.db to reclaim free pages.",
        category: .databases, requiresAdmin: false, preselected: true, warning: nil,
        commandsProvider: { vacuum(NSHomeDirectory() + "/Library/Safari/History.db") },
        check: { sqliteCheck(path: NSHomeDirectory() + "/Library/Safari/History.db", app: "Safari") })

    static let thinSnapshots = MaintenanceTask(
        id: "thin-snapshots", title: "Thin local Time Machine snapshots",
        detail: "Asks APFS to release local snapshots now instead of waiting for space pressure.",
        category: .storage, requiresAdmin: true, preselected: true, warning: nil,
        commandsProvider: { ["tmutil thinlocalsnapshots / 999999999999 4"] },
        check: {
            let r = CommandRunner.runSync("tmutil", ["listlocalsnapshots", "/"], timeout: 15)
            let count = r.output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
            return count > 0 ? .ready : .skip("No local snapshots.")
        })

    static let detachImages = MaintenanceTask(
        id: "detach-images", title: "Eject mounted disk images",
        detail: "Detaches .dmg installers still mounted under /Volumes. System and simulator images are left alone.",
        category: .storage, requiresAdmin: false, preselected: false, warning: nil,
        commandsProvider: { mountedUserImages().map { "hdiutil detach \"\($0.device)\"" } },
        check: {
            let images = mountedUserImages()
            return images.isEmpty ? .skip("No user-mounted disk images.") : .ready
        })

    static let periodicScripts = MaintenanceTask(
        id: "periodic", title: "Run periodic maintenance scripts",
        detail: "Runs the daily, weekly and monthly system maintenance scripts.",
        category: .storage, requiresAdmin: true, preselected: false, warning: nil,
        commandsProvider: { ["periodic daily weekly monthly"] },
        check: { exists("/usr/sbin/periodic") ? .ready : .unavailable("Removed in this version of macOS.") })

    static let spotlight = MaintenanceTask(
        id: "spotlight-rebuild", title: "Rebuild Spotlight index",
        detail: "Erases and rebuilds the index for the startup disk. Fixes missing or stale search results.",
        category: .spotlight, requiresAdmin: true, preselected: false,
        warning: "Heavy: reindexing can take hours and uses CPU and battery meanwhile.",
        commandsProvider: { ["mdutil -E /"] },
        check: {
            let r = CommandRunner.runSync("mdutil", ["-s", "/"], timeout: 15)
            return r.output.contains("Indexing enabled") ? .ready : .skip("Indexing is disabled for /.")
        })

    // MARK: Helpers

    static func exists(_ path: String) -> Bool { FileManager.default.isExecutableFile(atPath: path) }

    static func vacuum(_ db: String) -> [String] {
        let q = shellQuote(db)
        return ["du -h \(q)", "sqlite3 \(q) 'VACUUM;'", "du -h \(q)"]
    }

    static func sqliteCheck(path: String?, app: String) -> TaskReadiness {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            return .skip("\(app) database not found (or Full Disk Access is off).")
        }
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return .skip("Needs Full Disk Access to open \(app)'s database.")
        }
        try? handle.close()
        if CommandRunner.runSync("pgrep", ["-x", app], timeout: 5).succeeded {
            return .skip("Quit \(app) first; its database is in use.")
        }
        return .ready
    }

    static func mailEnvelopeIndex() -> String? {
        let root = NSHomeDirectory() + "/Library/Mail"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .filter { $0.hasPrefix("V") }
            .sorted { (Int($0.dropFirst()) ?? 0) > (Int($1.dropFirst()) ?? 0) }
        for v in versions {
            let p = "\(root)/\(v)/MailData/Envelope Index"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    struct MountedImage { let imagePath: String; let device: String; let mountPoint: String }

    /// Disk images mounted under /Volumes, excluding system and simulator runtimes.
    static func mountedUserImages() -> [MountedImage] {
        let r = CommandRunner.runSync("hdiutil", ["info", "-plist"], timeout: 15)
        guard r.succeeded, let data = r.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [] }
        var out: [MountedImage] = []
        for image in images {
            let path = image["image-path"] as? String ?? ""
            if path.hasPrefix("/System/") || path.hasPrefix("/Library/Developer/") || path.contains("CoreSimulator") { continue }
            for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                guard let mount = entity["mount-point"] as? String, mount.hasPrefix("/Volumes/"),
                      let dev = entity["dev-entry"] as? String else { continue }
                out.append(MountedImage(imagePath: path, device: dev, mountPoint: mount))
            }
        }
        return out
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

// MARK: - Engine

public enum MaintenanceEngine {
    /// Runs a non-admin task as the current user.
    public static func run(_ task: MaintenanceTask) -> MaintenanceResult {
        let start = Date()
        let script = task.script
        guard !script.isEmpty else {
            return MaintenanceResult(id: task.id, outcome: .failed("Nothing to run"), output: "", duration: 0)
        }
        let r = CommandRunner.runSync("/bin/sh", ["-c", script], timeout: 300)
        return MaintenanceResult(id: task.id, outcome: r.succeeded ? .applied : .failed("Exit status \(r.status)"),
                                 output: r.output.trimmingCharacters(in: .whitespacesAndNewlines),
                                 duration: Date().timeIntervalSince(start))
    }

    /// Runs all admin tasks behind one administrator prompt (osascript), then
    /// splits the combined output back into per-task results using markers.
    public static func runAdmin(_ tasks: [MaintenanceTask]) -> [MaintenanceResult] {
        guard !tasks.isEmpty else { return [] }
        let start = Date()
        let shell = batchScript(tasks)
        let r = CommandRunner.runSync("/usr/bin/osascript", ["-e", appleScript(for: shell)], timeout: 3600)
        let elapsed = Date().timeIntervalSince(start)
        guard r.succeeded else {
            let cancelled = r.output.contains("-128") || r.output.localizedCaseInsensitiveContains("cancel")
            let reason = cancelled ? "Authentication cancelled" : "Admin run failed"
            return tasks.map { MaintenanceResult(id: $0.id, outcome: .failed(reason),
                                                 output: r.output.trimmingCharacters(in: .whitespacesAndNewlines), duration: 0) }
        }
        let parsed = parseMarkers(r.output)
        return tasks.map { t in
            if let p = parsed[t.id] {
                return MaintenanceResult(id: t.id, outcome: p.status == 0 ? .applied : .failed("Exit status \(p.status)"),
                                         output: p.output, duration: elapsed / Double(tasks.count))
            }
            return MaintenanceResult(id: t.id, outcome: .failed("No result reported"), output: "", duration: 0)
        }
    }

    static let beginMarker = "__TB_BEGIN__"
    static let endMarker = "__TB_END__"

    static func batchScript(_ tasks: [MaintenanceTask]) -> String {
        tasks.map { t in
            "echo \(beginMarker) \(t.id); ( \(t.script) ) 2>&1; echo \(endMarker) \(t.id) $?"
        }.joined(separator: "; ")
    }

    static func appleScript(for shell: String) -> String {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    /// `do shell script` returns \r line endings; accept either.
    static func parseMarkers(_ output: String) -> [String: (status: Int32, output: String)] {
        var result: [String: (Int32, String)] = [:]
        var current: String?
        var buffer: [String] = []
        for raw in output.components(separatedBy: CharacterSet.newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(beginMarker + " ") {
                current = String(line.dropFirst(beginMarker.count + 1))
                buffer = []
            } else if line.hasPrefix(endMarker + " ") {
                let parts = line.dropFirst(endMarker.count + 1).split(separator: " ")
                if parts.count == 2, let status = Int32(parts[1]) {
                    result[String(parts[0])] = (status, buffer.joined(separator: "\n"))
                }
                current = nil
            } else if current != nil, !line.isEmpty {
                buffer.append(raw)
            }
        }
        return result.mapValues { (status: $0.0, output: $0.1) }
    }

    public static func log(_ results: [MaintenanceResult], tasks: [MaintenanceTask], log: OperationLog = .shared) {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        log.record(results.map { r in
            let task = byID[r.id]
            var message = String(r.output.suffix(500))
            if case .failed(let reason) = r.outcome { message = reason + (message.isEmpty ? "" : ": " + message) }
            return LogEntry(date: Date(), source: "optimize", rule: r.id, path: task?.title ?? r.id, bytes: 0,
                            mode: .command, success: r.outcome == .applied, message: message.isEmpty ? nil : message)
        })
    }
}

// MARK: - Diagnosis

public enum FindingSeverity: Int, Sendable, Comparable {
    case ok, info, warning
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct Finding: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: FindingSeverity
}

public struct SystemSummary: Sendable {
    public let memoryTotal: UInt64
    public let memoryUsed: UInt64
    public let diskTotal: Int64
    public let diskUsed: Int64
    public let uptime: TimeInterval

    public var uptimeText: String { Diagnosis.formatUptime(uptime) }
}

public enum Diagnosis {
    public static func summary() -> SystemSummary {
        let mem = memory()
        let vol = VolumeInfo.current()
        return SystemSummary(memoryTotal: mem.total, memoryUsed: mem.used, diskTotal: vol.total,
                             diskUsed: vol.used, uptime: uptime())
    }

    /// Takes ~2 s: CPU is sampled twice to find sustained hogs.
    public static func run() -> [Finding] {
        var findings: [Finding] = []

        let up = uptime()
        let days = Int(up / 86_400)
        findings.append(days >= 14
            ? Finding(id: "uptime", title: "Up for \(formatUptime(up))",
                      detail: "A restart clears leaked memory, stuck daemons and pending updates.", severity: .warning)
            : Finding(id: "uptime", title: "Uptime \(formatUptime(up))", detail: "No restart needed.", severity: .ok))

        let level = memoryPressureLevel()
        switch level {
        case 4: findings.append(Finding(id: "pressure", title: "Memory pressure critical",
                                        detail: "Quit memory-heavy apps; macOS is compressing and swapping heavily.", severity: .warning))
        case 2: findings.append(Finding(id: "pressure", title: "Memory pressure elevated",
                                        detail: "Consider quitting unused apps or browser tabs.", severity: .info))
        default: findings.append(Finding(id: "pressure", title: "Memory pressure normal", detail: "No action needed.", severity: .ok))
        }

        let swap = swapUsage()
        let gb = Double(swap.used) / 1_073_741_824
        if gb >= 4 {
            findings.append(Finding(id: "swap", title: String(format: "%.1f GB swap in use", gb),
                                    detail: "Heavy swapping slows everything down; a restart resets it.", severity: .warning))
        } else if gb >= 1 {
            findings.append(Finding(id: "swap", title: String(format: "%.1f GB swap in use", gb),
                                    detail: "Moderate swap. Fine unless the Mac feels slow.", severity: .info))
        } else {
            findings.append(Finding(id: "swap", title: "Swap minimal", detail: String(format: "%.0f MB in use.", gb * 1024), severity: .ok))
        }

        let hogs = sustainedCPUHogs()
        if hogs.isEmpty {
            findings.append(Finding(id: "cpu", title: "No sustained high-CPU processes", detail: "Sampled twice, 2 s apart.", severity: .ok))
        } else {
            let list = hogs.prefix(3).map { "\($0.name) (\(Int($0.cpu))%)" }.joined(separator: ", ")
            findings.append(Finding(id: "cpu", title: "Sustained high CPU", detail: "\(list). Quit or restart it if unexpected.",
                                    severity: .warning))
        }

        let vol = VolumeInfo.current()
        let freeFraction = vol.total > 0 ? Double(vol.available) / Double(vol.total) : 1
        if freeFraction < 0.1 {
            findings.append(Finding(id: "disk", title: "Low free space (\(vol.available.formattedBytes))",
                                    detail: "Below 10% free, macOS slows down and updates may fail. Run a Clean scan.", severity: .warning))
        } else {
            findings.append(Finding(id: "disk", title: "\(vol.available.formattedBytes) free",
                                    detail: "\(Int(freeFraction * 100))% of the startup disk is free.", severity: freeFraction < 0.2 ? .info : .ok))
        }

        let md = CommandRunner.runSync("mdutil", ["-s", "/"], timeout: 15).output
        if md.contains("Indexing enabled") {
            findings.append(Finding(id: "spotlight", title: "Spotlight indexing enabled", detail: "Index is active for /.", severity: .ok))
        } else if md.localizedCaseInsensitiveContains("disabled") {
            findings.append(Finding(id: "spotlight", title: "Spotlight indexing disabled",
                                    detail: "Search won't find new files. Enable with `sudo mdutil -i on /`.", severity: .info))
        }
        return findings
    }

    // MARK: Probes

    public static func memory() -> (total: UInt64, used: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (total, 0) }
        let page = UInt64(vm_kernel_page_size)
        let used = (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (total, min(used, total))
    }

    public static func uptime() -> TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - TimeInterval(tv.tv_sec)
    }

    /// 1 = normal, 2 = warning, 4 = critical.
    public static func memoryPressureLevel() -> Int32 {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 1 }
        return level
    }

    public static func swapUsage() -> (total: UInt64, used: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_total, usage.xsu_used)
    }

    struct CPUProcess { let pid: Int; let cpu: Double; let name: String }

    static func sampleCPU() -> [Int: CPUProcess] {
        let r = CommandRunner.runSync("ps", ["-Aceo", "pid,pcpu,comm", "-r"], timeout: 10)
        var out: [Int: CPUProcess] = [:]
        for line in r.output.split(separator: "\n").dropFirst().prefix(40) {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let cpu = Double(parts[1]) else { continue }
            out[pid] = CPUProcess(pid: pid, cpu: cpu, name: String(parts[2]))
        }
        return out
    }

    /// Processes at ≥ 80% CPU in two samples taken ~2 s apart.
    static func sustainedCPUHogs(threshold: Double = 80) -> [CPUProcess] {
        let first = sampleCPU()
        Thread.sleep(forTimeInterval: 2)
        let second = sampleCPU()
        return second.values
            .filter { $0.cpu >= threshold && (first[$0.pid]?.cpu ?? 0) >= threshold }
            .sorted { $0.cpu > $1.cpu }
    }

    static func formatUptime(_ t: TimeInterval) -> String {
        let d = Int(t / 86_400), h = Int(t.truncatingRemainder(dividingBy: 86_400) / 3600)
        if d > 0 { return "\(d)d \(h)h" }
        return "\(h)h \(Int(t.truncatingRemainder(dividingBy: 3600) / 60))m"
    }
}
