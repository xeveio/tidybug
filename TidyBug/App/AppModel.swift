import AppKit
import ServiceManagement
import SwiftUI
import TidyBugCore

enum Pane: String, CaseIterable, Identifiable {
    case home, smartClean, diskMap, purge, duplicates, largeFiles, apps, optimize, monitor, history
    var id: String { rawValue }

    /// Panes shown as tabs (Activity lives in the top bar). ⌘1…⌘9 follow this order.
    static let dock: [Pane] = [.home, .smartClean, .diskMap, .purge, .duplicates, .largeFiles, .apps, .optimize, .monitor]

    var title: String {
        switch self {
        case .home: "Overview"
        case .smartClean: "Clean"
        case .diskMap: "Space"
        case .purge: "Projects"
        case .duplicates: "Duplicates"
        case .largeFiles: "Large Files"
        case .apps: "Apps"
        case .optimize: "Optimize"
        case .monitor: "Monitor"
        case .history: "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .smartClean: "sparkles"
        case .diskMap: "chart.pie"
        case .purge: "hammer"
        case .duplicates: "square.on.square"
        case .largeFiles: "doc.text.magnifyingglass"
        case .apps: "app.badge"
        case .optimize: "wrench.and.screwdriver"
        case .monitor: "waveform.path.ecg"
        case .history: "list.bullet.rectangle"
        }
    }
}

enum ScanPhase: Equatable { case idle, scanning, ready, cleaning }

struct CleanSummary: Identifiable, Equatable {
    let id = UUID()
    let freed: Int64
    let count: Int
    let failures: Int
    let permanent: Bool
}

/// A pending destructive action awaiting the user's confirmation.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let items: [CleanItem]
    var commands: [CommandAction] = []
    var permanent = false
    var extraBytes: Int64 = 0
    /// Overrides the default home-only guard for the dry-run preview (e.g. uninstalling from /Applications).
    var safetyGuard: SafetyGuard? = nil
    let perform: @MainActor () async -> Void

    var totalBytes: Int64 { items.reduce(extraBytes) { $0 + $1.size } }
}

/// Thread-safe cancellation flag handed to background scanners.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

@MainActor @Observable
final class AppModel {
    /// Single instance shared by the window, the menu bar and App Intents.
    static let shared = AppModel()

    var pane: Pane? = .home
    var volume = VolumeInfo.current()
    var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    var pendingConfirmation: ConfirmRequest?
    var celebration: CleanSummary?
    var freedThisSession: Int64 = 0
    var history: [LogEntry] = []

    // MARK: Smart Clean
    var scanPhase: ScanPhase = .idle
    var results: [RuleResult] = []
    var selectedItems: Set<String> = []
    var selectedCommands: Set<String> = []
    var lastScan: Date?
    var runningAdvisorCommand: String?
    private var scanTask: Task<Void, Never>?
    let ruleOrder = BuiltinRules.all.map(\.id)

    // MARK: Disk Map
    var mapRootPath = NSHomeDirectory()
    var mapRoot: DiskNode?
    var mapFocus: DiskNode?
    var mapProgress: ScanProgress?
    var mapScanning = false
    var mapVersion = 0
    private var mapFlag: CancelFlag?

    // MARK: Collector (DaisyDisk-style staging area)
    struct StagedItem: Identifiable, Equatable {
        var id: String { url.path }
        let url: URL
        /// nil while the size is still being measured.
        var size: Int64?
        var node: DiskNode?
        let source: String
        var name: String { url.lastPathComponent }

        static func == (a: StagedItem, b: StagedItem) -> Bool { a.id == b.id && a.size == b.size }
    }

    var staged: [StagedItem] = []
    var stagingNotice: String?
    var showTour = false

    // MARK: Project Purge
    var purgeRoots: [String] {
        didSet { UserDefaults.standard.set(purgeRoots, forKey: "purgeRoots") }
    }
    var artifacts: [ProjectArtifact] = []
    var purgeSelection: Set<String> = []
    var purgeScanning = false
    var purgeCurrent = ""
    var purgeScanned = false
    private var purgeFlag: CancelFlag?

    // MARK: Large Files
    var largeRoot = NSHomeDirectory()
    var largeMinimum: Int64 = 100 << 20
    var largeFiles: [LargeFile] = []
    var largeSelection: Set<String> = []
    var largeScanning = false
    var largeCurrent = ""
    var largeScanned = false
    private var largeFlag: CancelFlag?

    private var volumeTimer: Timer?

