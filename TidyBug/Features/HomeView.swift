import Charts
import SwiftUI
import TidyBugCore

/// Overview dashboard: volume, reclaimable space by category, largest items, activity.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statRow
                VolumeBreakdown()
                HStack(alignment: .top, spacing: 16) {
                    reclaimablePanel.frame(maxWidth: .infinity)
                    largestPanel.frame(width: 420)
                }
                HStack(alignment: .top, spacing: 16) {
                    toolsPanel.frame(maxWidth: .infinity)
                    activityPanel.frame(width: 420)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 1260)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Overview").pageTitle()
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            switch model.scanPhase {
            case .scanning:
                HStack(spacing: 10) {
                    LogoMark(state: .scanning, size: 14).padding(4)
                    Text("Scanning \(model.results.count)/\(model.ruleOrder.count)")
                        .font(.mono(12)).foregroundStyle(Palette.textSecondary)
                    Button("Stop") { model.cancelScan() }.buttonStyle(.tidySecondary)
                }
            case .cleaning:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Cleaning…").font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                }
            default:
                Button { model.startSmartScan() } label: {
                    HStack(spacing: 8) {
                        Label(model.results.isEmpty ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                        Text("⌘R").font(.system(size: 11, weight: .medium)).opacity(0.7)
                    }
                }
                .buttonStyle(.tidy)
            }
        }
    }

    private var subtitle: String {
        var parts = ["Macintosh HD", "\(model.volume.total.formattedBytes) APFS"]
        if let last = model.lastScan {
            parts.append("scanned \(last.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("not scanned yet")
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Stats

    private var freedAllTime: Int64 { model.history.filter(\.success).reduce(0) { $0 + $1.bytes } }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatCard(label: "Free space", bytes: model.volume.available,
                     footnote: "\(Int((1 - model.volume.usedFraction) * 100))% of \(model.volume.total.formattedBytes)",
                     accent: Brand.pressure(model.volume.usedFraction))
            StatCard(label: "Reclaimable", bytes: model.results.isEmpty ? nil : model.reclaimableTotal,
                     footnote: model.results.isEmpty ? "Run a scan" : "\(model.visibleResults.filter { $0.rule.safety != .advisor && $0.total > 0 }.count) categories",
                     accent: Palette.info)
            StatCard(label: "Safe to clean", bytes: model.results.isEmpty ? nil : model.safeTotal,
                     footnote: "Regenerable caches", accent: Palette.success) {
                if model.scanPhase == .ready && model.safeTotal > 0 {
                    Button("Clean") {
                        model.selectSafeOnly()
                        model.requestSmartClean()
                    }
                    .buttonStyle(.tidySecondary)
                }
            }
            StatCard(label: "Freed with TidyBug", bytes: freedAllTime,
                     footnote: "\(model.history.filter(\.success).count) operations", accent: Palette.violet)
        }
    }

    // MARK: Reclaimable chart

    private var chartResults: [RuleResult] {
        model.visibleResults.filter { $0.rule.safety != .advisor && $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(10).map { $0 }
    }

    private var reclaimablePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: "Reclaimable by category")
                Spacer()
                HStack(spacing: 12) {
                    SafetyBadge(level: .safe)
                    SafetyBadge(level: .review)
                }
            }
            if chartResults.isEmpty {
                placeholder(model.scanPhase == .scanning ? "Collecting results…" : "Run a scan to see what can be reclaimed.",
                            height: 220)
            } else {
                Chart(chartResults) { r in
                    BarMark(x: .value("Size", Double(r.total)), y: .value("Category", r.rule.title))
                        .foregroundStyle(Brand.color(for: r.rule.safety).opacity(0.85))
                        .cornerRadius(3)
                        .annotation(position: .trailing, spacing: 6) {
                            Text(r.total.formattedBytes).font(.mono(11)).foregroundStyle(Palette.textSecondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartPlotStyle { $0.padding(.trailing, 70) }
                .frame(height: CGFloat(chartResults.count) * 26 + 8)
                .animation(.tidy, value: chartResults.map(\.total))
                .onTapGesture { model.pane = .smartClean }
            }
        }
        .padding(18)
        .panel()
    }

    // MARK: Largest items

    private var largestItems: [(item: CleanItem, rule: CleanRule)] {
        model.visibleResults.filter { $0.rule.safety != .advisor }
            .flatMap { r in r.items.map { ($0, r.rule) } }
            .sorted { $0.0.size > $1.0.size }
            .prefix(8).map { (item: $0.0, rule: $0.1) }
    }

    private var largestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Largest items")
            if largestItems.isEmpty {
                placeholder("Nothing yet.", height: 220)
            } else {
                VStack(spacing: 0) {
                    ForEach(largestItems, id: \.item.id) { entry in
                        HStack(spacing: 10) {
                            FileIcon(path: entry.item.url.path, size: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.item.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
                                Text(Finder.abbreviate(entry.item.url.deletingLastPathComponent().path))
                                    .font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            Text(entry.item.size.formattedBytes).font(.mono(12)).foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .contextMenu { Button("Reveal in Finder") { Finder.reveal(entry.item.url) } }
                        if entry.item.id != largestItems.last?.item.id { Divider().overlay(Palette.border) }
                    }
                }
            }
        }
        .padding(18)
        .panel()
    }

    // MARK: Tools

    private var toolsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title: "Tools")
            VStack(spacing: 2) {
                ToolRow(pane: .diskMap, detail: "Interactive map of disk usage", shortcut: "⌘3",
                        stat: model.mapRoot.map { "\($0.size.formattedBytes) mapped" })
                ToolRow(pane: .purge, detail: "node_modules, build dirs, venvs, Pods, target", shortcut: "⌘4",
                        stat: model.artifacts.isEmpty ? nil : model.artifacts.reduce(0) { $0 + $1.item.size }.formattedBytes)
                ToolRow(pane: .duplicates, detail: "Identical files and similar photos", shortcut: "⌘5", stat: nil)
                ToolRow(pane: .largeFiles, detail: "Files over 100 MB outside ~/Library", shortcut: "⌘6",
                        stat: model.largeFiles.isEmpty ? nil : "\(model.largeFiles.count) files")
                ToolRow(pane: .apps, detail: "Uninstall apps with their leftovers", shortcut: "⌘7", stat: nil)
                ToolRow(pane: .optimize, detail: "DNS, Launch Services, Quick Look, databases, memory", shortcut: "⌘8", stat: nil)
                ToolRow(pane: .monitor, detail: "Live CPU, memory, GPU, disk, network and power", shortcut: "⌘9", stat: nil)
            }
        }
        .padding(18)
        .panel()
    }

    // MARK: Activity

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Recent activity")
                Spacer()
                Button("View all") { model.pane = .history }.buttonStyle(.tidyQuiet)
            }
            let recent = Array(model.history.prefix(6))
            if recent.isEmpty {
                placeholder("No cleanups yet.", height: 150)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { entry in
                        HStack(spacing: 10) {
                            Circle().fill(entry.success ? Palette.success : Palette.danger).frame(width: 6, height: 6)
                            Text(Finder.abbreviate(entry.path))
                                .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(entry.bytes.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.text)
                            Text(entry.date, format: .relative(presentation: .numeric))
                                .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                                .frame(width: 76, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(18)
        .panel()
    }

    private func placeholder(_ text: String, height: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

// MARK: - Pieces

struct StatCard<Accessory: View>: View {
    let label: String
    let bytes: Int64?
    let footnote: String
    let accent: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                Spacer()
                accessory
            }
            .frame(height: 22)
            Group {
                if let bytes {
                    BytesText(bytes: bytes)
                } else {
                    Text("—")
                }
            }
            .font(.number(26))
            .foregroundStyle(Palette.text)
            Text(footnote).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}

extension StatCard where Accessory == EmptyView {
    init(label: String, bytes: Int64?, footnote: String, accent: Color) {
        self.init(label: label, bytes: bytes, footnote: footnote, accent: accent) { EmptyView() }
    }
}

/// Segmented bar: used, of which reclaimable, and free.
struct VolumeBreakdown: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let total = Double(max(model.volume.total, 1))
        let reclaimable = min(model.reclaimableTotal, model.volume.used)
        let used = Double(model.volume.used - reclaimable) / total
        let recl = Double(reclaimable) / total
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Storage", subtitle: "\(model.volume.used.formattedBytes) of \(model.volume.total.formattedBytes) used")
                Spacer()
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x3A3F48))
                        .frame(width: max(0, geo.size.width * used - 2))
                    if recl > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.info)
                            .overlay(Stripes().foregroundStyle(.white.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 3)))
                            .frame(width: max(2, geo.size.width * recl - 2))
                            .transition(.scale(scale: 0, anchor: .leading))
                    }
                    RoundedRectangle(cornerRadius: 3).fill(Palette.success.opacity(0.35))
                }
            }
            .frame(height: 12)
            .animation(.gentle, value: model.reclaimableTotal)
            HStack(spacing: 20) {
                legend(Color(hex: 0x3A3F48), "Used", model.volume.used - reclaimable)
                if reclaimable > 0 { legend(Palette.info, "Reclaimable", reclaimable) }
                legend(Palette.success.opacity(0.6), "Free", model.volume.available)
                Spacer()
            }
        }
        .padding(18)
        .panel()
    }

    private func legend(_ color: Color, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            Text(bytes.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.text)
        }
    }
}

struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height + 3, y: rect.minY))
            p.addLine(to: CGPoint(x: x + 3, y: rect.maxY))
            p.closeSubpath()
            x += 7
        }
        return p
    }
}

struct ToolRow: View {
    @Environment(AppModel.self) private var model
    let pane: Pane
    let detail: String
    let shortcut: String
    let stat: String?
    @State private var hovering = false

    var body: some View {
        Button { model.pane = pane } label: {
            HStack(spacing: 12) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.raised)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pane.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if let stat { Text(stat).font(.mono(11.5)).foregroundStyle(Palette.textSecondary) }
                KeyHint(keys: shortcut)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.text : Palette.textTertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.white.opacity(0.04) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
