import SwiftUI

/// Compact live CPU / memory / health readout for the menu bar popover.
/// Samples only while visible (SystemMonitor is reference-counted).
struct MenuBarVitals: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var monitor = SystemMonitor.shared

    var body: some View {
        Button {
            model.pane = .monitor
            openWindow(id: "main")
            NSApp.activate()
        } label: {
            HStack(spacing: 14) {
                gauge("CPU", monitor.cpu, color: Palette.info)
                gauge("Memory", monitor.memory.usedFraction, color: pressureColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Health").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    Text("\(monitor.health)")
                        .font(.mono(13, weight: .semibold))
                        .foregroundStyle(monitor.health >= 80 ? Palette.success : (monitor.health >= 60 ? Palette.warning : Palette.danger))
                        .contentTransition(.numericText(value: Double(monitor.health)))
                }
                .frame(width: 44, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Monitor")
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .animation(.tidy, value: monitor.health)
    }

    private var pressureColor: Color {
        switch monitor.memory.pressure {
        case .normal: Palette.violet
        default: Palette.warning
        }
    }

    private func gauge(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText(value: value * 100))
            }
            GardenProgress(value: value, total: 1, color: color)
        }
        .frame(maxWidth: .infinity)
    }
}
