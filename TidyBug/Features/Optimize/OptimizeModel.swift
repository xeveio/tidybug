import SwiftUI
import TidyBugCore

@MainActor @Observable
final class OptimizeModel {
    static let shared = OptimizeModel()

    enum TaskState: Equatable {
        case idle, running, done(MaintenanceOutcome, output: String, duration: TimeInterval)
    }

    struct RunSummary: Equatable {
        let applied: Int
        let failed: Int
        let unchanged: Int
        let skipped: Int
        let preview: Bool
    }

    let tasks = Maintenance.tasks
    var readiness: [String: TaskReadiness] = [:]
    var selected: Set<String> = []
    var states: [String: TaskState] = [:]
    var expanded: Set<String> = []
    var findings: [Finding] = []
    var summary: SystemSummary?
    var checking = false
    var diagnosing = false
    var running = false
    var preview = false
    var lastRun: RunSummary?
    private var didInitialSelection = false
    private var loaded = false

    var categories: [MaintenanceCategory] {
        MaintenanceCategory.allCases.filter { c in tasks.contains { $0.category == c } }
    }

    func tasks(in category: MaintenanceCategory) -> [MaintenanceTask] {
        tasks.filter { $0.category == category }
    }

    func isReady(_ task: MaintenanceTask) -> Bool { readiness[task.id]?.isReady ?? false }

    var runnable: [MaintenanceTask] { tasks.filter { selected.contains($0.id) && isReady($0) } }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        refresh()
    }

    /// Re-evaluates task readiness, the system summary and the diagnosis.
    func refresh() {
        checking = true
        diagnosing = true
        let tasks = self.tasks
        Task.detached(priority: .userInitiated) {
            let summary = Diagnosis.summary()
            var ready: [String: TaskReadiness] = [:]
            for t in tasks { ready[t.id] = t.readiness() }
            await MainActor.run {
                withAnimation(.tidy) {
                    self.summary = summary
                    self.readiness = ready
                    self.checking = false
                    if !self.didInitialSelection {
                        self.selected = Set(tasks.filter { $0.preselected && ready[$0.id]?.isReady == true }.map(\.id))
                        self.didInitialSelection = true
                    } else {
                        self.selected = self.selected.filter { ready[$0]?.isReady == true }
                    }
                }
            }
            let findings = Diagnosis.run()
            await MainActor.run {
                withAnimation(.tidy) {
                    self.findings = findings.sorted { $0.severity > $1.severity }
                    self.diagnosing = false
                }
            }
        }
    }

    func toggle(_ task: MaintenanceTask) {
        guard isReady(task), !running else { return }
        withAnimation(.snappy) {
            if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
        }
    }

    func toggleExpanded(_ task: MaintenanceTask) {
        withAnimation(.tidy) {
            if expanded.contains(task.id) { expanded.remove(task.id) } else { expanded.insert(task.id) }
        }
    }

    func run() {
        let chosen = runnable
        guard !chosen.isEmpty, !running else { return }
        let skipped = tasks.filter { !isReady($0) }.count
        let unchanged = tasks.filter { isReady($0) && !selected.contains($0.id) }.count

        if preview {
            withAnimation(.tidy) {
                expanded.formUnion(chosen.map(\.id))
                lastRun = RunSummary(applied: chosen.count, failed: 0, unchanged: unchanged, skipped: skipped, preview: true)
            }
            return
        }

        running = true
        withAnimation(.tidy) {
            lastRun = nil
            for t in chosen { states[t.id] = .running }
        }
        let plain = chosen.filter { !$0.requiresAdmin }
        let admin = chosen.filter(\.requiresAdmin)

        Task.detached(priority: .userInitiated) {
            var results: [MaintenanceResult] = []
            for t in plain {
                let r = MaintenanceEngine.run(t)
                results.append(r)
                await MainActor.run { self.apply(r) }
            }
            if !admin.isEmpty {
                let rs = MaintenanceEngine.runAdmin(admin)
                results += rs
                await MainActor.run { for r in rs { self.apply(r) } }
            }
            MaintenanceEngine.log(results, tasks: chosen)
            let applied = results.filter { $0.outcome == .applied }.count
            await MainActor.run {
                withAnimation(.tidy) {
                    self.lastRun = RunSummary(applied: applied, failed: results.count - applied,
                                              unchanged: unchanged, skipped: skipped, preview: false)
                    self.running = false
                }
                AppModel.shared.refreshVolume()
                AppModel.shared.loadHistory()
                self.refresh()
            }
        }
    }

    private func apply(_ r: MaintenanceResult) {
        withAnimation(.tidy) {
            states[r.id] = .done(r.outcome, output: r.output, duration: r.duration)
            if case .failed = r.outcome { expanded.insert(r.id) }
        }
    }
}
