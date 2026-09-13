import Charts
import QuickLook
import SwiftUI
import TidyBugCore

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\LargeFile.item.size, order: .reverse)]
    @State private var highlighted = Set<String>()
    @State private var preview: URL?
    @State private var kindFilter: LargeFile.Kind?

    private var rows: [LargeFile] {
        model.largeFiles.filter { kindFilter == nil || $0.kind == kindFilter }.sorted(using: sortOrder)
    }
    private var selectedBytes: Int64 {
        model.largeFiles.filter { model.largeSelection.contains($0.id) }.reduce(0) { $0 + $1.item.size }
    }

    struct KindRow: Identifiable {
        var id: String { kind.rawValue }
        let kind: LargeFile.Kind
        let bytes: Int64
        let count: Int
    }

    private var kindRows: [KindRow] {
        Dictionary(grouping: model.largeFiles, by: \.kind)
            .map { KindRow(kind: $0.key, bytes: $0.value.reduce(0) { $0 + $1.item.size }, count: $0.value.count) }
            .sorted { $0.bytes > $1.bytes }
    }

    static let minimums: [(String, Int64)] = [("50 MB", 50 << 20), ("100 MB", 100 << 20), ("500 MB", 500 << 20), ("1 GB", 1 << 30)]

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Large Files",
                         subtitle: "Files above the size threshold outside ~/Library. Press Space to preview.") {
                Picker("Minimum", selection: $model.largeMinimum) {
                    ForEach(Self.minimums, id: \.1) { Text($0.0).tag($0.1) }
                }
                .labelsHidden()
                .fixedSize()
                Button {
                    if let p = Finder.chooseFolder(startingAt: model.largeRoot) { model.largeRoot = p; model.scanLargeFiles() }
                } label: {
                    Label(Finder.abbreviate(model.largeRoot), systemImage: "folder").font(.mono(11.5))
                }
                .buttonStyle(.tidySecondary)
                Button { model.scanLargeFiles() } label: {
                    Label(model.largeScanned ? "Rescan" : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.tidy)
                .disabled(model.largeScanning)
            }

            if model.largeScanning {
                ScanStatusBar(text: "Scanning", detail: Finder.abbreviate(model.largeCurrent)) { model.cancelLargeFiles() }
            }

            if !model.largeScanned {
                EmptyStateView(symbol: "doc.text.magnifyingglass", title: "No scan yet",
                               message: "Find ISOs, videos, dumps and archives above the size threshold in your home folder.") {
                    Button { model.scanLargeFiles() } label: { Label("Scan Home Folder", systemImage: "magnifyingglass") }
                        .buttonStyle(.tidyLarge)
                }
            } else {
                kindChips
                HStack(alignment: .top, spacing: 14) {
                    table
                    kindChart.frame(width: 280)
                }
                HStack(spacing: 8) {
                    Text("\(model.largeFiles.count) files · \(model.largeFiles.reduce(0) { $0 + $1.item.size }.formattedBytes)")
                        .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("\(model.largeSelection.count) selected · \(selectedBytes.formattedBytes)")
                        .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                    Button("Move to Trash") { model.trashSelectedLargeFiles() }
                        .buttonStyle(.tidy)
                        .disabled(model.largeSelection.isEmpty)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 18)
        .quickLookPreview($preview)
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", count: model.largeFiles.count, active: kindFilter == nil) { kindFilter = nil }
                ForEach(kindRows) { row in
                    chip(row.kind.rawValue, count: row.count, active: kindFilter == row.kind) { kindFilter = row.kind }
                }
            }
        }
    }

    private func chip(_ title: String, count: Int, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.tidy) { action() }
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? Palette.text : Palette.textSecondary)
                Text("\(count)").font(.mono(11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .paperCapsule(selected: active)
        }
        .buttonStyle(.plain)
    }

    private var table: some View {
        Table(rows, selection: $highlighted, sortOrder: $sortOrder) {
            TableColumn("") { f in
                CheckToggle(state: .init(model.largeSelection.contains(f.id))) { toggle(f) }
            }
            .width(22)
            TableColumn("Name", value: \.item.name) { f in
                HStack(spacing: 8) {
                    FileIcon(path: f.item.url.path, size: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.item.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(Finder.abbreviate(f.item.url.deletingLastPathComponent().path))
                            .font(.mono(10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .draggable(f.item.url) {
                    Text(f.item.name).font(.mono(12)).padding(.horizontal, 8).padding(.vertical, 4).paperCapsule()
                }
            }
            TableColumn("Kind", value: \.kind.rawValue) { f in
                Text(f.kind.rawValue).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            .width(84)
            TableColumn("Size", value: \.item.size) { f in
                Text(f.item.size.formattedBytes).font(.mono(12, weight: .medium)).foregroundStyle(Palette.text)
            }
            .width(84)
            TableColumn("Last used", value: \.accessed) { f in AgeBadge(days: f.ageDays) }
                .width(72)
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Quick Look") { preview = model.largeFiles.first { ids.contains($0.id) }?.item.url }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(model.largeFiles.filter { ids.contains($0.id) }.map(\.item.url))
            }
            Button("Toggle Selection") { for f in model.largeFiles where ids.contains(f.id) { toggle(f) } }
            Button("Add to Collector") {
                for f in model.largeFiles where ids.contains(f.id) { model.stage(f.item, source: "large-files") }
            }
        } primaryAction: { ids in
            preview = model.largeFiles.first { ids.contains($0.id) }?.item.url
        }
        .onKeyPress(.space) {
            preview = preview == nil ? model.largeFiles.first { highlighted.contains($0.id) }?.item.url : nil
            return .handled
        }
        .padding(4)
        .panel()
        .overlay {
            if model.largeFiles.isEmpty && !model.largeScanning {
                Text("No files above the threshold.").font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private var kindChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "By kind")
            if kindRows.isEmpty {
                Text("—").font(.mono(12)).foregroundStyle(Palette.textTertiary)
            } else {
                Chart(Array(kindRows.enumerated()), id: \.element.id) { i, row in
                    SectorMark(angle: .value("Bytes", Double(row.bytes)), innerRadius: .ratio(0.62), angularInset: 1.2)
                        .foregroundStyle(Palette.series[i % Palette.series.count])
                        .opacity(kindFilter == nil || kindFilter == row.kind ? 1 : 0.3)
                }
                .frame(height: 150)
                .animation(.tidy, value: kindFilter)
                VStack(spacing: 6) {
                    ForEach(Array(kindRows.enumerated()), id: \.element.id) { i, row in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.series[i % Palette.series.count]).frame(width: 8, height: 8)
                            Text(row.kind.rawValue).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(row.bytes.formattedBytes).font(.mono(11)).foregroundStyle(Palette.text)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    private func toggle(_ f: LargeFile) {
        withAnimation(.tidy) {
            if model.largeSelection.contains(f.id) { model.largeSelection.remove(f.id) } else { model.largeSelection.insert(f.id) }
        }
    }
}
