import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import TidyBugCore

// MARK: - Value types

struct SeriesPoint: Identifiable, Equatable, Sendable {
    let id: Int
    let value: Double
}

enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

struct MemoryStats: Equatable, Sendable {
    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var free: UInt64 = 0
    var pressure: MemoryPressure = .normal
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0

    /// Activity Monitor's "Memory Used": app + wired + compressed.
    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct BatteryStats: Equatable, Sendable {
    var level: Double          // 0…1
    var isCharging: Bool
    var isCharged: Bool
    var onAC: Bool
    var cycles: Int?
    var temperature: Double?   // °C
    var healthFraction: Double? // max capacity / design capacity
    var condition: String?     // "Good", "Fair", "Poor"
    var minutesRemaining: Int?

    var stateLabel: String {
        if isCharged { return "Charged" }
        if isCharging { return "Charging" }
        return onAC ? "On power adapter" : "On battery"
    }
}

struct ProcessStat: Identifiable, Equatable, Sendable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let cpu: Double        // fraction of one core (can exceed 1)
    let memory: UInt64     // resident bytes
}

struct HealthFactor: Identifiable, Equatable, Sendable {
    var id: String { label }
    let label: String
    let detail: String
    let penalty: Int
}

struct MachineInfo: Sendable {
    var name = "Mac"
    var chip = "Apple Silicon"
    var memoryGB = 0
    var os = ""
    var performanceCores = 0
    var efficiencyCores = 0

    var subtitle: String { [name, chip, "\(memoryGB) GB", os].filter { !$0.isEmpty }.joined(separator: " · ") }
}

/// One sampling pass, produced off the main actor.
struct MonitorSnapshot: Sendable {
    var cpuTotal: Double = 0
    var cores: [Double] = []
    var load: [Double] = [0, 0, 0]
    var memory = MemoryStats()
    var gpu: Double?
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var netDown: Double = 0
    var netUp: Double = 0
    var interface: String?
    var ip: String?
    var battery: BatteryStats?
    var batterySampled = false
    var processes: [ProcessStat]?
    var zombies = 0
    var uptime: TimeInterval = 0
    var thermal: ProcessInfo.ThermalState = .nominal
}

// MARK: - Monitor

/// Live system metrics, sampled once a second while at least one view is watching.
///
/// Usage: call `start()` on appear and `stop()` on disappear (reference-counted).
@MainActor @Observable
final class SystemMonitor {
    static let shared = SystemMonitor()
    static let historyLength = 120

    private(set) var machine = MachineInfo()
    private(set) var isRunning = false
    private(set) var tick = 0

    // CPU
    private(set) var cpu: Double = 0
    private(set) var cores: [Double] = []
    private(set) var load: [Double] = [0, 0, 0]
    // Memory
    private(set) var memory = MemoryStats()
    // GPU
    private(set) var gpu: Double?
    // Disk / network (bytes per second)
    private(set) var diskRead: Double = 0
    private(set) var diskWrite: Double = 0
    private(set) var netDown: Double = 0
    private(set) var netUp: Double = 0
    private(set) var interface: String?
    private(set) var ip: String?
    // Power / thermal
    private(set) var battery: BatteryStats?
    private(set) var thermal: ProcessInfo.ThermalState = .nominal
    // Processes
    private(set) var processes: [ProcessStat] = []
    private(set) var zombieCount = 0
    private(set) var uptime: TimeInterval = 0
    // Health
    private(set) var health = 100
    private(set) var healthFactors: [HealthFactor] = []

    // Histories (last 120 samples) for sparklines.
    private(set) var cpuHistory: [SeriesPoint] = []
    private(set) var memoryHistory: [SeriesPoint] = []
    private(set) var gpuHistory: [SeriesPoint] = []
    private(set) var readHistory: [SeriesPoint] = []
    private(set) var writeHistory: [SeriesPoint] = []
    private(set) var downHistory: [SeriesPoint] = []
    private(set) var upHistory: [SeriesPoint] = []

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let sampler = MonitorSampler()

    init() {
        Task.detached(priority: .utility) { [weak self] in
            let info = MonitorSampler.machineInfo()
            await MainActor.run { self?.machine = info }
        }
    }

