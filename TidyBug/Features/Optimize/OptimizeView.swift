import SwiftUI
import TidyBugCore

/// Maintenance tasks with a performance diagnosis. Nothing runs without a click;
/// admin tasks share one password prompt; Preview shows the exact commands.
struct OptimizeView: View {
    @State private var model = OptimizeModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let run = model.lastRun { summaryBanner(run).transition(.move(edge: .top).combined(with: .opacity)) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    diagnosisPanel
                    ForEach(model.categories, id: \.self) { category in
                        categoryPanel(category)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .onAppear { model.loadIfNeeded() }
        .animation(.tidy, value: model.lastRun)
    }

    // MARK: Header

    private var summaryLine: String {
        guard let s = model.summary else { return "Reading system state…" }
        let ram = String(format: "%.1f/%.0f GB RAM", Double(s.memoryUsed) / 1_073_741_824, Double(s.memoryTotal) / 1_073_741_824)
        let disk = "\(s.diskUsed.formattedBytes)/\(s.diskTotal.formattedBytes) disk"
        return "\(ram) · \(disk) · uptime \(s.uptimeText)"
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Optimize").pageTitle()
                Text(summaryLine)
                    .font(.mono(11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Toggle(isOn: $model.preview) {
                    Text("Preview").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.accent)
                .help("Show the exact commands without running anything")

                Button { model.refresh() } label: { Label("Re-check", systemImage: "arrow.clockwise") }
                    .buttonStyle(.tidySecondary)
                    .disabled(model.running || model.checking)

                Button { model.run() } label: {
                    ShortcutLabel(title: runTitle, symbol: model.preview ? "eye" : "play.fill", keys: "⌘↵")
                }
                .buttonStyle(.tidy)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.runnable.isEmpty || model.running)
            }
        }
    }

    private var runTitle: String {
        let n = model.runnable.count
        if model.running { return "Running…" }
        let noun = "task\(n == 1 ? "" : "s")"
        return model.preview ? "Preview \(n) \(noun)" : "Run \(n) \(noun)"
    }

    private func summaryBanner(_ run: OptimizeModel.RunSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: run.preview ? "eye" : (run.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .foregroundStyle(run.preview ? Palette.info : (run.failed == 0 ? Palette.success : Palette.warning))
            Group {
                if run.preview {
                    Text("Preview: \(run.applied) task\(run.applied == 1 ? "" : "s") would run. Commands are shown below.")
                } else {
                    Text(summaryText(run))
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Palette.text)
            Spacer()
            Button { withAnimation(.tidy) { model.lastRun = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.tidyQuiet)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .panel(radius: 10)
    }

    private func summaryText(_ run: OptimizeModel.RunSummary) -> String {
        var parts = ["Applied \(run.applied)"]
        if run.failed > 0 { parts.append("\(run.failed) failed") }
        parts.append("\(run.unchanged) unchanged")
        parts.append("\(run.skipped) skipped")
        return parts.joined(separator: " · ")
    }

    // MARK: Diagnosis

    private var diagnosisPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "Diagnosis", subtitle: model.diagnosing ? "Sampling CPU and memory…" : "\(model.findings.count) checks")
                Spacer()
                if model.diagnosing { ProgressView().controlSize(.mini) }
            }
            if model.findings.isEmpty {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.04)).frame(height: 18)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)], alignment: .leading, spacing: 10) {
                    ForEach(model.findings) { f in FindingRow(finding: f) }
                }
            }
        }
        .padding(18)
        .panel()
    }

    // MARK: Tasks

    private func categoryPanel(_ category: MaintenanceCategory) -> some View {
        let tasks = model.tasks(in: category)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: category.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
                Text(category.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(tasks.count)").font(.mono(11)).foregroundStyle(Palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            ForEach(tasks) { task in
                Rectangle().fill(Palette.border).frame(height: 1)
                TaskRow(task: task, model: model)
            }
        }
        .panel()
    }
}

// MARK: - Rows

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text)
                Text(finding.detail).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var color: Color {
        switch finding.severity {
        case .ok: Palette.success
        case .info: Palette.info
        case .warning: Palette.warning
        }
    }
}

private struct TaskRow: View {
    let task: MaintenanceTask
    let model: OptimizeModel
    @State private var hovering = false

    private var ready: Bool { model.isReady(task) }
    private var state: OptimizeModel.TaskState { model.states[task.id] ?? .idle }
    private var isExpanded: Bool { model.expanded.contains(task.id) }
    private var showCommands: Bool { model.preview || isExpanded }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CheckToggle(state: .init(model.selected.contains(task.id))) { model.toggle(task) }
                .disabled(!ready || model.running)
                .opacity(ready ? 1 : 0.3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ready ? Palette.text : Palette.textSecondary)
                    if task.requiresAdmin { Pill(text: "Admin", color: Palette.warning, symbol: "lock.fill") }
                }
                Text(task.detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = task.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(Palette.warning)
                }
                if showCommands {
                    commandBlock.transition(.opacity.combined(with: .move(edge: .top)))
                }
                if isExpanded, case .done(_, let output, _) = state, !output.isEmpty {
                    ScrollView {
                        Text(output)
                            .font(.mono(10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 140)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.sunken)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border)))
                    .transition(.opacity)
                }
            }

            Spacer(minLength: 12)

            status
                .frame(width: 210, alignment: .trailing)
                .padding(.top, 1)

            Button { model.toggleExpanded(task) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(hovering ? Palette.text : Palette.textTertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide details" : "Show commands and output")
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(hovering ? Color.white.opacity(0.025) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.tidy, value: showCommands)
    }

    private var commandBlock: some View {
        let cmds = task.commands
        return VStack(alignment: .leading, spacing: 2) {
            if cmds.isEmpty {
                Text("# nothing to run").font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
            }
            ForEach(Array(cmds.enumerated()), id: \.offset) { _, cmd in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.requiresAdmin ? "#" : "$").font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                    Text(cmd).font(.mono(10.5)).foregroundStyle(Palette.text).textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.sunken)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border)))
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(task.requiresAdmin ? "Waiting for admin…" : "Running…")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            }
            .transition(.opacity)
        case .done(.applied, _, let duration):
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.success)
                Text("Done").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.success)
                Text(String(format: "%.1fs", duration)).font(.mono(11)).foregroundStyle(Palette.textTertiary)
            }
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        case .done(.failed(let reason), _, _):
            HStack(spacing: 5) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.danger)
                Text(reason).font(.system(size: 11.5)).foregroundStyle(Palette.danger).lineLimit(1)
            }
            .help(reason)
        case .idle:
            if model.checking && model.readiness[task.id] == nil {
                Text("Checking…").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
            } else if let reason = model.readiness[task.id]?.reason {
                Text(reason)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .help(reason)
            } else if model.preview && model.selected.contains(task.id) {
                Text("Would run").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.info)
            } else {
                HStack(spacing: 5) {
                    Circle().fill(Palette.textTertiary).frame(width: 5, height: 5)
                    Text("Ready").font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }
}
