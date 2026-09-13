import Charts
import SwiftUI
import TidyBugCore

/// Standard page header: title, one-line description, trailing actions.
struct ScreenHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).pageTitle()
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { actions }
        }
    }
}

/// Button label with a trailing shortcut hint.
struct ShortcutLabel: View {
    let title: String
    let symbol: String
    let keys: String
    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
            Text(keys).font(.system(size: 11, weight: .medium)).opacity(0.65)
        }
    }
}

struct SmartCleanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if model.scanPhase == .scanning {
                    GardenProgress(value: Double(model.results.count), total: Double(model.ruleOrder.count))
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)

            if model.scanPhase == .idle && model.results.isEmpty {
                EmptyStateView(symbol: "sparkles", title: "No scan results",
                               message: "Scan \(model.ruleOrder.count) known locations: app caches, Xcode data, package-manager caches, installers, database dumps and large app data. Nothing is removed without confirmation.") {
                    Button { model.startSmartScan() } label: {
                        ShortcutLabel(title: "Scan", symbol: "arrow.clockwise", keys: "⌘R")
                    }
                    .buttonStyle(.tidyLarge)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !summaryRows.isEmpty { summaryPanel }
                        ForEach(RuleGroup.allCases, id: \.self) { group in
                            let rs = model.visibleResults.filter { $0.rule.group == group }
                            if !rs.isEmpty { groupPanel(group, rs) }
                        }
                        if model.scanPhase == .scanning { PlaceholderCard() }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.never)
                .overlay(alignment: .bottom) { cleanBar.padding(.bottom, 18).padding(.horizontal, 28) }
            }
        }
        .animation(.tidy, value: model.scanPhase)
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Clean", subtitle: status) {
            if model.scanPhase == .scanning {
                LogoMark(state: .scanning, size: 13).padding(4)
                Text("\(model.results.count)/\(model.ruleOrder.count)").font(.mono(12)).foregroundStyle(Palette.textSecondary)
                Button("Stop") { model.cancelScan() }.buttonStyle(.tidySecondary)
            } else if !model.results.isEmpty {
                Button { model.startSmartScan() } label: {
                    ShortcutLabel(title: "Rescan", symbol: "arrow.clockwise", keys: "⌘R")
                }
                .buttonStyle(.tidySecondary)
                .disabled(model.scanPhase == .cleaning)
            }
        }
    }

    private var status: String {
        switch model.scanPhase {
        case .idle: return "Reclaim space from caches, build data and leftovers."
        case .scanning: return "Scanning \(model.results.count) of \(model.ruleOrder.count) locations…"
        case .cleaning: return "Removing selected items…"
        case .ready:
            let when = model.lastScan.map { " · scanned \($0.formatted(.relative(presentation: .named)))" } ?? ""
            let n = model.visibleResults.filter { $0.rule.safety != .advisor && $0.total > 0 }.count
            return "\(model.reclaimableTotal.formattedBytes) reclaimable in \(n) categories\(when). Safe items are preselected."
        }
    }

    // MARK: Summary chart

    struct SummaryRow: Identifiable {
        var id: String { group + safety }
        let group: String
        let safety: String
        let bytes: Int64
    }

    private var summaryRows: [SummaryRow] {
        var rows: [SummaryRow] = []
        for group in RuleGroup.allCases {
            for level in [SafetyLevel.safe, .review] {
                let bytes = model.visibleResults.filter { $0.rule.group == group && $0.rule.safety == level }
                    .reduce(0) { $0 + $1.total }
                if bytes > 0 { rows.append(SummaryRow(group: group.rawValue, safety: level == .safe ? "Safe" : "Review", bytes: bytes)) }
            }
        }
        return rows
    }

    private var summaryPanel: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                metric("Reclaimable", model.reclaimableTotal, Palette.info)
                metric("Safe", model.safeTotal, Palette.success)
                metric("Selected", model.selectedBytes, Palette.accent)
            }
            .frame(width: 150, alignment: .leading)
            Rectangle().fill(Palette.border).frame(width: 1)
            Chart(summaryRows) { row in
                BarMark(x: .value("Bytes", Double(row.bytes)), y: .value("Group", row.group))
                    .foregroundStyle(by: .value("Safety", row.safety))
                    .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: ["Safe", "Review"], range: [Palette.success, Palette.warning])
            .chartLegend(position: .top, alignment: .trailing, spacing: 10)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Palette.border)
                    AxisValueLabel {
                        if let d = value.as(Double.self) { Text(d == 0 ? "0" : Int64(d).formattedBytes) }
                    }
                    .font(.mono(10)).foregroundStyle(Palette.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel().font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(height: CGFloat(Set(summaryRows.map(\.group)).count) * 30 + 44)
            .animation(.tidy, value: summaryRows.map(\.bytes))
        }
        .padding(18)
        .panel()
    }

    private func metric(_ label: String, _ bytes: Int64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            BytesText(bytes: bytes).font(.number(20)).foregroundStyle(Palette.text)
        }
    }

    // MARK: Groups

    private func groupPanel(_ group: RuleGroup, _ results: [RuleResult]) -> some View {
        VStack(spacing: 0) {
            GroupHeader(group: group, total: results.reduce(0) { $0 + $1.total }, count: results.count)
            ForEach(results) { r in
                Rectangle().fill(Palette.border).frame(height: 1)
                RuleCard(result: r)
                    .transition(.opacity)
            }
        }
        .panel()
    }

    // MARK: Action bar

    private var cleanBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Selected").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                BytesText(bytes: model.selectedBytes).font(.mono(15, weight: .semibold)).foregroundStyle(Palette.text)
            }
            Text("\(model.selectedCount) item\(model.selectedCount == 1 ? "" : "s")")
                .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
            Spacer()
            if model.scanPhase == .cleaning { ProgressView().controlSize(.small) }
            Text(model.permanentForCaches ? "Caches are deleted permanently" : "Items are moved to the Trash")
                .font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
            Button { model.requestSmartClean() } label: {
                Text(model.permanentForCaches ? "Clean \(model.selectedBytes.formattedBytes)" : "Move to Trash")
            }
            .buttonStyle(.tidy)
            .disabled(model.selectedBytes == 0 || model.scanPhase != .ready)
            .popoverTip(SweepReviewTip(), arrowEdge: .bottom)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .panel(radius: 12, lifted: true)
        .frame(maxWidth: 820)
    }
}