    init() {
        purgeRoots = UserDefaults.standard.stringArray(forKey: "purgeRoots") ?? ProjectScanner.defaultRoots
        loadHistory()
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshVolume() }
        }
    }

    // MARK: Settings

    var permanentForCaches: Bool { UserDefaults.standard.bool(forKey: "permanentForCaches") }

    var whitelist: [String] {
        get { UserDefaults.standard.stringArray(forKey: "whitelist") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "whitelist") }
    }

    var safetyGuard: SafetyGuard { SafetyGuard(whitelist: whitelist) }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { NSLog("TidyBug launch-at-login: \(error)") }
        }
    }

    static func checkFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        guard let handle = FileHandle(forReadingAtPath: probe) else { return false }
        try? handle.close()
        return true
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    func refreshVolume() {
        volume = VolumeInfo.current()
        hasFullDiskAccess = Self.checkFullDiskAccess()
    }

    func loadHistory() {
        Task.detached(priority: .utility) {
            let entries = OperationLog.shared.entries()
            await MainActor.run { self.history = entries }
        }
    }

    // MARK: Smart Clean

    var visibleResults: [RuleResult] {
        results.filter { $0.available && ($0.total > 0 || !$0.items.isEmpty || $0.probeNote != nil) }
    }

    var reclaimableTotal: Int64 {
        visibleResults.filter { $0.rule.safety != .advisor }.reduce(0) { $0 + $1.total }
    }

    var safeTotal: Int64 {
        visibleResults.filter { $0.rule.safety == .safe }.reduce(0) { $0 + $1.total }
    }

    var selectedBytes: Int64 {
        visibleResults.reduce(0) { sum, r in
            if r.rule.isCommandBased { return sum + (selectedCommands.contains(r.id) ? r.total : 0) }
            return sum + r.items.filter { selectedItems.contains($0.id) }.reduce(0) { $0 + $1.size }
        }
    }

    var selectedCount: Int {
        selectedCommands.count + selectedItems.count
    }

    func startSmartScan() {
        scanTask?.cancel()
        withAnimation(.tidy) {
            scanPhase = .scanning
            results = []
            selectedItems = []
            selectedCommands = []
        }
        scanTask = Task { [weak self] in
            let stream = AsyncStream<RuleResult> { continuation in
                let worker = Task.detached(priority: .utility) {
                    await ScanEngine.scan { continuation.yield($0) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in worker.cancel() }
            }
            for await result in stream {
                guard let self else { return }
                withAnimation(.bouncy) { self.insert(result) }
            }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.tidy) {
                self.scanPhase = .ready
                self.lastScan = Date()
            }
            self.refreshVolume()
        }
    }

    /// Starts a Smart Scan if there are no results yet, and waits for it to finish.
    func scanIfNeeded() async {
        if scanPhase == .ready || scanPhase == .cleaning { return }
        if scanPhase != .scanning { startSmartScan() }
        await scanTask?.value
    }

    /// Scan if needed, then clean only the safe (regenerable) tier. Used by the
    /// menu bar and Shortcuts. Returns the bytes freed.
    @discardableResult
    func cleanSafeJunk() async -> Int64 {
        await scanIfNeeded()
        selectSafeOnly()
        let before = freedThisSession
        await performSmartClean()
        return freedThisSession - before
    }

    func cancelScan() {
        scanTask?.cancel()
        withAnimation(.tidy) { scanPhase = results.isEmpty ? .idle : .ready }
    }

    private func insert(_ result: RuleResult) {
        results.removeAll { $0.id == result.id }
        let index = ruleOrder.firstIndex(of: result.id) ?? ruleOrder.count
        let at = results.firstIndex { (ruleOrder.firstIndex(of: $0.id) ?? 0) > index } ?? results.count
        results.insert(result, at: at)
        // Only the regenerable tier is preselected; everything else is the user's call.
        guard result.rule.safety == .safe else { return }
        if result.rule.isCommandBased {
            if result.total > 0 || !result.items.isEmpty { selectedCommands.insert(result.id) }
        } else {
            for item in result.items where item.isRemovable && !item.containsData { selectedItems.insert(item.id) }
        }
    }

    enum CheckState { case on, off, mixed }

    func checkState(for result: RuleResult) -> CheckState {
        if result.rule.isCommandBased { return selectedCommands.contains(result.id) ? .on : .off }
        let removable = result.items.filter(\.isRemovable)
        let picked = removable.filter { selectedItems.contains($0.id) }.count
        if picked == 0 { return .off }
        return picked == removable.count ? .on : .mixed
    }

    func toggle(_ result: RuleResult) {
        withAnimation(.snappy) {
            if result.rule.isCommandBased {
                if selectedCommands.contains(result.id) { selectedCommands.remove(result.id) }
                else { selectedCommands.insert(result.id) }
                return
            }
            let ids = result.items.filter(\.isRemovable).map(\.id)
            if checkState(for: result) == .on { selectedItems.subtract(ids) } else { selectedItems.formUnion(ids) }
        }
    }

    func toggle(item: CleanItem) {
        guard item.isRemovable else { return }
        withAnimation(.snappy) {
            if selectedItems.contains(item.id) { selectedItems.remove(item.id) } else { selectedItems.insert(item.id) }
        }
    }

    /// Only the safe tier, as used by the menu bar's one-click clean.
    func selectSafeOnly() {
        selectedItems = []
        selectedCommands = []
        for r in visibleResults where r.rule.safety == .safe { insert(r) }
    }

    func requestSmartClean() {
        let chosen = visibleResults.filter { !$0.rule.isCommandBased && $0.rule.safety != .advisor }
            .flatMap { r in r.items.filter { selectedItems.contains($0.id) } }
        let commands = visibleResults.filter { $0.rule.isCommandBased && selectedCommands.contains($0.id) }
        let permanent = permanentForCaches || visibleResults.contains { $0.rule.permanentOnly && $0.items.contains { selectedItems.contains($0.id) } }
        pendingConfirmation = ConfirmRequest(
            title: "Clean \(selectedBytes.formattedBytes)",
            items: chosen,
            commands: commands.compactMap(\.rule.command),
            permanent: permanent,
            extraBytes: commands.reduce(0) { $0 + $1.total },
            perform: { [weak self] in await self?.performSmartClean() })
    }

    func performSmartClean() async {
        withAnimation(.tidy) { scanPhase = .cleaning }
        var outcome = CleanOutcome()
        var usedPermanent = false
        for result in visibleResults where result.rule.safety != .advisor {
            if result.rule.isCommandBased {
                guard selectedCommands.contains(result.id) else { continue }
                let r = await ScanEngine.runCommand(for: result.rule, estimatedBytes: result.total)
                if r.succeeded { outcome.freed += result.total }
                let rule = result.rule
                let fresh = await Task.detached(priority: .utility) { ScanEngine.scan(rule) }.value
                withAnimation(.bouncy) {
                    selectedCommands.remove(result.id)
                    if let i = results.firstIndex(where: { $0.id == result.id }) { results[i] = fresh }
                }
                continue
            }
            let items = result.items.filter { selectedItems.contains($0.id) }
            guard !items.isEmpty else { continue }
            let mode: DeletionMode = result.rule.permanentOnly || (result.rule.allowsPermanent && permanentForCaches)
                ? .permanent : .trash
            if mode == .permanent { usedPermanent = true }
            let o = await Cleaner.remove(items, mode: mode, source: "smart-clean", rule: result.rule.id, guard: safetyGuard)
            outcome.merge(o)
            let removed = Set(o.removed.map(\.id))
            withAnimation(.bouncy) {
                if let i = results.firstIndex(where: { $0.id == result.id }) {
                    results[i].items.removeAll { removed.contains($0.id) }
                }
                selectedItems.subtract(removed)
            }
        }
        withAnimation(.tidy) { scanPhase = .ready }
        finish(outcome, permanent: usedPermanent)
    }

    func requestAdvisorCommand(_ result: RuleResult) {
        guard let command = result.rule.command else { return }
        pendingConfirmation = ConfirmRequest(
            title: command.title, items: [], commands: [command], extraBytes: result.probeBytes ?? 0,
            perform: { [weak self] in
                guard let self else { return }
                self.runningAdvisorCommand = result.id
                let r = await ScanEngine.runCommand(for: result.rule, estimatedBytes: result.probeBytes ?? 0)
                let rule = result.rule
                let fresh = await Task.detached(priority: .utility) { ScanEngine.scan(rule) }.value
                if let i = self.results.firstIndex(where: { $0.id == result.id }) { self.results[i] = fresh }
                self.runningAdvisorCommand = nil
                var o = CleanOutcome()
                if r.succeeded { o.freed = result.probeBytes ?? 0 }
                self.finish(o, permanent: true)
            })
    }

    // MARK: Shared removal

    func requestTrash(_ items: [CleanItem], title: String, source: String,
                      then: @escaping @MainActor (CleanOutcome) -> Void) {
        pendingConfirmation = ConfirmRequest(title: title, items: items, perform: { [weak self] in
            guard let self else { return }
            let o = await Cleaner.remove(items, mode: .trash, source: source, guard: self.safetyGuard)
            then(o)
            self.finish(o, permanent: false)
        })
    }

    private func finish(_ outcome: CleanOutcome, permanent: Bool) {
        freedThisSession += outcome.freed
        refreshVolume()
        loadHistory()
        if outcome.freed > 0 || !outcome.failures.isEmpty {
            withAnimation(.bouncy) {
                celebration = CleanSummary(freed: outcome.freed, count: outcome.removed.count,
                                           failures: outcome.failures.count, permanent: permanent)
            }
        }
    }

    // MARK: Disk Map

    func scanDiskMap(path: String? = nil) {
        if let path { mapRootPath = path }
        mapFlag?.set()
        let flag = CancelFlag()
        mapFlag = flag
        let root = mapRootPath
        withAnimation(.tidy) {
            mapScanning = true
            mapRoot = nil
            mapFocus = nil
            // Staged items stay (they're plain paths); only detach them from the old tree.
            for i in staged.indices { staged[i].node = nil }
            mapProgress = nil
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let tree = DiskTreeBuilder.build(root: root, isCancelled: { flag.isSet }) { p in
                Task { @MainActor in self?.mapProgress = p }
            }
            await MainActor.run {
                guard let self, !flag.isSet else { return }
                withAnimation(.tidy) {
                    self.mapRoot = tree
                    self.mapFocus = tree
                    self.mapScanning = false
                    self.mapVersion += 1
                }
            }
        }
    }

    func cancelDiskMap() {
        mapFlag?.set()
        withAnimation(.tidy) { mapScanning = false }
    }

    func focus(_ node: DiskNode?) {
        guard let node, node.isDirectory, !node.children.isEmpty else { return }
        withAnimation(.tidy) { mapFocus = node }
    }

    // MARK: Collector

    var stagedTotal: Int64 { staged.reduce(0) { $0 + ($1.size ?? 0) } }
    var isMeasuringStaged: Bool { staged.contains { $0.size == nil } }

    /// Disk-map view of the collector (items that came from the current tree).
    var collector: [DiskNode] {
        get { staged.compactMap(\.node) }
        set {
            staged.removeAll { item in
                guard let n = item.node else { return false }
                return !newValue.contains { $0 === n }
            }
        }
    }

    /// Add a file or folder to the collector. Sizes are measured (hardlink-aware)
    /// in the background when not supplied. Protected paths are refused.
    func stage(_ url: URL, size: Int64? = nil, node: DiskNode? = nil, source: String) {
        let path = url.standardizedFileURL.path
        if staged.contains(where: { path == $0.id || path.hasPrefix($0.id + "/") }) {
            notice("Already in the Collector")
            return
        }
        do { try safetyGuard.validate(url) } catch {
            notice((error as? LocalizedError)?.errorDescription ?? "Protected location")
            return
        }
        withAnimation(.bouncy) {
            // A folder replaces anything already collected from inside it.
            staged.removeAll { $0.id.hasPrefix(path + "/") }
            staged.append(StagedItem(url: URL(fileURLWithPath: path), size: size, node: node, source: source))
        }
        guard size == nil else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let bytes = Sizer().measure(path).bytes
            await MainActor.run {
                guard let self, let i = self.staged.firstIndex(where: { $0.id == path }) else { return }
                withAnimation(.tidy) { self.staged[i].size = bytes }
            }
        }
    }

    func stage(urls: [URL], source: String) {
        for url in urls { stage(url, source: source) }
    }

    func stage(_ item: CleanItem, source: String) {
        stage(item.url, size: item.size, source: source)
    }

    func unstage(_ item: StagedItem) {
        withAnimation(.bouncy) { staged.removeAll { $0.id == item.id } }
    }

    func clearStaged() {
        withAnimation(.tidy) { staged.removeAll() }
    }

    private func notice(_ text: String) {
        withAnimation(.tidy) { stagingNotice = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.tidy) { if self.stagingNotice == text { self.stagingNotice = nil } }
        }
    }

    /// "Delete All": one confirmation, everything to the Trash, then every view is updated.
    func requestDeleteStaged() {
        let items = staged.filter { $0.size != nil }
        guard !items.isEmpty else { return }
        let cleanItems = items.map { CleanItem(url: $0.url, size: $0.size ?? 0) }
        requestTrash(cleanItems, title: "Delete \(items.count) collected item\(items.count == 1 ? "" : "s")",
                     source: "collector") { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.url.path))
            withAnimation(.tidy) {
                for item in items where removed.contains(item.id) {
                    if let node = item.node { node.parent?.remove(node) }
                }
                self.staged.removeAll { removed.contains($0.id) }
                self.artifacts.removeAll { removed.contains($0.id) }
                self.largeFiles.removeAll { removed.contains($0.id) }
                self.purgeSelection.subtract(removed)
                self.largeSelection.subtract(removed)
                for i in self.results.indices { self.results[i].items.removeAll { removed.contains($0.id) } }
                self.selectedItems.subtract(removed)
                self.mapVersion += 1
            }
        }
    }

    func addToCollector(_ node: DiskNode) {
        guard !node.isAggregate, node.parent != nil else { return }
        stage(node.url, size: node.size, node: node, source: "space")
    }

    func trashCollector() { requestDeleteStaged() }

    // MARK: Project Purge

    func scanProjects() {
        purgeFlag?.set()
        let flag = CancelFlag()
        purgeFlag = flag
        let roots = purgeRoots
        withAnimation(.tidy) {
            artifacts = []
            purgeSelection = []
            purgeScanning = true
            purgeScanned = true
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            var lastPing = Date.distantPast
            ProjectScanner.scan(roots: roots, isCancelled: { flag.isSet }, progress: { path in
                guard Date().timeIntervalSince(lastPing) > 0.08 else { return }
                lastPing = Date()
                Task { @MainActor in self?.purgeCurrent = path }
            }, found: { artifact in
                Task { @MainActor in
                    guard let self, !flag.isSet else { return }
                    withAnimation(.bouncy) { self.artifacts.append(artifact) }
                }
            })
            await MainActor.run {
                guard let self, !flag.isSet else { return }
                withAnimation(.tidy) { self.purgeScanning = false }
            }
        }
    }

    func cancelProjects() {
        purgeFlag?.set()
        withAnimation(.tidy) { purgeScanning = false }
    }

    func selectStale(olderThan days: Int) {
        withAnimation(.snappy) {
            purgeSelection = Set(artifacts.filter {
                $0.ageDays >= days && $0.reinstallable && $0.item.isRemovable && !$0.item.containsData
            }.map(\.id))
        }
    }

    func trashSelectedArtifacts() {
        let items = artifacts.filter { purgeSelection.contains($0.id) }.map(\.item)
        requestTrash(items, title: "Purge \(items.count) build folder\(items.count == 1 ? "" : "s")",
                     source: "purge") { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.id))
            withAnimation(.bouncy) {
                self.artifacts.removeAll { removed.contains($0.id) }
                self.purgeSelection.subtract(removed)
            }
        }
    }

    // MARK: Large Files

    func scanLargeFiles() {
        largeFlag?.set()
        let flag = CancelFlag()
        largeFlag = flag
        let root = largeRoot
        let minimum = largeMinimum
        withAnimation(.tidy) {
            largeFiles = []
            largeSelection = []
            largeScanning = true
            largeScanned = true
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            var lastPing = Date.distantPast
            LargeFileFinder.scan(root: root, minimumSize: minimum, isCancelled: { flag.isSet }, progress: { path in
                guard Date().timeIntervalSince(lastPing) > 0.08 else { return }
                lastPing = Date()
                Task { @MainActor in self?.largeCurrent = path }
            }, found: { file in
                Task { @MainActor in
                    guard let self, !flag.isSet else { return }
                    withAnimation(.bouncy) { self.largeFiles.append(file) }
                }
            })
            await MainActor.run {
                guard let self, !flag.isSet else { return }
                withAnimation(.tidy) { self.largeScanning = false }
            }
        }
    }

    func cancelLargeFiles() {
        largeFlag?.set()
        withAnimation(.tidy) { largeScanning = false }
    }

    func trashSelectedLargeFiles() {
        let items = largeFiles.filter { largeSelection.contains($0.id) }.map(\.item)
        requestTrash(items, title: "Move \(items.count) file\(items.count == 1 ? "" : "s") to Trash",
                     source: "large-files") { [weak self] outcome in
            guard let self else { return }
            let removed = Set(outcome.removed.map(\.id))
            withAnimation(.bouncy) {
                self.largeFiles.removeAll { removed.contains($0.id) }
                self.largeSelection.subtract(removed)
            }
        }
    }
}

enum Finder {
    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    static func chooseFolder(startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: path)
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