    func start() {
        watchers += 1
        guard task == nil else { return }
        isRunning = true
        let sampler = self.sampler
        task = Task.detached(priority: .utility) { [weak self] in
            var n = 0
            while !Task.isCancelled {
                let snap = sampler.sample(tick: n)
                await self?.apply(snap)
                n += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func apply(_ s: MonitorSnapshot) {
        tick += 1
        cpu = s.cpuTotal
        cores = s.cores
        load = s.load
        memory = s.memory
        gpu = s.gpu
        diskRead = s.diskRead
        diskWrite = s.diskWrite
        netDown = s.netDown
        netUp = s.netUp
        interface = s.interface
        ip = s.ip
        if s.batterySampled { battery = s.battery }
        thermal = s.thermal
        if let p = s.processes {
            processes = p
            zombieCount = s.zombies
        }
        uptime = s.uptime
        #if DEBUG
        if Self.demoMode { applyDemoOverrides() }
        #endif

        push(&cpuHistory, s.cpuTotal)
        push(&memoryHistory, s.memory.usedFraction)
        push(&gpuHistory, s.gpu ?? 0)
        push(&readHistory, s.diskRead)
        push(&writeHistory, s.diskWrite)
        push(&downHistory, s.netDown)
        push(&upHistory, s.netUp)
        computeHealth()
    }

    #if DEBUG
    /// Demo mode (marketing screenshots): hide identifying details.
    static var demoMode = false

    private func applyDemoOverrides() {
        machine.name = "MacBook Pro"
        interface = "en0"
        ip = "10.0.1.24"
        let base: [(String, Double, UInt64)] = [
            ("Xcode", 0.42, 3_900_000_000), ("Simulator", 0.24, 1_600_000_000), ("node", 0.19, 820_000_000),
            ("com.docker.backend", 0.12, 2_100_000_000), ("Safari", 0.08, 1_200_000_000),
            ("Slack", 0.05, 640_000_000), ("Figma", 0.04, 910_000_000), ("Spotify", 0.02, 380_000_000),
        ]
        processes = base.enumerated().map { i, p in
            ProcessStat(pid: pid_t(1200 + i * 317), name: p.0,
                        cpu: max(0.005, p.1 * Double.random(in: 0.85...1.15)), memory: p.2)
        }
        zombieCount = 0
    }
    #endif

    private func push(_ series: inout [SeriesPoint], _ value: Double) {
        series.append(SeriesPoint(id: tick, value: value))
        if series.count > Self.historyLength { series.removeFirst(series.count - Self.historyLength) }
    }

    /// Health score, 0–100. Starts at 100 and subtracts:
    /// - CPU: sustained load (30 s average) above 70 % costs 0.6 pt per point, up to 18.
    /// - Memory pressure: warning −15, critical −30.
    /// - Swap in use: −2 per GB, up to −10.
    /// - Disk: under 20 % free −10, under 10 % free −20.
    /// - Thermal state: fair −5, serious −15, critical −30.
    /// - Battery: condition other than normal −10; max capacity under 80 % −5.
    /// - Uptime: over 14 days −5, over 30 days −10 (a restart clears leaked resources).
    private func computeHealth() {
        var f: [HealthFactor] = []
        let recent = cpuHistory.suffix(30).map(\.value)
        let avg = recent.isEmpty ? 0 : recent.reduce(0, +) / Double(recent.count)
        let cpuPenalty = min(18, Int(max(0, avg * 100 - 70) * 0.6))
        f.append(HealthFactor(label: "CPU", detail: String(format: "%.0f%% average over 30 s", avg * 100), penalty: cpuPenalty))

        let memPenalty = memory.pressure == .critical ? 30 : (memory.pressure == .warning ? 15 : 0)
        f.append(HealthFactor(label: "Memory pressure", detail: memory.pressure.label, penalty: memPenalty))

        let swapGB = Double(memory.swapUsed) / 1_073_741_824
        f.append(HealthFactor(label: "Swap", detail: String(format: "%.1f GB in use", swapGB), penalty: min(10, Int(swapGB * 2))))

        let vol = VolumeInfo.current()
        let freeFraction = vol.total > 0 ? Double(vol.available) / Double(vol.total) : 1
        let diskPenalty = freeFraction < 0.1 ? 20 : (freeFraction < 0.2 ? 10 : 0)
        f.append(HealthFactor(label: "Disk space", detail: String(format: "%.0f%% free", freeFraction * 100), penalty: diskPenalty))

        let thermalPenalty: Int
        switch thermal {
        case .fair: thermalPenalty = 5
        case .serious: thermalPenalty = 15
        case .critical: thermalPenalty = 30
        default: thermalPenalty = 0
        }
        f.append(HealthFactor(label: "Thermals", detail: thermal.label, penalty: thermalPenalty))

        if let b = battery {
            var p = 0
            if let c = b.condition, c != "Good", c != "Normal" { p += 10 }
            if let h = b.healthFraction, h < 0.8 { p += 5 }
            let detail = [b.condition, b.healthFraction.map { String(format: "%.0f%% capacity", $0 * 100) }]
                .compactMap { $0 }.joined(separator: " · ")
            f.append(HealthFactor(label: "Battery", detail: detail.isEmpty ? "—" : detail, penalty: p))
        }

        let days = uptime / 86_400
        f.append(HealthFactor(label: "Uptime", detail: formatUptime(uptime), penalty: days > 30 ? 10 : (days > 14 ? 5 : 0)))

        healthFactors = f
        health = max(0, min(100, 100 - f.reduce(0) { $0 + $1.penalty }))
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

func formatUptime(_ t: TimeInterval) -> String {
    let total = Int(t)
    let d = total / 86_400, h = (total % 86_400) / 3600, m = (total % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

func formatRate(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file) + "/s"
}

// MARK: - Sampler (off main actor)

/// Holds previous counters to compute deltas. Only used from the single sampling task.
final class MonitorSampler: @unchecked Sendable {
    private struct CoreTicks { var user: UInt64; var system: UInt64; var idle: UInt64; var nice: UInt64 }

    private var prevCores: [CoreTicks] = []
    private var prevDisk: (read: UInt64, write: UInt64, time: TimeInterval)?
    private var prevNet: [String: (ib: UInt32, ob: UInt32)] = [:]
    private var prevNetTime: TimeInterval?
    private var prevProcCPU: [pid_t: UInt64] = [:]
    private var prevProcTime: UInt64 = 0
    private var cachedBattery: BatteryStats?
    /// Multiplier converting pti_total_* into nanoseconds (mach ticks on Apple silicon).
    private lazy var procTimeScale: Double = Self.detectProcTimeScale()

    func sample(tick: Int) -> MonitorSnapshot {
        var s = MonitorSnapshot()
        let (total, cores) = sampleCPU()
        s.cpuTotal = total
        s.cores = cores
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        s.load = loads
        s.memory = sampleMemory()
        s.gpu = sampleGPU()
        (s.diskRead, s.diskWrite) = sampleDisk()
        let net = sampleNetwork()
        s.netDown = net.down
        s.netUp = net.up
        s.interface = net.interface
        s.ip = net.ip
        if tick % 5 == 0 {
            cachedBattery = Self.sampleBattery()
            s.batterySampled = true
        }
        s.battery = cachedBattery
        if tick % 2 == 0 {
            let p = sampleProcesses()
            s.processes = tick == 0 ? [] : p.top
            s.zombies = p.zombies
        }
        s.uptime = Self.uptime()
        s.thermal = ProcessInfo.processInfo.thermalState
        return s
    }

    // MARK: CPU

    private func sampleCPU() -> (Double, [Double]) {
        var numCPU: natural_t = 0
        var infoPtr: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &infoPtr, &count) == KERN_SUCCESS,
              let info = infoPtr else { return (0, []) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        var current: [CoreTicks] = []
        var cores: [Double] = []
        var usedAll: UInt64 = 0, totalAll: UInt64 = 0
        for i in 0..<Int(numCPU) {
            let base = Int(CPU_STATE_MAX) * i
            func v(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[base + Int(state)])) }
            let t = CoreTicks(user: v(CPU_STATE_USER), system: v(CPU_STATE_SYSTEM), idle: v(CPU_STATE_IDLE), nice: v(CPU_STATE_NICE))
            current.append(t)
            if i < prevCores.count {
                let p = prevCores[i]
                let used = (t.user &- p.user) &+ (t.system &- p.system) &+ (t.nice &- p.nice)
                let all = used &+ (t.idle &- p.idle)
                cores.append(all > 0 ? Double(used) / Double(all) : 0)
                usedAll &+= used
                totalAll &+= all
            } else {
                cores.append(0)
            }
        }
        prevCores = current
        return (totalAll > 0 ? Double(usedAll) / Double(totalAll) : 0, cores)
    }

    // MARK: Memory

    private func sampleMemory() -> MemoryStats {
        var m = MemoryStats()
        m.total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            var pageSize: vm_size_t = 0
            host_page_size(mach_host_self(), &pageSize)
            let ps = UInt64(pageSize)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            m.app = (internalPages > purgeable ? internalPages - purgeable : 0) * ps
            m.wired = UInt64(stats.wire_count) * ps
            m.compressed = UInt64(stats.compressor_page_count) * ps
            m.cached = (UInt64(stats.external_page_count) + purgeable) * ps
            let accounted = m.app + m.wired + m.compressed + m.cached
            m.free = m.total > accounted ? m.total - accounted : 0
        }
        if let level: Int32 = Self.sysctlValue("kern.memorystatus_vm_pressure_level") {
            m.pressure = MemoryPressure(rawValue: Int(level)) ?? .normal
        }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            m.swapUsed = swap.xsu_used
            m.swapTotal = swap.xsu_total
        }
        return m
    }

    // MARK: GPU

    private func sampleGPU() -> Double? {
        let values = Self.ioProperties(matching: "IOAccelerator").compactMap { dict -> Double? in
            guard let stats = dict["PerformanceStatistics"] as? [String: Any] else { return nil }
            return (stats["Device Utilization %"] as? NSNumber)?.doubleValue
        }
        return values.max().map { min(1, $0 / 100) }
    }

    // MARK: Disk

    private func sampleDisk() -> (Double, Double) {
        var read: UInt64 = 0, write: UInt64 = 0
        for dict in Self.ioProperties(matching: "IOBlockStorageDriver") {
            guard let stats = dict["Statistics"] as? [String: Any] else { continue }
            read &+= (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write &+= (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        let now = Date().timeIntervalSinceReferenceDate
        defer { prevDisk = (read, write, now) }
        guard let p = prevDisk, now > p.time, read >= p.read, write >= p.write else { return (0, 0) }
        let dt = now - p.time
        return (Double(read - p.read) / dt, Double(write - p.write) / dt)
    }

    // MARK: Network

    private func sampleNetwork() -> (down: Double, up: Double, interface: String?, ip: String?) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0, nil, nil) }
        defer { freeifaddrs(ifap) }

        var counters: [String: (ib: UInt32, ob: UInt32)] = [:]
        var ipv4: [String: String] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard Self.isPhysicalInterface(name), let addr = ifa.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            if family == AF_LINK, let data = ifa.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                counters[name] = (d.ifi_ibytes, d.ifi_obytes)
            } else if family == AF_INET {
                var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &sin, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                    ipv4[name] = String(cString: buf)
                }
            }
        }

