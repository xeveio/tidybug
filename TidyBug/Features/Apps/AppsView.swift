import Charts
import SwiftUI
import TidyBugCore

/// Apps tab: uninstall apps with their leftovers, or remove leftovers of apps
/// that are already gone.
struct AppsView: View {
    @State private var model = AppsModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenHeader(title: "Apps", subtitle: subtitle) {
                Picker("", selection: $model.mode) {
                    ForEach(AppsModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    model.mode == .installed ? model.scan() : model.scanOrphans()
                } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .buttonStyle(.tidySecondary)
                    .disabled(model.scanning || model.scanningOrphans)
            }
            if let error = model.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.text)
                    Spacer()
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.tidyQuiet)
                }
                .padding(10)
                .panel(radius: 10, tint: Palette.warning)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            switch model.mode {
            case .installed: InstalledAppsSection(model: model)
            case .leftovers: OrphansSection(model: model)
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 18)
        .animation(.tidy, value: model.mode)
        .animation(.tidy, value: model.errorMessage)
        .task {
            if !model.scanned { model.scan() }
            if model.mode == .leftovers && !model.orphansScanned { model.scanOrphans() }
        }
        .onChange(of: model.mode) { _, mode in
            if mode == .leftovers && !model.orphansScanned { model.scanOrphans() }
        }
    }

    private var subtitle: String {
        switch model.mode {
        case .installed:
            if model.scanning { return "Reading /Applications…" }
            let sizing = model.sizing ? " · measuring…" : ""
            return "\(model.apps.count) apps · \(model.totalSize.formattedBytes)\(sizing)"
        case .leftovers:
            if model.scanningOrphans { return "Looking for data left behind by removed apps…" }
            return "\(model.orphans.count) items from \(model.orphanGroups.count) removed apps · \(model.orphanTotal.formattedBytes)"
        }
    }
}

// MARK: - Installed

