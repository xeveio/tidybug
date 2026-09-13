import AppKit
import SwiftUI
import TidyBugCore
import UserNotifications

// MARK: - Shared pieces

struct StepHeader: View {
    let step: OnboardingStep
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: "%02d  ·  %@", step.rawValue + 1, step.title.uppercased()))
                .font(.mono(11, weight: .medium))
                .kerning(0.8)
                .foregroundStyle(Palette.accent)
            Text(title)
                .font(.display(30, weight: .semibold))
                .kerning(-0.6)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fades rows in with a short stagger on appear.
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25).delay(Double(index) * 0.045)) { shown = true }
            }
    }
}

extension View {
    func staggerIn(_ index: Int) -> some View { modifier(StaggerIn(index: index)) }
}

/// A row in a bordered list panel.
struct SetupRow<Trailing: View>: View {
    let symbol: String
    var tint: Color = Palette.textSecondary
    let title: String
    let detail: String
    var mono: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.raised)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let mono {
                    Text(mono)
                        .font(.mono(11))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

extension SetupRow where Trailing == EmptyView {
    init(symbol: String, tint: Color = Palette.textSecondary, title: String, detail: String, mono: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail, mono: mono) { EmptyView() }
    }
}

/// Stacks rows inside one panel with hairline separators.
struct RowList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { i, sub in
                    if i > 0 { Rectangle().fill(Palette.border).frame(height: 1) }
                    sub
                }
            }
        }
        .panel()
    }
}

// MARK: - 1 Welcome

struct MeetStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepHeader(step: .meet,
                       title: "Reclaim disk space without guesswork.",
                       subtitle: "TidyBug finds regenerable caches, build artifacts, duplicates and large files, shows exactly what each item is and where it lives, and removes only what you approve.")
            RowList {
                SetupRow(symbol: "sparkles", tint: Palette.success, title: "Clean",
                         detail: "App caches, logs, Xcode data and package-manager downloads.",
                         mono: "~/Library/Caches  ~/.npm/_cacache  ~/Library/Developer/Xcode/DerivedData")
                    .staggerIn(0)
                SetupRow(symbol: "hammer", tint: Palette.warning, title: "Projects",
                         detail: "Build artifacts in projects you haven't touched in weeks, only when a lockfile can restore them.",
                         mono: "node_modules  .build  target  Pods  .venv  .next")
                    .staggerIn(1)
                SetupRow(symbol: "square.on.square", tint: Palette.info, title: "Duplicates",
                         detail: "Byte-identical files and near-identical photos across your folders.",
                         mono: "size → partial hash → SHA-256  ·  Vision feature prints")
                    .staggerIn(2)
                SetupRow(symbol: "chart.pie", tint: Palette.violet, title: "Space",
                         detail: "An interactive map of every folder, hardlink-aware so sizes match what is actually freed.",
                         mono: "fts(3) + lstat  ·  dedup by (dev, inode)")
                    .staggerIn(3)
            }
        }
    }
}

// MARK: - 2 Safety model

struct PromiseStep: View {
    private let protected = ["~/Documents", "~/Desktop", "~/Library/Mobile Documents", "*.photoslibrary",
                             ".git/", "~/.ssh", "~/.secrets", "*.xcarchive", "*.ipa", "Keychains"]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepHeader(step: .promise,
                       title: "Nothing is removed without your approval.",
                       subtitle: "Every action goes through the same guard: preview, confirmation, a path check, and a log entry.")
            RowList {
                SetupRow(symbol: "eye", tint: Palette.success, title: "Scans are read-only",
                         detail: "Sizing walks the file system with fts(3) and lstat. Nothing is opened for writing.")
                    .staggerIn(0)
                SetupRow(symbol: "trash", tint: Palette.success, title: "Trash by default",
                         detail: "Items move to the Trash and can be restored. Permanent deletion is opt-in and limited to regenerable caches.")
                    .staggerIn(1)
                VStack(alignment: .leading, spacing: 0) {
                    SetupRow(symbol: "lock", tint: Palette.success, title: "Protected paths",
                             detail: "These are never removed, even if selected. Symlinks are resolved before the check.")
                    FlowChips(items: protected).padding(.leading, 56).padding(.trailing, 14).padding(.bottom, 12)
                }
                .staggerIn(2)
                SetupRow(symbol: "doc.text", tint: Palette.success, title: "Every operation is logged",
                         detail: "Append-only JSON Lines, viewable under Activity.",
                         mono: "~/Library/Logs/TidyBug/operations.jsonl")
                    .staggerIn(3)
            }
        }
    }
}

