import Charts
import SwiftUI
import TidyBugCore

struct PurgeView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ProjectArtifact.item.size, order: .reverse)]
    @State private var highlighted = Set<String>()
    @State private var staleDays = 30

    private var rows: [ProjectArtifact] { model.artifacts.sorted(using: sortOrder) }
    private var totalBytes: Int64 { model.artifacts.reduce(0) { $0 + $1.item.size } }
    private var staleBytes: Int64 {
        model.artifacts.filter { $0.ageDays >= staleDays && $0.reinstallable }.reduce(0) { $0 + $1.item.size }
    }
    private var selectedBytes: Int64 {
        model.artifacts.filter { model.purgeSelection.contains($0.id) }.reduce(0) { $0 + $1.item.size }
    }

    struct KindRow: Identifiable {
        var id: String { kind }
        let kind: String
        let bytes: Int64
        let count: Int
    }

    private var kindRows: [KindRow] {
        Dictionary(grouping: model.artifacts, by: \.kind)
            .map { KindRow(kind: $0.key, bytes: $0.value.reduce(0) { $0 + $1.item.size }, count: $0.value.count) }
            .sorted { $0.bytes > $1.bytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            roots
            if model.purgeScanning {
                ScanStatusBar(text: "Scanning projects", detail: Finder.abbreviate(model.purgeCurrent)) { model.cancelProjects() }
            }
            if !model.purgeScanned {
                EmptyStateView(symbol: "hammer", title: "No project scan yet",
                               message: "Finds node_modules, Xcode build folders, .next, .venv, Pods, Rust target and more. Only folders that a lockfile or manifest can recreate are suggested. Signed archives are never touched.") {
                    Button { model.scanProjects() } label: { Label("Scan Projects", systemImage: "magnifyingglass") }
                        .buttonStyle(.tidyLarge)
                }
            } else {
                stats
                HStack(alignment: .top, spacing: 14) {
                    table
                    kindChart.frame(width: 300)
                }
                actionBar
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 18)
    }

    private var header: some View {
        ScreenHeader(title: "Projects",
                     subtitle: "Build artifacts that can be regenerated from a lockfile or manifest.") {
            if model.purgeScanned {
                Button { model.scanProjects() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.tidySecondary).disabled(model.purgeScanning)
            }
        }
    }

    private var roots: some View {
        HStack(spacing: 8) {
            Text("Roots").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.purgeRoots, id: \.self) { root in
                        HStack(spacing: 6) {
                            Text(Finder.abbreviate(root)).font(.mono(11.5)).foregroundStyle(Palette.text)
                            Button {
                                withAnimation(.tidy) { model.purgeRoots.removeAll { $0 == root } }
                            } label: { Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .paperCapsule()
                        .transition(.opacity)
                    }
                    Button {
                        if let path = Finder.chooseFolder(startingAt: NSHomeDirectory()), !model.purgeRoots.contains(path) {
                            withAnimation(.tidy) { model.purgeRoots.append(path) }
                        }
                    } label: { Label("Add", systemImage: "plus") }
                        .buttonStyle(.tidyQuiet)
                }
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            StatTile(title: "Found", bytes: totalBytes, caption: "\(model.artifacts.count) folders", color: Palette.info)
            StatTile(title: "Stale and reinstallable", bytes: staleBytes, caption: "untouched for \(staleDays)+ days", color: Palette.warning) {
                Picker("", selection: $staleDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("1 year").tag(365)
                }
                .labelsHidden()
                .fixedSize()
            }
            StatTile(title: "Selected", bytes: selectedBytes, caption: "\(model.purgeSelection.count) folders", color: Palette.accent)
        }
    }

    private var table: some View {
        Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { a in
                CheckToggle(state: .init(model.purgeSelection.contains(a.id))) { toggle(a) }
                    .disabled(!a.item.isRemovable)
                    .opacity(a.item.isRemovable ? 1 : 0.3)
            }
            .width(22)
            TableColumn("Project", value: \.projectName) { a in
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.projectName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text)
                    Text(Finder.abbreviate(a.projectPath)).font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .draggable(a.item.url) {
                    Text("\(a.projectName)/\(a.item.name)").font(.mono(12)).padding(.horizontal, 8).padding(.vertical, 4).paperCapsule()
                }
            }
            TableColumn("Folder", value: \.kind) { a in
                VStack(alignment: .leading, spacing: 1) {
                    Text(a.item.name).font(.mono(11.5)).foregroundStyle(Palette.text)
                    if a.item.name != a.kind { Text(a.kind).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary) }
                }
            }
            .width(min: 110, ideal: 150)
            TableColumn("Size", value: \.item.size) { a in
                Text(a.item.size.formattedBytes).font(.mono(12, weight: .medium)).foregroundStyle(Palette.text)
            }
            .width(84)
            TableColumn("Touched", value: \.projectModified) { a in AgeBadge(days: a.ageDays) }
                .width(70)
            TableColumn("Status") { a in
                HStack(spacing: 4) {
                    if a.item.containsProtected {
                        Pill(text: "archive · kept", color: Palette.danger, symbol: "lock.fill")
                    } else if a.reinstallable {
                        Pill(text: "lockfile", color: Palette.success)
                    } else {
                        Pill(text: "no lockfile", color: Palette.warning)
                    }
                    if a.item.containsData { Pill(text: "data", color: Palette.warning) }
                }
            }
            .width(min: 100, ideal: 130)
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Toggle Selection") { for a in model.artifacts where ids.contains(a.id) { toggle(a) } }
            Button("Add to Collector") {
                for a in model.artifacts where ids.contains(a.id) && a.item.isRemovable { model.stage(a.item, source: "projects") }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(model.artifacts.filter { ids.contains($0.id) }.map(\.item.url))
            }
        } primaryAction: { ids in
            for a in model.artifacts where ids.contains(a.id) { toggle(a) }
        }
        .padding(4)
        .panel()
        .overlay {
            if model.artifacts.isEmpty && !model.purgeScanning {
                Text("No build artifacts found in these roots.").font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var kindChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "By type")
            if kindRows.isEmpty {
                Text("—").font(.mono(12)).foregroundStyle(Palette.textTertiary)
            } else {
                Chart(Array(kindRows.enumerated()), id: \.element.id) { i, row in
                    BarMark(x: .value("Bytes", Double(row.bytes)), y: .value("Type", row.kind))
                        .foregroundStyle(Palette.series[i % Palette.series.count])
                        .cornerRadius(2)
                        .annotation(position: .trailing, spacing: 4) {
                            Text(row.bytes.formattedBytes).font(.mono(10)).foregroundStyle(Palette.textSecondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartPlotStyle { $0.padding(.trailing, 56) }
                .frame(height: CGFloat(kindRows.count) * 24 + 8)
                .animation(.tidy, value: kindRows.map(\.bytes))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Select stale (\(staleDays)d+)") { model.selectStale(olderThan: staleDays) }
                .buttonStyle(.tidySecondary)
                .popoverTip(ProjectsStaleTip(), arrowEdge: .bottom)
            Button("Clear Selection") { withAnimation(.tidy) { model.purgeSelection = [] } }
                .buttonStyle(.tidyQuiet)
                .disabled(model.purgeSelection.isEmpty)
            Spacer()
            Text("\(model.purgeSelection.count) selected · \(selectedBytes.formattedBytes)")
                .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
            Button("Move to Trash") { model.trashSelectedArtifacts() }
                .buttonStyle(.tidy)
                .disabled(model.purgeSelection.isEmpty)
        }
    }

    private func toggle(_ a: ProjectArtifact) {
        guard a.item.isRemovable else { return }
        withAnimation(.tidy) {
            if model.purgeSelection.contains(a.id) { model.purgeSelection.remove(a.id) } else { model.purgeSelection.insert(a.id) }
        }
    }
}

struct StatTile<Accessory: View>: View {
    let title: String
    let bytes: Int64
    let caption: String
    let color: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                BytesText(bytes: bytes).font(.number(22)).foregroundStyle(Palette.text)
                Text(caption).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            accessory
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .panel()
    }
}

extension StatTile where Accessory == EmptyView {
    init(title: String, bytes: Int64, caption: String, color: Color) {
        self.init(title: title, bytes: bytes, caption: caption, color: color) { EmptyView() }
    }
}
