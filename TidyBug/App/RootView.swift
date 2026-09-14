import SwiftUI
import TidyBugCore

/// Title-bar tabs, the current page, the Collector strip, a result toast, the
/// feature tour and a ⌘K command palette. First launch shows onboarding instead.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("didTour") private var didTour = false
    @State private var showPalette = false

    var body: some View {
        @Bindable var model = model
        ZStack {
            AmbientBackground()
            if didOnboard {
                VStack(spacing: 0) {
                    TopBar(showPalette: $showPalette)
                    page.frame(maxWidth: .infinity, maxHeight: .infinity)
                    CollectorStrip()
                }
                .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.gentle) { didOnboard = true }
                    model.refreshVolume()
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let summary = model.celebration {
                ResultToast(summary: summary) {
                    withAnimation(.tidy) { model.celebration = nil }
                }
                .padding(.bottom, 74)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .onTapGesture { withAnimation(.tidy) { showPalette = false } }
                    CommandPalette(isPresented: $showPalette)
                        .padding(.top, 96)
                        .transition(.scale(scale: 0.97, anchor: .top).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if model.showTour && didOnboard {
                FeatureTour {
                    withAnimation(.tidy) { model.showTour = false }
                    didTour = true
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background {
            Button("") { withAnimation(.tidy) { showPalette.toggle() } }
                .keyboardShortcut("k")
                .hidden()
        }
        .task(id: didOnboard) {
            // First run: the tour follows onboarding once.
            guard didOnboard, !didTour else { return }
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.tidy) { model.showTour = true }
        }
        .animation(.tidy, value: showPalette)
        .animation(.tidy, value: model.showTour)
        .animation(.bouncy, value: model.celebration)
        .sheet(item: $model.pendingConfirmation) { request in
            ConfirmSheet(request: request).preferredColorScheme(.dark)
        }
        .preferredColorScheme(.dark)
    }

    private var page: some View {
        Group {
            switch model.pane ?? .home {
            case .home: HomeView()
            case .smartClean: SmartCleanView()
            case .diskMap: DiskMapView()
            case .purge: PurgeView()
            case .duplicates: DuplicatesView()
            case .largeFiles: LargeFilesView()
            case .apps: AppsView()
            case .optimize: OptimizeView()
            case .monitor: MonitorView()
            case .history: HistoryView()
            }
        }
        .id(model.pane)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .animation(.tidy, value: model.pane)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Binding var showPalette: Bool
    @Namespace private var ns

    private var markState: MascotMood {
        if model.scanPhase == .cleaning { return .sweeping }
        if model.scanPhase == .scanning || model.mapScanning || model.purgeScanning || model.largeScanning { return .scanning }
        return .idle
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 70) // traffic lights
            HStack(spacing: 7) {
                LogoMark(state: markState, size: 16)
                Text("TidyBug").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            }
            .padding(.trailing, 20)

            // Nine tabs: full labels when there's room, icons (with tooltips) when narrow.
            ViewThatFits(in: .horizontal) {
                tabs(compact: false)
                tabs(compact: true)
            }

            Spacer(minLength: 16)

            Button { withAnimation(.tidy) { showPalette = true } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium))
                    Text("Search or run a command").font(.system(size: 12))
                    Spacer(minLength: 12)
                    KeyHint(keys: "⌘K")
                }
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(width: 250)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)

            DiskChip().padding(.trailing, 6)

            Button { withAnimation(.tidy) { model.pane = .history } } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.tidyQuiet)
            .help("Activity")
            Button { withAnimation(.tidy) { model.showTour = true } } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.tidyQuiet)
            .help("How to use TidyBug")
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.tidyQuiet)
                .help("Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(WindowDragArea())
        .background(Palette.bg.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
    }

    private func tabs(compact: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Pane.dock) { pane in
                TabButton(pane: pane, selected: (model.pane ?? .home) == pane, busy: busy(pane), ns: ns,
                          compact: compact) {
                    withAnimation(.tidy) { model.pane = pane }
                }
            }
        }
        .fixedSize()
    }

    private func busy(_ pane: Pane) -> Bool {
        switch pane {
        case .smartClean: model.scanPhase == .scanning || model.scanPhase == .cleaning
        case .diskMap: model.mapScanning
        case .purge: model.purgeScanning
        case .largeFiles: model.largeScanning
        case .duplicates: DuplicatesModel.shared.isScanning
        default: false
        }
    }
}

struct TabButton: View {
    let pane: Pane
    let selected: Bool
    let busy: Bool
    let ns: Namespace.ID
    var compact = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if compact {
                    Image(systemName: pane.symbol).font(.system(size: 12, weight: .medium))
                } else {
                    Text(pane.title)
                }
                if busy {
                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                        // Static on purpose: a looping phaseAnimator redraws the top bar
                        // at display refresh rate for the whole duration of every scan.
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(selected ? Palette.text : (hovering ? Palette.text.opacity(0.85) : Palette.textSecondary))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.border))
                        .matchedGeometryEffect(id: "tab", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Makes empty top-bar space drag the window (title bar is hidden).
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}

struct DiskChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 7) {
            SizeRing(fraction: model.volume.usedFraction, lineWidth: 2.2).frame(width: 12, height: 12)
            BytesText(bytes: model.volume.available)
                .font(.mono(11.5, weight: .medium))
                .foregroundStyle(Palette.text)
            Text("free").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
    }
}

/// Compact brand lockup used by onboarding and elsewhere.
struct Wordmark: View {
    var body: some View {
        HStack(spacing: 7) {
            LogoMark(size: 16)
            Text("TidyBug").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
        }
    }
}