/// Wrapping row of mono path chips.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.mono(11))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Palette.raised)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border)))
            }
        }
    }
}

struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - 3 Full Disk Access

struct AccessStep: View {
    let state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(step: .access,
                       title: "Grant Full Disk Access.",
                       subtitle: "macOS restricts Mail, Safari, the Trash and several app containers. Without access those locations are skipped and totals will be incomplete. TidyBug never uploads or reads file contents beyond hashing duplicates.")

            statusRow

            if !state.fullDiskAccess {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        instruction(1, "Open ", "System Settings → Privacy & Security → Full Disk Access")
                        instruction(2, "Drag the app tile into the list, or click ", "+")
                        instruction(3, "Enable the toggle. If macOS asks to quit, setup resumes here.", nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    appTile
                }
                .padding(16)
                .panel()
                .transition(.opacity)
            }
        }
        .animation(.tidy, value: state.fullDiskAccess)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                if state.fullDiskAccess {
                    Circle().fill(Palette.success)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().fill(Palette.warning.opacity(0.18))
                    Circle().fill(Palette.warning).frame(width: 7, height: 7)
                        .phaseAnimator([0.35, 1.0]) { dot, phase in dot.opacity(phase) }
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.fullDiskAccess ? "Full Disk Access granted" : "Waiting for permission")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.opacity)
                Text(state.fullDiskAccess ? "All locations can be scanned." : "Status updates automatically once the toggle is enabled.")
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if !state.fullDiskAccess {
                Button { AppModel.shared.openFullDiskAccessSettings() } label: {
                    Label("Open System Settings", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.tidy)
            }
        }
        .padding(14)
        .panel(tint: state.fullDiskAccess ? Palette.success : nil)
    }

    private func instruction(_ n: Int, _ text: String, _ mono: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.mono(11, weight: .semibold)).foregroundStyle(Palette.textTertiary).frame(width: 12)
            (Text(text).foregroundStyle(Palette.textSecondary)
             + Text(mono ?? "").font(.mono(12)).foregroundStyle(Palette.text))
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appTile: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 48, height: 48)
            Text("TidyBug.app").font(.mono(11)).foregroundStyle(Palette.text)
            Text("Drag me").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
        }
        .padding(12)
        .frame(width: 120)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.raised)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))))
        .draggable(Bundle.main.bundleURL)
        .help("Drag into the Full Disk Access list")
    }
}

// MARK: - 4 Notifications

struct NotifyStep: View {
    let state: OnboardingState
    @AppStorage("lowSpaceAlerts") private var alerts = true
    @AppStorage("lowSpaceThresholdGB") private var threshold = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(step: .notify,
                       title: "Low-space alerts.",
                       subtitle: "Get a notification when free space drops below a threshold, with a one-click action to clean safe items. At most one alert per day.")

            RowList {
                SetupRow(symbol: "bell", tint: Palette.info, title: "Enable alerts",
                         detail: statusText) {
                    Toggle("", isOn: Binding(get: { alerts && !denied }, set: { on in
                        alerts = on
                        if on && state.notificationStatus == .notDetermined {
                            Task { await state.requestNotifications() }
                        }
                    }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(denied)
                }
                SetupRow(symbol: "gauge.with.dots.needle.33percent", tint: Palette.info, title: "Threshold",
                         detail: "Alert when free space falls below this amount.") {
                    Picker("", selection: $threshold) {
                        ForEach([10, 20, 50, 100], id: \.self) { Text("\($0) GB").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!alerts || denied)
                }
            }

            if denied {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warning)
                    Text("Notifications are disabled for TidyBug in System Settings.")
                        .font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Open Notification Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .buttonStyle(.tidySecondary)
                }
                .padding(12)
                .panel(tint: Palette.warning)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.textTertiary)
                notificationPreview
            }
        }
        .task { await state.refreshNotificationStatus() }
    }

    private var denied: Bool { state.notificationStatus == .denied }

    private var statusText: String {
        switch state.notificationStatus {
        case .authorized, .provisional, .ephemeral: "Permission granted."
        case .denied: "Blocked in System Settings."
        default: "macOS will ask for permission when enabled."
        }
    }

    private var notificationPreview: some View {
        HStack(alignment: .top, spacing: 10) {
            LogoMark(size: 22).padding(4)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.bg))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("TidyBug").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Text("now").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                }
                Text("Free space is below \(threshold) GB").font(.system(size: 12)).foregroundStyle(Palette.text)
                Text("Clean safe items to reclaim space.").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.raised)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border)))
        .opacity(alerts && !denied ? 1 : 0.45)
        .animation(.tidy, value: alerts)
    }
}

