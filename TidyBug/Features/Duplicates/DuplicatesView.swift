import Charts
import QuickLook
import SwiftUI
import TidyBugCore

/// Byte-identical files and visually similar photos.
struct DuplicatesView: View {
    @State private var model = DuplicatesModel.shared
    @State private var preview: URL?
    @State private var hovered: URL?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            if model.isScanning {
                ScanStatusBar(text: scanLabel, detail: Finder.abbreviate(currentPath)) { model.cancel() }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .overlay(alignment: .bottom) {
            if !model.selectedItems.isEmpty && !model.isScanning {
                actionBar
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.tidy, value: model.selectedItems.isEmpty)
        .animation(.tidy, value: model.mode)
        .animation(.tidy, value: model.isScanning)
        .quickLookPreview($preview)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space) {
            if preview != nil { preview = nil } else if let hovered { preview = hovered }
            return .handled
        }
        .onAppear { focused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Duplicates").pageTitle()
                Text(model.mode == .files
                     ? "Byte-identical files, matched by size, partial hash and full SHA-256. Hardlinks are excluded."
                     : "Near-identical photos (re-exports, resized copies, bursts), compared with Vision feature prints.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button { model.scan() } label: {
                Label(model.hasScanned ? "Rescan" : "Scan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.tidy)
            .disabled(model.isScanning || model.roots.isEmpty)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            ModeSwitch(mode: $model.mode)
            if model.mode == .files {
                Picker("Minimum size", selection: $model.minimumSize) {
                    Text("≥ 100 KB").tag(Int64(100 << 10))
                    Text("≥ 1 MB").tag(Int64(1 << 20))
                    Text("≥ 10 MB").tag(Int64(10 << 20))
                    Text("≥ 100 MB").tag(Int64(100 << 20))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("Ignore files smaller than this")
            } else {
                Picker("Match", selection: $model.strictness) {
                    Text("Identical").tag(1.0)
                    Text("Close").tag(0.5)
                    Text("Loose").tag(0.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .help("Similarity threshold")
            }
            RootsMenu(model: model)
            Spacer()
            if model.hasScanned && !model.isScanning && model.resultCount > 0 {
                Button("Select suggested") { model.selectSuggested() }.buttonStyle(.tidyQuiet)
                Button("Clear selection") { model.selectNone() }.buttonStyle(.tidyQuiet)
            }
        }
    }

    private var scanLabel: String {
        if model.mode == .files {
            guard let p = model.fileProgress else { return "Indexing" }
            return p.phase == .hashing ? "Hashing \(p.hashed.formatted())/\(p.candidates.formatted())"
                                       : "Indexed \(p.filesSeen.formatted()) files"
        }
        guard let p = model.photoProgress else { return "Indexing" }
        return p.analyzed > 0 ? "Analyzing \(p.analyzed.formatted())/\(p.found.formatted())" : "Found \(p.found.formatted()) images"
    }

    private var currentPath: String {
        (model.mode == .files ? model.fileProgress?.currentPath : model.photoProgress?.currentPath) ?? ""
    }

    private var progressFraction: Double? {
        if model.mode == .files, let p = model.fileProgress, p.phase == .hashing, p.candidates > 0 {
            return Double(p.hashed) / Double(p.candidates)
        }
        if model.mode == .photos, let p = model.photoProgress, p.found > 0, p.analyzed > 0 {
            return Double(p.analyzed) / Double(p.found)
        }
        return nil
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            scanning
        } else if !model.hasScanned {
            EmptyStateView(symbol: model.mode.symbol,
                           title: model.mode == .files ? "Find duplicate files" : "Find similar photos",
                           message: model.mode == .files
                               ? "Scans \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s") for files with identical contents. The oldest copy outside Downloads is kept by default."
                               : "Scans \(model.roots.count) folder\(model.roots.count == 1 ? "" : "s") for near-identical images. The Photos library is excluded; use its Duplicates album instead.") {
                VStack(spacing: 10) {
                    Button { model.scan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                        .buttonStyle(.tidyLarge)
                        .disabled(model.roots.isEmpty)
                    Text(model.roots.map(Finder.abbreviate).joined(separator: "  "))
                        .font(.mono(11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        } else if model.resultCount == 0 {
            EmptyStateView(symbol: "checkmark.circle", title: "No duplicates found",
                           message: model.mode == .files
                               ? "No files with identical contents in the scanned folders."
                               : "No near-identical photos at this threshold. Try “Loose” to widen the match.") {
                Button("Rescan") { model.scan() }.buttonStyle(.tidySecondary)
            }
        } else {
            results
        }
    }

    private var scanning: some View {
        VStack(spacing: 12) {
            Spacer()
            LogoMark(state: .scanning, size: 26).padding(6)
            Text(scanLabel)
                .font(.number(26))
                .foregroundStyle(Palette.text)
                .contentTransition(.numericText())
                .animation(.tidy, value: scanLabel)
            if let f = progressFraction {
                GardenProgress(value: f, total: 1).frame(width: 320)
                Text("\(Int(f * 100))%").font(.mono(11.5)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                summary
                if model.mode == .files {
                    ForEach(model.groups) { group in
                        FileGroupPanel(group: group, model: model, hovered: $hovered)
                            .transition(.opacity)
                    }
                } else {
                    ForEach(model.clusters) { cluster in
                        PhotoClusterPanel(cluster: cluster, model: model, hovered: $hovered) { preview = $0 }
                            .transition(.opacity)
                    }
                }
            }
            .padding(.bottom, 96)
        }
        .scrollIndicators(.never)
    }

    private var copyCount: Int {
        model.mode == .files ? model.groups.reduce(0) { $0 + $1.files.count - 1 }
                             : model.clusters.reduce(0) { $0 + $1.photos.count - 1 }
    }

    /// Wasted bytes by file type (files) or by folder (photos), top 6.
    private var breakdown: [(label: String, bytes: Int64)] {
        var totals: [String: Int64] = [:]
        if model.mode == .files {
            for g in model.groups {
                let ext = (g.keeper.name as NSString).pathExtension.lowercased()
                totals[ext.isEmpty ? "(none)" : ".\(ext)", default: 0] += g.wasted
            }
        } else {
            for c in model.clusters {
                let keeper = model.keeperID(c)
                for p in c.photos where p.id != keeper {
                    totals[p.url.deletingLastPathComponent().lastPathComponent, default: 0] += p.size
                }
            }
        }
        return totals.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                summaryStat("Reclaimable", BytesText(bytes: model.wastedTotal), color: Palette.warning)
                HStack(spacing: 28) {
                    summaryStat(model.mode == .files ? "Groups" : "Clusters",
                                Text("\(model.resultCount)").monospacedDigit(), color: Palette.text)
                    summaryStat("Redundant copies", Text("\(copyCount)").monospacedDigit(), color: Palette.text)
                    summaryStat("Selected", BytesText(bytes: model.selectedBytes), color: Palette.accent)
                }
            }
            .padding(18)
            .frame(width: 400, alignment: .leading)
            .panel()

            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: model.mode == .files ? "Reclaimable by type" : "Reclaimable by folder")
                Chart(breakdown, id: \.label) { row in
                    BarMark(x: .value("Bytes", Double(row.bytes)), y: .value("Label", row.label))
                        .foregroundStyle(Palette.warning.opacity(0.85))
                        .cornerRadius(3)
                        .annotation(position: .trailing, spacing: 6) {
                            Text(row.bytes.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.mono(11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartPlotStyle { $0.padding(.trailing, 64) }
                .frame(height: CGFloat(max(breakdown.count, 1)) * 22 + 4)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()
        }
    }

    private func summaryStat<V: View>(_ label: String, _ value: V, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.textTertiary)
            value.font(.number(label == "Reclaimable" ? 26 : 17)).foregroundStyle(color)
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 14) {
            Text("\(model.selectedItems.count) selected")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
            BytesText(bytes: model.selectedBytes)
                .font(.mono(13, weight: .semibold))
                .foregroundStyle(Palette.text)
            Spacer()
            KeyHint(keys: "space  Quick Look")
            Button {
                for item in model.selectedItems { AppModel.shared.stage(item, source: "duplicates") }
            } label: { Label("Add selected to Collector", systemImage: "tray.and.arrow.down") }
                .buttonStyle(.tidySecondary)
            Button { model.trashSelected() } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.tidyDanger)
                .keyboardShortcut(.delete, modifiers: .command)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .frame(maxWidth: 640)
        .panel(radius: 12, lifted: true)
    }
}

// MARK: - Mode switch

struct ModeSwitch: View {
    @Binding var mode: DuplicatesModel.Mode
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DuplicatesModel.Mode.allCases) { m in
                let selected = mode == m
                Button {
                    withAnimation(.tidy) { mode = m }
                } label: {
                    Label(m.rawValue, systemImage: m.symbol)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4.5)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border))
                                    .matchedGeometryEffect(id: "dup-mode", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border)))
    }
}

struct RootsMenu: View {
    let model: DuplicatesModel

    var body: some View {
        Menu {
            Section("Scan locations") {
                ForEach(model.roots, id: \.self) { root in
                    Button {
                        withAnimation(.tidy) { model.roots.removeAll { $0 == root } }
                    } label: {
                        Label(Finder.abbreviate(root), systemImage: "minus.circle")
                    }
                }
            }
            Divider()
            Button("Add Folder…") {
                if let p = Finder.chooseFolder(startingAt: NSHomeDirectory()), !model.roots.contains(p) {
                    model.roots.append(p)
                }
            }
            Button("Reset to Defaults") { model.roots = DuplicatesModel.defaultRoots }
        } label: {
            Label("\(model.roots.count) location\(model.roots.count == 1 ? "" : "s")", systemImage: "folder")
        }
        .menuStyle(.button)
        .buttonStyle(.tidySecondary)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - File groups

struct FileGroupPanel: View {
    let group: DuplicateGroup
    let model: DuplicatesModel
    @Binding var hovered: URL?

    var body: some View {
        let keeper = model.keeperID(group)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                FileIcon(path: group.keeper.url.path, size: 20)
                Text(group.keeper.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text("\(group.size.formattedBytes) × \(group.files.count)")
                    .font(.mono(11.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text(group.wasted.formattedBytes).font(.mono(12, weight: .semibold)).foregroundStyle(Palette.warning)
                Text("reclaimable").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            Rectangle().fill(Palette.border).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(group.files) { file in
                    DuplicateRow(file: file, isKeeper: file.id == keeper,
                                 selected: model.fileSelection.contains(file.id),
                                 toggle: { model.toggleFile(file, in: group) },
                                 makeKeeper: { model.makeKeeper(file, in: group) },
                                 hovered: $hovered)
                }
            }
            .padding(.vertical, 4)
        }
        .panel()
    }
}

struct DuplicateRow: View {
    let file: DuplicateFile
    let isKeeper: Bool
    let selected: Bool
    let toggle: () -> Void
    let makeKeeper: () -> Void
    @Binding var hovered: URL?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isKeeper {
                    Text("KEEP")
                        .font(.system(size: 9.5, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(Palette.success)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.success.opacity(0.13)))
                } else {
                    CheckToggle(state: .init(selected), action: toggle)
                }
            }
            .frame(width: 38, alignment: .leading)
            .animation(.tidy, value: isKeeper)

            Text(Finder.abbreviate(file.url.path))
                .font(.mono(11.5))
                .foregroundStyle(isKeeper ? Palette.text : (selected ? Palette.textSecondary : Palette.text))
                .strikethrough(selected, color: Palette.accent.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.head)
            if !file.autoSelectable && !isKeeper {
                Pill(text: "in project", color: Palette.warning, symbol: "hammer")
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 0) {
                    if !isKeeper { Button("Keep this copy", action: makeKeeper).buttonStyle(.tidyQuiet) }
                    Button { Finder.reveal(file.url) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.tidyQuiet)
                        .help("Reveal in Finder")
                }
                .transition(.opacity)
            }
            Text(file.modified, format: .dateTime.year().month(.abbreviated).day())
                .font(.mono(11))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.035) : .clear)
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { hovered = file.url } else if hovered == file.url { hovered = nil }
        }
        .onTapGesture { if !isKeeper { toggle() } }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .draggable(file.url)
        .contextMenu {
            if !isKeeper { Button("Keep This Copy", action: makeKeeper) }
            Button("Add to Collector") { AppModel.shared.stage(file.item, source: "duplicates") }
            Button("Reveal in Finder") { Finder.reveal(file.url) }
        }
    }
}