// MARK: - Command palette

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let group: String
    let symbol: String
    var shortcut: String?
    let run: @MainActor () -> Void
}

struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    private var commands: [PaletteCommand] {
        var list: [PaletteCommand] = [
            PaletteCommand(id: "scan", title: "Scan for reclaimable space", group: "Actions", symbol: "arrow.clockwise", shortcut: "⌘R") {
                model.pane = .smartClean; model.startSmartScan()
            },
            PaletteCommand(id: "clean-safe", title: "Clean safe items", group: "Actions", symbol: "sparkles") {
                model.pane = .smartClean
                Task {
                    await model.scanIfNeeded()
                    model.selectSafeOnly()
                    model.requestSmartClean()
                }
            },
            PaletteCommand(id: "map-home", title: "Map home folder", group: "Actions", symbol: "chart.pie", shortcut: "⇧⌘R") {
                model.pane = .diskMap; model.scanDiskMap(path: NSHomeDirectory())
            },
            PaletteCommand(id: "map-folder", title: "Map a folder…", group: "Actions", symbol: "folder") {
                if let p = Finder.chooseFolder(startingAt: NSHomeDirectory()) { model.pane = .diskMap; model.scanDiskMap(path: p) }
            },
            PaletteCommand(id: "projects", title: "Scan projects for build artifacts", group: "Actions", symbol: "hammer") {
                model.pane = .purge; model.scanProjects()
            },
            PaletteCommand(id: "dupes", title: "Find duplicate files", group: "Actions", symbol: "square.on.square") {
                model.pane = .duplicates; DuplicatesModel.shared.scan()
            },
            PaletteCommand(id: "large", title: "Find large files", group: "Actions", symbol: "doc.text.magnifyingglass") {
                model.pane = .largeFiles; model.scanLargeFiles()
            },
        ]
        if !model.staged.isEmpty {
            list += [
                PaletteCommand(id: "collector-delete", title: "Delete all items in the Collector (\(model.stagedTotal.formattedBytes))",
                               group: "Collector", symbol: "trash", shortcut: "⇧⌘⌫") { model.requestDeleteStaged() },
                PaletteCommand(id: "collector-clear", title: "Clear the Collector", group: "Collector", symbol: "xmark.circle") {
                    model.clearStaged()
                },
            ]
        }
        for (i, pane) in (Pane.dock + [.history]).enumerated() {
            list.append(PaletteCommand(id: "go-\(pane.rawValue)", title: "Go to \(pane.title)", group: "Navigate",
                                       symbol: pane.symbol, shortcut: i < 9 ? "⌘\(i + 1)" : "⌘Y") { model.pane = pane })
        }
        list += [
            PaletteCommand(id: "tour", title: "Show the TidyBug tour", group: "Help", symbol: "questionmark.circle") {
                model.showTour = true
            },
            PaletteCommand(id: "updates", title: "Check for updates", group: "Help", symbol: "arrow.down.circle") {
                Updater.shared.checkForUpdates()
            },
            PaletteCommand(id: "log", title: "Reveal operations log in Finder", group: "Help", symbol: "doc.text") {
                Finder.reveal(OperationLog.shared.url)
            },
            PaletteCommand(id: "fda", title: "Open Full Disk Access settings", group: "Help", symbol: "lock.shield") {
                model.openFullDiskAccessSettings()
            },
            PaletteCommand(id: "settings", title: "Settings…", group: "Help", symbol: "gearshape", shortcut: "⌘,") {
                openSettings()
            },
        ]
        return list
    }

    private var filtered: [PaletteCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return commands }
        return commands.filter { cmd in
            let hay = cmd.title.lowercased()
            // Subsequence match: "cln sf" finds "Clean safe items".
            var it = hay.makeIterator()
            return q.replacingOccurrences(of: " ", with: "").allSatisfy { ch in
                while let c = it.next() { if c == ch { return true } }
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.textTertiary)
                TextField("Search or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .onKeyPress(.downArrow) { index = min(index + 1, max(filtered.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.return) { run(filtered[safe: index]); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
                KeyHint(keys: "esc")
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, cmd in
                            if i == 0 || filtered[i - 1].group != cmd.group {
                                Text(cmd.group)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Palette.textTertiary)
                                    .padding(.horizontal, 10).padding(.top, i == 0 ? 4 : 10).padding(.bottom, 4)
                            }
                            row(cmd, selected: i == index)
                                .id(cmd.id)
                                .onTapGesture { run(cmd) }
                                .onHover { if $0 { index = i } }
                        }
                        if filtered.isEmpty {
                            Text("No matching commands").font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                                .frame(maxWidth: .infinity).padding(24)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: index) { _, i in
                    if let id = filtered[safe: i]?.id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
                }
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 14) {
                LogoMark(size: 12)
                Spacer()
                hint("↑↓", "navigate")
                hint("↵", "run")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 600)
        .panel(radius: 14, lifted: true)
        .onChange(of: query) { index = 0 }
        .onAppear { focused = true }
    }

    private func row(_ cmd: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: cmd.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
                .frame(width: 20)
            Text(cmd.title).font(.system(size: 13)).foregroundStyle(Palette.text)
            Spacer()
            if let s = cmd.shortcut { KeyHint(keys: s) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.white.opacity(0.07) : .clear))
        .contentShape(Rectangle())
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyHint(keys: key)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
        }
    }

    private func run(_ cmd: PaletteCommand?) {
        guard let cmd else { return }
        isPresented = false
        cmd.run()
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