// MARK: - 5 Preferences

struct PrefsStep: View {
    @AppStorage("showFreeInMenuBar") private var showFree = true
    @State private var launchAtLogin = AppModel.shared.launchAtLogin
    @State private var roots = AppModel.shared.purgeRoots

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(step: .prefs,
                       title: "Preferences.",
                       subtitle: "TidyBug lives in the menu bar for quick scans. Project folders are where build artifacts are searched for.")

            RowList {
                SetupRow(symbol: "menubar.rectangle", tint: Palette.violet, title: "Show free space in the menu bar",
                         detail: "Displays the remaining space next to the icon.") {
                    Toggle("", isOn: $showFree).toggleStyle(.switch).labelsHidden()
                }
                SetupRow(symbol: "power", tint: Palette.violet, title: "Open at login",
                         detail: "Keeps the menu bar item and low-space alerts running.") {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { _, on in AppModel.shared.launchAtLogin = on }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeading(title: "Project folders", subtitle: "\(roots.count) configured")
                    Spacer()
                    Button {
                        if let p = Finder.chooseFolder(startingAt: NSHomeDirectory()), !roots.contains(p) { save(roots + [p]) }
                    } label: { Label("Add Folder", systemImage: "plus") }
                        .buttonStyle(.tidySecondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(roots.enumerated()), id: \.element) { i, root in
                        if i > 0 { Rectangle().fill(Palette.border).frame(height: 1) }
                        HStack(spacing: 10) {
                            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                            Text(Finder.abbreviate(root)).font(.mono(12)).foregroundStyle(Palette.text)
                            Spacer()
                            Button { save(roots.filter { $0 != root }) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.tidyQuiet)
                                .help("Remove")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .transition(.opacity)
                    }
                    if roots.isEmpty {
                        Text("No folders. Projects will not be scanned.")
                            .font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
                            .padding(14)
                    }
                }
                .panel()
            }
        }
    }

    private func save(_ new: [String]) {
        withAnimation(.tidy) { roots = new }
        AppModel.shared.purgeRoots = new
    }
}

// MARK: - 6 Ready

struct ReadyStep: View {
    let state: OnboardingState
    let start: () -> Void
    @AppStorage("showFreeInMenuBar") private var showFree = true
    @AppStorage("lowSpaceAlerts") private var alerts = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(step: .ready,
                       title: "Setup complete.",
                       subtitle: "The first scan checks \(AppModel.shared.ruleOrder.count) known locations and usually takes under a minute. It is read-only; you review everything before anything is removed. A short tour of the main features follows.")

            RowList {
                check("Full Disk Access", state.fullDiskAccess ? "Granted" : "Not granted — some locations will be skipped",
                      ok: state.fullDiskAccess).staggerIn(0)
                check("Low-space alerts", alerts && state.notificationsAllowed ? "On" : "Off", ok: alerts && state.notificationsAllowed)
                    .staggerIn(1)
                check("Menu bar", showFree ? "Showing free space" : "Icon only", ok: true).staggerIn(2)
                check("Project folders", "\(AppModel.shared.purgeRoots.count) configured",
                      ok: !AppModel.shared.purgeRoots.isEmpty).staggerIn(3)
            }

            Button(action: start) {
                HStack(spacing: 10) {
                    Label("Start first scan", systemImage: "arrow.clockwise")
                    Text("↵").font(.system(size: 11, weight: .medium)).opacity(0.7)
                }
            }
            .buttonStyle(.tidyLarge)
        }
    }

    private func check(_ title: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(ok ? Palette.success : Palette.warning)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Spacer()
            Text(value).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