// MARK: - Photo clusters

struct PhotoClusterPanel: View {
    let cluster: PhotoCluster
    let model: DuplicatesModel
    @Binding var hovered: URL?
    let preview: (URL) -> Void

    var body: some View {
        let keeper = model.keeperID(cluster)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(cluster.photos.count) similar photos")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Pill(text: cluster.likeness,
                     color: cluster.isNearIdentical ? Palette.warning : Palette.info)
                Spacer()
                Text(cluster.wasted.formattedBytes).font(.mono(12, weight: .semibold)).foregroundStyle(Palette.warning)
                Text("reclaimable").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 10)], spacing: 10) {
                ForEach(cluster.photos) { photo in
                    PhotoTile(photo: photo, isKeeper: photo.id == keeper,
                              selected: model.photoSelection.contains(photo.id),
                              toggle: { model.togglePhoto(photo, in: cluster) },
                              makeKeeper: { model.makeKeeper(photo, in: cluster) },
                              preview: { preview(photo.url) },
                              hovered: $hovered)
                }
            }
        }
        .padding(14)
        .panel()
    }
}

struct PhotoTile: View {
    let photo: SimilarPhoto
    let isKeeper: Bool
    let selected: Bool
    let toggle: () -> Void
    let makeKeeper: () -> Void
    let preview: () -> Void
    @Binding var hovered: URL?

    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                    } else {
                        Rectangle().fill(Palette.sunken).overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.accent.opacity(selected ? 0.22 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isKeeper ? Palette.success : (selected ? Palette.accent : (hovering ? Palette.borderStrong : Palette.border)),
                                      lineWidth: isKeeper || selected ? 2 : 1)
                }

                if isKeeper {
                    Text("KEEP")
                        .font(.system(size: 9.5, weight: .bold)).kerning(0.6)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.success))
                        .padding(7)
                } else {
                    CheckToggle(state: .init(selected), action: toggle).padding(7)
                }
            }
            HStack {
                Text("\(photo.pixelWidth)×\(photo.pixelHeight)")
                Spacer()
                Text(photo.size.formattedBytes)
            }
            .font(.mono(10.5))
            .foregroundStyle(Palette.textTertiary)
        }
        .animation(.tidy, value: selected)
        .animation(.tidy, value: isKeeper)
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { hovered = photo.url } else if hovered == photo.url { hovered = nil }
        }
        .onTapGesture(count: 2, perform: preview)
        .onTapGesture { if !isKeeper { toggle() } }
        .help(Finder.abbreviate(photo.url.path))
        .draggable(photo.url)
        .contextMenu {
            Button("Quick Look", action: preview)
            if !isKeeper { Button("Keep This One", action: makeKeeper) }
            Button("Add to Collector") { AppModel.shared.stage(photo.item, source: "duplicates") }
            Button("Reveal in Finder") { Finder.reveal(photo.url) }
        }
        .task(id: photo.id) {
            let img = await ThumbnailCache.shared.image(for: photo.url)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
    }
}