private struct InstalledAppsSection: View {
    @Bindable var model: AppsModel
    @State private var hoveredID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                searchField
                table
            }
            .frame(maxWidth: .infinity)
            detail
                .frame(width: 380)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            TextField("Filter by name or bundle id", text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border)))
    }

    private var table: some View {
        Table(model.filteredApps, selection: $model.selection, sortOrder: $model.sortOrder) {
            TableColumn("Name", value: \.name) { app in
                HStack(spacing: 9) {
                    FileIcon(path: app.url.path, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text).lineLimit(1)
                        Text(app.bundleID ?? "—").font(.mono(10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    if model.isRunning(app) { Pill(text: "running", color: Palette.success) }
                    if app.isAppStore { Pill(text: "App Store", color: Palette.info) }
                }
                .draggable(app.url)
            }
            TableColumn("Version", value: \.versionText) { app in
                Text(app.versionText).font(.mono(11.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Size", value: \.size) { app in
                if app.isSized {
                    Text(app.size.formattedBytes).font(.mono(12, weight: .medium)).foregroundStyle(Palette.text)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .width(86)
            TableColumn("Last used", value: \.lastUsedSort) { app in
                if let days = app.lastUsedDays {
                    AgeBadge(days: days)
                } else {
                    Text("never").font(.mono(11.5)).foregroundStyle(Palette.textTertiary)
                }
            }
            .width(78)
        }
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            let targets = model.apps.filter { ids.contains($0.id) }
            Button(targets.count == 1 ? "Uninstall \(targets[0].name)…" : "Uninstall \(targets.count) Apps…") {
                model.uninstall(targets)
            }
            .disabled(targets.isEmpty)
            Button("Add to Collector") {
                for app in targets { AppModel.shared.stage(app.url, size: app.isSized ? app.size : nil, source: "apps") }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(targets.map(\.url)) }
        }
        .padding(6)
        .panel()
        .overlay {
            if model.scanning {
                ProgressView().controlSize(.small)
            } else if model.scanned && model.filteredApps.isEmpty {
                Text(model.search.isEmpty ? "No removable apps found." : "No apps match “\(model.search)”.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
            }
        }
        .onChange(of: model.selection) { _, ids in
            for app in model.apps where ids.contains(app.id) { model.loadLeftovers(for: app) }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        let selected = model.selectedApps
        Group {
            if selected.count == 1 {
                AppDetail(model: model, app: selected[0])
            } else if selected.count > 1 {
                MultiDetail(model: model, apps: selected)
            } else {
                overview
            }
        }
        .panel()
    }

    private var overview: some View {
        let top = model.apps.filter(\.isSized).sorted { $0.size > $1.size }.prefix(10).map { $0 }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Size by app", subtitle: "top 10")
            if top.isEmpty {
                Text(model.scanning || model.sizing ? "Measuring…" : "No data yet.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(top) { app in
                    BarMark(x: .value("Size", Double(app.size)), y: .value("App", app.name))
                        .foregroundStyle(Palette.info.opacity(0.85))
                        .cornerRadius(3)
                        .annotation(position: .trailing, spacing: 5) {
                            Text(app.size.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel().font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartPlotStyle { $0.padding(.trailing, 64) }
                .frame(height: CGFloat(top.count) * 24 + 8)
                .animation(.tidy, value: top.map(\.size))
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            Text("Select an app to see every file it installed. Uninstalling moves the app and its data to the Trash.")
                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct AppDetail: View {
    @Bindable var model: AppsModel
    let app: InstalledApp

    private var groups: [(String, [AppLeftover])] {
        let list = model.leftovers[app.id] ?? []
        return Dictionary(grouping: list, by: \.category).sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                FileIcon(path: app.url.path, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    Text(app.bundleID ?? "no bundle id").font(.mono(11)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("v\(app.versionText)").font(.mono(11)).foregroundStyle(Palette.textSecondary)
                        if model.isRunning(app) { Pill(text: "running", color: Palette.success) }
                        if app.isAppStore { Pill(text: "App Store", color: Palette.info) }
                    }
                }
            }
            .padding(18)
            Text(Finder.abbreviate(app.url.path))
                .font(.mono(11)).foregroundStyle(Palette.textSecondary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 18).padding(.bottom, 12)
            Rectangle().fill(Palette.border).frame(height: 1)

            HStack {
                SectionHeading(title: "Files to remove")
                Spacer()
                if model.loadingLeftovers.contains(app.id) { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FileRow(checked: true, locked: true, category: "Application", url: app.url,
                            size: app.isSized ? app.size : nil) {}
                    ForEach(groups, id: \.0) { category, items in
                        HStack {
                            Text(category.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.6)
                                .foregroundStyle(Palette.textTertiary)
                            Spacer()
                            Text(items.reduce(0) { $0 + $1.size }.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 3)
                        ForEach(items) { l in
                            FileRow(checked: !model.excluded.contains(l.id), locked: false, category: nil, url: l.url, size: l.size) {
                                model.toggleExcluded(l)
                            }
                        }
                    }
                    if !model.loadingLeftovers.contains(app.id) && (model.leftovers[app.id]?.isEmpty ?? false) {
                        Text("No related files found in ~/Library.")
                            .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                            .padding(18)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(Palette.border).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    BytesText(bytes: model.totalBytes(for: app)).font(.mono(15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(model.items(for: app).count) items · moved to Trash")
                        .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Button {
                    model.uninstall([app])
                } label: {
                    if model.quitting {
                        ProgressView().controlSize(.small).tint(.white).padding(.horizontal, 20)
                    } else {
                        Label(model.isRunning(app) ? "Quit and Uninstall" : "Uninstall", systemImage: "trash")
                    }
                }
                .buttonStyle(.tidyDanger)
                .disabled(model.quitting || model.loadingLeftovers.contains(app.id))
            }
            .padding(14)
        }
        .onAppear { model.loadLeftovers(for: app) }
    }
}

private struct MultiDetail: View {
    @Bindable var model: AppsModel
    let apps: [InstalledApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(apps.count) apps selected").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            FileIcon(path: app.url.path, size: 18)
                            Text(app.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
                            if model.loadingLeftovers.contains(app.id) { ProgressView().controlSize(.mini) }
                            Spacer()
                            Text(model.totalBytes(for: app).formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack {
                BytesText(bytes: apps.reduce(0) { $0 + model.totalBytes(for: $1) })
                    .font(.mono(15, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Button { model.uninstall(apps) } label: { Label("Uninstall \(apps.count) Apps", systemImage: "trash") }
                    .buttonStyle(.tidyDanger)
                    .disabled(model.quitting)
            }
        }
        .padding(18)
    }
}

private struct FileRow: View {
    let checked: Bool
    let locked: Bool
    let category: String?
    let url: URL
    let size: Int64?
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            CheckToggle(state: .init(checked), action: toggle)
                .disabled(locked)
                .opacity(locked ? 0.6 : 1)
            FileIcon(path: url.path, size: 15)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.system(size: 12)).foregroundStyle(checked ? Palette.text : Palette.textTertiary)
                    .lineLimit(1)
                Text(Finder.abbreviate(url.deletingLastPathComponent().path))
                    .font(.mono(10)).foregroundStyle(Palette.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let category { Pill(text: category, color: Palette.textSecondary) }
            if let size {
                Text(size.formattedBytes).font(.mono(11)).foregroundStyle(Palette.textSecondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 5)
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(url)
        .contextMenu {
            Button("Add to Collector") { AppModel.shared.stage(url, size: size, source: "apps") }
            Button("Reveal in Finder") { Finder.reveal(url) }
        }
    }
}

// MARK: - Leftovers of removed apps

private struct OrphansSection: View {
    @Bindable var model: AppsModel

    var body: some View {
        if model.scanningOrphans && !model.orphansScanned {
            ScanStatusBar(text: "Scanning ~/Library", detail: "Containers, Preferences, Caches, Saved Application State") {}
            Spacer()
        } else if model.orphansScanned && model.orphans.isEmpty {
            EmptyStateView(symbol: "checkmark.seal", title: "No leftovers found",
                           message: "Nothing in ~/Library belongs to an app that is no longer installed.") { EmptyView() }
        } else if !model.orphansScanned {
            EmptyStateView(symbol: "shippingbox", title: "Leftovers of removed apps",
                           message: "Finds containers, preferences, caches and saved state named after apps that are no longer installed.") {
                Button("Scan ~/Library") { model.scanOrphans() }.buttonStyle(.tidyLarge)
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Palette.textTertiary)
                    Text("Nothing is pre-selected. Some apps keep data after removal on purpose, for example to restore settings on reinstall.")
                        .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.orphanGroups) { group in OrphanGroupCard(model: model, group: group) }
                    }
                    .padding(.bottom, 8)
                }
                actionBar
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                BytesText(bytes: model.orphanSelectedBytes).font(.mono(14, weight: .semibold)).foregroundStyle(Palette.text)
                Text("\(model.orphanSelection.count) selected").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            Button("Add to Collector") { model.collectSelectedOrphans() }
                .buttonStyle(.tidySecondary)
                .disabled(model.orphanSelection.isEmpty)
            Button { model.trashSelectedOrphans() } label: { Label("Move to Trash", systemImage: "trash") }
                .buttonStyle(.tidyDanger)
                .disabled(model.orphanSelection.isEmpty)
        }
        .padding(12)
        .panel(radius: 10)
    }
}

private struct OrphanGroupCard: View {
    @Bindable var model: AppsModel
    let group: AppsModel.OrphanGroup

    private var state: AppModel.CheckState {
        let picked = group.items.filter { model.orphanSelection.contains($0.id) }.count
        return picked == 0 ? .off : (picked == group.items.count ? .on : .mixed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CheckToggle(state: state) { model.toggleGroup(group) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(group.bundleID).font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                SafetyBadge(level: .review)
                Text(group.size.formattedBytes).font(.mono(12, weight: .medium)).foregroundStyle(Palette.text)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(Palette.border).frame(height: 1)
            ForEach(group.items) { o in
                HStack(spacing: 9) {
                    CheckToggle(state: .init(model.orphanSelection.contains(o.id))) { model.toggleOrphan(o) }
                    Pill(text: o.category, color: Palette.textSecondary)
                    Text(Finder.abbreviate(o.url.path)).font(.mono(11)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(o.size.formattedBytes).font(.mono(11)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .contentShape(Rectangle())
                .draggable(o.url)
                .contextMenu {
                    Button("Add to Collector") { AppModel.shared.stage(o.url, size: o.size, source: "apps") }
                    Button("Reveal in Finder") { Finder.reveal(o.url) }
                }
            }
            .padding(.vertical, 4)
        }
        .panel(radius: 10)
    }
}
