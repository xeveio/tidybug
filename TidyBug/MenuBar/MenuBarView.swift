import SwiftUI
import TidyBugCore

/// Menu bar popover: volume, scan status, and a one-click clean of safe items.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var confirming = false

    private var safeResults: [RuleResult] {
        model.visibleResults.filter { $0.rule.safety == .safe && $0.total > 0 }.sorted { $0.total > $1.total }
    }

    private var markState: MascotMood {
        switch model.scanPhase {
        case .scanning: .scanning
        case .cleaning: .sweeping
        default: .idle
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                LogoMark(state: markState, size: 15)
                Text("TidyBug").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text("\(Int(model.volume.usedFraction * 100))% used").font(.mono(11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(14)

            divider

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    BytesText(bytes: model.volume.available).font(.number(22)).foregroundStyle(Palette.text)
                    Text("free of \(model.volume.total.formattedBytes)").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                }
                GardenProgress(value: model.volume.usedFraction, total: 1, color: Brand.pressure(model.volume.usedFraction))
            }
            .padding(14)

            divider

            MenuBarVitals()
                .padding(.horizontal, 14).padding(.vertical, 10)

            divider

            VStack(alignment: .leading, spacing: 8) { status }
                .padding(14)

            divider

            HStack(spacing: 4) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: { Label("Open TidyBug", systemImage: "macwindow") }
                    .buttonStyle(.tidyQuiet)
                Spacer()
                Button { Updater.shared.checkForUpdates() } label: { Image(systemName: "arrow.down.circle") }
                    .buttonStyle(.tidyQuiet)
                    .help("Check for Updates…")
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.tidyQuiet)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.tidyQuiet)
                    .help("Quit TidyBug")
            }
            .padding(8)
        }
        .frame(width: 320)
        .background(Palette.surface)
        .preferredColorScheme(.dark)
        .animation(.tidy, value: model.scanPhase)
        .animation(.tidy, value: confirming)
        .onAppear { model.refreshVolume() }
    }

    private var divider: some View { Rectangle().fill(Palette.border).frame(height: 1) }

    @ViewBuilder
    private var status: some View {
        switch model.scanPhase {
        case .idle:
            Button { model.startSmartScan() } label: {
                Label("Scan for reclaimable space", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidy)
        case .scanning:
            HStack {
                Text("Scanning").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text)
                Spacer()
                Text("\(model.results.count)/\(model.ruleOrder.count)").font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
            }
            GardenProgress(value: Double(model.results.count), total: Double(model.ruleOrder.count))
        case .cleaning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Cleaning…").font(.system(size: 12.5)).foregroundStyle(Palette.text)
            }
        case .ready:
            HStack(alignment: .firstTextBaseline) {
                Text("Safe to clean").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                Spacer()
                BytesText(bytes: model.safeTotal).font(.mono(12.5, weight: .semibold)).foregroundStyle(Palette.success)
            }
            ForEach(safeResults.prefix(5)) { r in
                HStack(spacing: 8) {
                    Image(systemName: r.rule.symbol).font(.system(size: 11)).foregroundStyle(Brand.tint(r.rule.hue)).frame(width: 16)
                    Text(r.rule.title).font(.system(size: 12)).foregroundStyle(Palette.text)
                    Spacer()
                    Text(r.total.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                }
            }
            if let c = model.celebration, c.freed > 0 {
                Label("Reclaimed \(c.freed.formattedBytes)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.success)
            }
            HStack(spacing: 6) {
                if confirming {
                    Button("Cancel") { confirming = false }.buttonStyle(.tidySecondary)
                    Button {
                        confirming = false
                        Task { await model.cleanSafeJunk() }
                    } label: {
                        Text("Confirm · \(model.safeTotal.formattedBytes)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidy)
                } else {
                    Button { confirming = true } label: {
                        Text("Clean safe items").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidy)
                    .disabled(model.safeTotal == 0)
                    Button { model.startSmartScan() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.tidySecondary)
                        .help("Rescan")
                }
            }
            .padding(.top, 4)
        }
    }
}