        let now = Date().timeIntervalSinceReferenceDate
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, c) in counters {
            guard let p = prevNet[name] else { continue }
            // if_data counters are 32-bit and wrap at 4 GiB.
            down += UInt64(c.ib &- p.ib)
            up += UInt64(c.ob &- p.ob)
        }
        let dt = prevNetTime.map { now - $0 } ?? 0
        prevNet = counters
        prevNetTime = now

        // Primary: the interface with an IPv4 address and the most traffic.
        let primary = ipv4.keys.max { (counters[$0].map { UInt64($0.ib) + UInt64($0.ob) } ?? 0)
            < (counters[$1].map { UInt64($0.ib) + UInt64($0.ob) } ?? 0) }
        guard dt > 0 else { return (0, 0, primary, primary.flatMap { ipv4[$0] }) }
        return (Double(down) / dt, Double(up) / dt, primary, primary.flatMap { ipv4[$0] })
    }

    private static func isPhysicalInterface(_ name: String) -> Bool {
        let skip = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap", "ipsec", "vmenet"]
        return !skip.contains { name.hasPrefix($0) }
    }

    // MARK: Battery

    static func sampleBattery() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(1, desc[kIOPSMaxCapacityKey] as? Int ?? 100)
            var stats = BatteryStats(
                level: Double(current) / Double(maximum),
                isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: desc[kIOPSIsChargedKey] as? Bool ?? false,
                onAC: (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                condition: desc[kIOPSBatteryHealthKey] as? String)
            if let minutes = desc[kIOPSTimeToEmptyKey] as? Int, minutes > 0 { stats.minutesRemaining = minutes }
            if let smart = ioProperties(matching: "AppleSmartBattery").first {
                stats.cycles = (smart["CycleCount"] as? NSNumber)?.intValue
                if let t = (smart["Temperature"] as? NSNumber)?.doubleValue { stats.temperature = t / 100 }
                let design = (smart["DesignCapacity"] as? NSNumber)?.doubleValue
                let maxCap = (smart["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
                    ?? (smart["NominalChargeCapacity"] as? NSNumber)?.doubleValue
                if let design, let maxCap, design > 0 { stats.healthFraction = min(1.05, maxCap / design) }
            }
            return stats
        }
        return nil
    }

    // MARK: Processes

    private func sampleProcesses() -> (top: [ProcessStat], zombies: Int) {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return ([], 0) }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let got = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard got > 0 else { return ([], 0) }

        let now = mach_absolute_time()
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let elapsedNs = Double(now &- prevProcTime) * Double(tb.numer) / Double(tb.denom)
        let firstPass = prevProcTime == 0
        prevProcTime = now

        var zombies = 0
        var next: [pid_t: UInt64] = [:]
        var stats: [ProcessStat] = []
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let bsdSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)

        for pid in pids.prefix(Int(got)) where pid > 0 {
            var bsd = proc_bsdshortinfo()
            if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &bsd, bsdSize) == bsdSize, bsd.pbsi_status == 5 /* SZOMB */ {
                zombies += 1
                continue
            }
            var ti = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, taskSize) == taskSize else { continue }
            let cpuTime = ti.pti_total_user &+ ti.pti_total_system
            next[pid] = cpuTime
            guard !firstPass, elapsedNs > 0, let prev = prevProcCPU[pid], cpuTime >= prev else { continue }
            let cpu = Double(cpuTime - prev) * procTimeScale / elapsedNs
            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            var name = String(cString: nameBuf)
            if name.isEmpty { name = "pid \(pid)" }
            stats.append(ProcessStat(pid: pid, name: name, cpu: cpu, memory: ti.pti_resident_size))
        }
        prevProcCPU = next
        stats.sort { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.memory > $1.memory }
        return (Array(stats.prefix(8)), zombies)
    }

    /// pti_total_user/system are nanoseconds on Intel but mach ticks on Apple silicon.
    /// Compare against CLOCK_PROCESS_CPUTIME_ID for this process to pick the right scale.
    private static func detectProcTimeScale() -> Double {
        var x = 0.0
        for i in 0..<3_000_000 { x += sqrt(Double(i)) } // burn a little CPU so both clocks are non-trivial
        _ = x
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &ti, size) == size else { return 1 }
        let raw = Double(ti.pti_total_user + ti.pti_total_system)
        let ns = Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID))
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let ticksScale = Double(tb.numer) / Double(tb.denom)
        guard raw > 0, ns > 0 else { return 1 }
        // Whichever interpretation lands closer to the real CPU time wins.
        return abs(raw * ticksScale - ns) < abs(raw - ns) ? ticksScale : 1
    }

    // MARK: Misc

    static func uptime() -> TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - TimeInterval(tv.tv_sec)
    }

    static func machineInfo() -> MachineInfo {
        var info = MachineInfo()
        info.name = Host.current().localizedName ?? "Mac"
        info.chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        info.memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        info.os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        info.performanceCores = Int(sysctlValue("hw.perflevel0.logicalcpu") as Int32? ?? 0)
        info.efficiencyCores = Int(sysctlValue("hw.perflevel1.logicalcpu") as Int32? ?? 0)
        return info
    }

    static func sysctlValue<T: FixedWidthInteger>(_ name: String) -> T? {
        var value: T = 0
        var size = MemoryLayout<T>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func ioProperties(matching className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var out: [[String: Any]] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                out.append(dict)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return out
    }
}