// MARK: - Rows

struct GroupHeader: View {
    let group: RuleGroup
    let total: Int64
    var count: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textTertiary)
            Text(group.rawValue).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
            if count > 0 { Text("\(count)").font(.mono(11)).foregroundStyle(Palette.textTertiary) }
            Spacer()
            BytesText(bytes: total).font(.mono(12, weight: .medium)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct RuleCard: View {
    @Environment(AppModel.self) private var model
    let result: RuleResult
    @State private var expanded = false
    @State private var hovering = false

    private var rule: CleanRule { result.rule }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if rule.safety != .advisor {
                    CheckToggle(state: model.checkState(for: result)) { model.toggle(result) }
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                RuleIcon(symbol: rule.symbol, hue: rule.hue, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(rule.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                        SafetyBadge(level: rule.safety)
                        if rule.permanentOnly { Pill(text: "permanent", color: Palette.danger) }
                        if rule.isCommandBased, let c = rule.command {
                            Text(c.tool).font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border))
                        }
                    }
                    Text(rule.detail).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 12)
                if !result.items.isEmpty {
                    Text("\(result.items.count) item\(result.items.count == 1 ? "" : "s")")
                        .font(.mono(11)).foregroundStyle(Palette.textTertiary)
                }
                Group {
                    if result.total > 0 { BytesText(bytes: result.total) } else { Text("—") }
                }
                .font(.mono(12.5, weight: .medium))
                .foregroundStyle(result.total > 0 ? Palette.text : Palette.textTertiary)
                .frame(width: 84, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .opacity(result.items.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(hovering ? Color.white.opacity(0.025) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { if !result.items.isEmpty { withAnimation(.tidy) { expanded.toggle() } } }

            if rule.safety == .advisor { advice.padding(.leading, 66).padding([.trailing, .bottom], 14) }

            if expanded {
                VStack(spacing: 0) {
                    ForEach(result.items.prefix(150)) { item in
                        ItemRow(item: item, selectable: rule.safety != .advisor && !rule.isCommandBased,
                                selected: model.selectedItems.contains(item.id)) { model.toggle(item: item) }
                    }
                    if result.items.count > 150 {
                        Text("\(result.items.count - 150) more items not shown")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary).padding(8)
                    }
                }
                .padding(.bottom, 6)
                .background(Palette.sunken.opacity(0.5))
                .transition(.opacity)
            }
        }
    }

    private var advice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.violet)
            VStack(alignment: .leading, spacing: 8) {
                if let note = result.probeNote {
                    Text(note).font(.mono(11.5, weight: .medium)).foregroundStyle(Palette.text)
                }
                if let text = rule.advice {
                    Text(text).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if let url = rule.openURL, FileManager.default.fileExists(atPath: url.path) {
                        Button("Open \(url.deletingPathExtension().lastPathComponent)") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.tidySecondary)
                    }
                    if let command = rule.command {
                        Button { model.requestAdvisorCommand(result) } label: {
                            if model.runningAdvisorCommand == result.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(command.display).font(.mono(11.5))
                            }
                        }
                        .buttonStyle(.tidySecondary)
                        .disabled(model.runningAdvisorCommand != nil || (result.probeBytes ?? 0) == 0)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.sunken)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border)))
    }
}

struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CleanItem
    let selectable: Bool
    let selected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            if selectable {
                CheckToggle(state: .init(selected), action: toggle)
                    .disabled(!item.isRemovable)
                    .opacity(item.isRemovable ? 1 : 0.3)
            }
            FileIcon(path: item.url.path, size: 16)
            Text(item.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
            if item.containsProtected { Pill(text: "release artifact · kept", color: Palette.danger, symbol: "lock.fill") }
            if item.containsData { Pill(text: "contains data", color: Palette.warning) }
            Text(Finder.abbreviate(item.url.deletingLastPathComponent().path))
                .font(.mono(11)).foregroundStyle(Palette.textTertiary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if let m = item.modified {
                Text(m, format: .relative(presentation: .numeric))
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Text(item.size.formattedBytes).font(.mono(12)).foregroundStyle(Palette.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Button { Finder.reveal(item.url) } label: { Image(systemName: "arrow.up.forward.square") }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .help("Reveal in Finder")
                .opacity(hovering ? 1 : 0)
        }
        .padding(.leading, 42).padding(.trailing, 14).padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .onHover { hovering = $0 }
        .draggable(item.url) {
            Text(item.name).font(.mono(12)).padding(.horizontal, 8).padding(.vertical, 4).paperCapsule()
        }
        .contextMenu {
            if item.isRemovable { Button("Add to Collector") { model.stage(item, source: "clean") } }
            Button("Reveal in Finder") { Finder.reveal(item.url) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.path, forType: .string)
            }
        }
    }
}

/// Skeleton row shown while results stream in.
struct PlaceholderCard: View {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Palette.raised).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.raised).frame(width: 150, height: 9)
                RoundedRectangle(cornerRadius: 3).fill(Palette.raised.opacity(0.6)).frame(width: 260, height: 7)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(Palette.raised).frame(width: 60, height: 10)
        }
        .padding(14)
        .overlay {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.04), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.35)
                    .offset(x: phase * geo.size.width)
            }
            .clipped()
        }
        .panel()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.2 }
        }
    }
}
