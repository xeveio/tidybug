import AppKit
import SwiftUI
import TidyBugCore

extension InstalledApp {
    var versionText: String { version ?? "—" }
    var lastUsedSort: Date { lastUsed ?? .distantPast }
    var lastUsedDays: Int? {
        lastUsed.map { max(0, Int(Date().timeIntervalSince($0) / 86_400)) }
    }
}

/// State for the Apps tab: installed apps with their leftovers, and orphaned
/// leftovers of apps that are already gone.
@MainActor @Observable
final class AppsModel {
    static let shared = AppsModel()

    enum Mode: String, CaseIterable, Identifiable {
        case installed = "Installed", leftovers = "Leftovers"
        var id: String { rawValue }
    }

    /// Remembered between launches.
    var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "appsMode") ?? "") ?? .installed {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "appsMode") }
    }

    // Installed
    var apps: [InstalledApp] = []
    var scanning = false
    var scanned = false
    var sizing = false
    var search = ""
    var sortOrder = [KeyPathComparator(\InstalledApp.size, order: .reverse)]
    var selection = Set<String>()
    var leftovers: [String: [AppLeftover]] = [:]
    var loadingLeftovers = Set<String>()
    /// Leftover paths the user unchecked (the app bundle itself is always removed).
    var excluded = Set<String>()
    var runningIDs = Set<String>()
    var errorMessage: String?
    var quitting = false

    // Orphans
    var orphans: [OrphanLeftover] = []
    var orphanSelection = Set<String>()
    var scanningOrphans = false
    var orphansScanned = false

    private var teamIDs: [String: String] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppsModel.shared.refreshRunning() }
            })
        }
    }

    static var uninstallGuard: SafetyGuard {
        SafetyGuard(allowedRoots: [NSHomeDirectory(), "/Applications"], whitelist: AppModel.shared.whitelist)
    }

    func refreshRunning() {
        runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        app.bundleID.map(runningIDs.contains) ?? false
    }

    var filteredApps: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(q) || ($0.bundleID?.lowercased().contains(q) ?? false)
        }
        return list.sorted(using: sortOrder)
    }

    var totalSize: Int64 { apps.reduce(0) { $0 + max(0, $1.size) } }
    var selectedApps: [InstalledApp] { apps.filter { selection.contains($0.id) } }

    // MARK: Scan

    func scan() {
        guard !scanning else { return }
        scanning = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            let listed = AppInventory.list()
            await MainActor.run {
                let model = AppsModel.shared
                withAnimation(.tidy) {
                    model.apps = listed
                    model.scanning = false
                    model.scanned = true
                    model.leftovers = [:]
                    model.selection = model.selection.filter { id in listed.contains { $0.id == id } }
                }
                model.refreshRunning()
                model.measureSizes()
            }
        }
    }

    /// Measures bundles one by one so the list fills in progressively.
    private func measureSizes() {
        sizing = true
        let targets = apps.map(\.url)
        Task.detached(priority: .utility) {
            let sizer = Sizer(isCancelled: { false })
            for url in targets {
                let bytes = sizer.measure(url.path).bytes
                await MainActor.run {
                    let model = AppsModel.shared
                    if let i = model.apps.firstIndex(where: { $0.url == url }) { model.apps[i].size = bytes }
                }
            }
            await MainActor.run { AppsModel.shared.sizing = false }
        }
    }

    // MARK: Leftovers of installed apps

    func loadLeftovers(for app: InstalledApp) {
        guard leftovers[app.id] == nil, !loadingLeftovers.contains(app.id) else { return }
        loadingLeftovers.insert(app.id)
        let others = apps.filter { $0.id != app.id }
        let otherIDs = Set(others.compactMap(\.bundleID))
        let cachedTeams = teamIDs
        Task.detached(priority: .userInitiated) {
            var teams = cachedTeams
            func team(_ a: InstalledApp) -> String? {
                if let t = teams[a.id] { return t.isEmpty ? nil : t }
                let t = AppInventory.teamIdentifier(a.url)
                teams[a.id] = t ?? ""
                return t
            }
            let myTeam = team(app)
            let otherTeams = myTeam == nil ? Set<String>() : Set(others.compactMap { team($0) })
            let found = LeftoverFinder().leftovers(bundleID: app.bundleID, appName: app.name, appPath: app.url.path,
                                                   teamID: myTeam, otherBundleIDs: otherIDs, otherTeamIDs: otherTeams)
            await MainActor.run {
                let model = AppsModel.shared
                model.teamIDs.merge(teams) { $1 }
                withAnimation(.tidy) {
                    model.leftovers[app.id] = found.sorted { $0.size > $1.size }
                    model.loadingLeftovers.remove(app.id)
                }
            }
        }
    }

    func items(for app: InstalledApp) -> [CleanItem] {
        var items = [CleanItem(url: app.url, name: app.name, size: max(0, app.size), note: "Application")]
        for l in leftovers[app.id] ?? [] where !excluded.contains(l.id) {
            items.append(CleanItem(url: l.url, size: l.size, note: l.category))
        }
        return items
    }

    func totalBytes(for app: InstalledApp) -> Int64 {
        items(for: app).reduce(0) { $0 + $1.size }
    }

    func toggleExcluded(_ leftover: AppLeftover) {
        withAnimation(.snappy) {
            if excluded.contains(leftover.id) { excluded.remove(leftover.id) } else { excluded.insert(leftover.id) }
        }
    }

    // MARK: Uninstall

    /// Quits running targets (if any, waiting up to 5 s), then asks for confirmation.
    func uninstall(_ targets: [InstalledApp]) {
        guard !targets.isEmpty else { return }
        errorMessage = nil
        Task {
            let running = NSWorkspace.shared.runningApplications.filter { r in
                targets.contains { $0.bundleID != nil && $0.bundleID == r.bundleIdentifier }
            }
            if !running.isEmpty {
                quitting = true
                running.forEach { $0.terminate() }
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline, running.contains(where: { !$0.isTerminated }) {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                quitting = false
                refreshRunning()
                if let stuck = running.first(where: { !$0.isTerminated }) {
                    errorMessage = "\(stuck.localizedName ?? "The app") did not quit. Quit it manually and try again."
                    return
                }
            }
            for app in targets { loadLeftovers(for: app) }
            while targets.contains(where: { loadingLeftovers.contains($0.id) }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let allItems = targets.flatMap { self.items(for: $0) }
            let guardRail = Self.uninstallGuard
            let title = targets.count == 1 ? "Uninstall \(targets[0].name)" : "Uninstall \(targets.count) apps"
            AppModel.shared.pendingConfirmation = ConfirmRequest(
                title: title, items: allItems, safetyGuard: guardRail,
                perform: { await AppsModel.shared.remove(allItems, source: "uninstall", guard: guardRail, apps: targets) })
        }
    }

    func remove(_ items: [CleanItem], source: String, guard guardRail: SafetyGuard, apps targets: [InstalledApp] = []) async {
        let outcome = await Cleaner.remove(items, mode: .trash, source: source, guard: guardRail)
        let removed = Set(outcome.removed.map(\.id))
        withAnimation(.tidy) {
            apps.removeAll { removed.contains($0.id) }
            selection.subtract(removed)
            for key in leftovers.keys { leftovers[key]?.removeAll { removed.contains($0.id) } }
            orphans.removeAll { removed.contains($0.id) }
            orphanSelection.subtract(removed)
        }
        let failedBundles = outcome.failures.filter { f in targets.contains { $0.url == f.item.url } }
        if let first = failedBundles.first {
            errorMessage = "Couldn't move \(first.item.name) to the Trash: \(first.reason) Apps installed by the App Store or owned by root may need to be dragged to the Trash in Finder."
        }
        let shared = AppModel.shared
        shared.refreshVolume()
        shared.loadHistory()
        if outcome.freed > 0 || !outcome.failures.isEmpty {
            shared.celebration = CleanSummary(freed: outcome.freed, count: outcome.removed.count,
                                              failures: outcome.failures.count, permanent: false)
        }
    }

    // MARK: Orphans

    func scanOrphans() {
        guard !scanningOrphans else { return }
        scanningOrphans = true
        let running = runningIDs
        Task.detached(priority: .userInitiated) {
            let installed = Set(AppInventory.list().compactMap(\.bundleID))
            let found = LeftoverFinder().orphans(isInstalled: { id in
                if running.contains(id) || LeftoverFinder.isInstalled(id, installed: installed) { return true }
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
            })
            await MainActor.run {
                let model = AppsModel.shared
                withAnimation(.tidy) {
                    model.orphans = found
                    model.orphanSelection = []
                    model.scanningOrphans = false
                    model.orphansScanned = true
                }
            }
        }
    }

    struct OrphanGroup: Identifiable {
        var id: String { bundleID }
        let bundleID: String
        let name: String
        let items: [OrphanLeftover]
        var size: Int64 { items.reduce(0) { $0 + $1.size } }
    }

    /// Groups orphans by app, folding helper ids ("com.microsoft.teams2.respawn")
    /// into their parent ("com.microsoft.teams2") when both are present.
    var orphanGroups: [OrphanGroup] {
        let ids = Set(orphans.map(\.bundleID))
        func root(_ id: String) -> String {
            ids.filter { id.hasPrefix($0 + ".") }.min { $0.count < $1.count } ?? id
        }
        return Dictionary(grouping: orphans) { root($0.bundleID) }
            .map { key, items in
                let name = items.first { $0.bundleID == key }?.probableAppName ?? items[0].probableAppName
                return OrphanGroup(bundleID: key, name: name, items: items.sorted { $0.size > $1.size })
            }
            .sorted { $0.size > $1.size }
    }

    var orphanTotal: Int64 { orphans.reduce(0) { $0 + $1.size } }
    var orphanSelectedBytes: Int64 { orphans.filter { orphanSelection.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func toggleOrphan(_ o: OrphanLeftover) {
        withAnimation(.snappy) {
            if orphanSelection.contains(o.id) { orphanSelection.remove(o.id) } else { orphanSelection.insert(o.id) }
        }
    }

    func toggleGroup(_ g: OrphanGroup) {
        let ids = Set(g.items.map(\.id))
        withAnimation(.snappy) {
            if ids.isSubset(of: orphanSelection) { orphanSelection.subtract(ids) } else { orphanSelection.formUnion(ids) }
        }
    }

    func trashSelectedOrphans() {
        let items = orphans.filter { orphanSelection.contains($0.id) }
            .map { CleanItem(url: $0.url, size: $0.size, note: $0.category) }
        guard !items.isEmpty else { return }
        let guardRail = SafetyGuard(whitelist: AppModel.shared.whitelist)
        AppModel.shared.pendingConfirmation = ConfirmRequest(
            title: "Remove \(items.count) leftover item\(items.count == 1 ? "" : "s")", items: items, safetyGuard: guardRail,
            perform: { await AppsModel.shared.remove(items, source: "leftovers", guard: guardRail) })
    }

    func collectSelectedOrphans() {
        for o in orphans where orphanSelection.contains(o.id) {
            AppModel.shared.stage(o.url, size: o.size, source: "apps")
        }
    }
}
