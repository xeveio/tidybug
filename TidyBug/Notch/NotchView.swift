import SwiftUI
import TidyBugCore

/// The overlay's content: text-only wings around the notch, growing into a
/// compact stats panel on hover. No charts and no rolling digits: values are
/// fixed-width so the wings never jitter.
struct NotchView: View {
    @Bindable var state: NotchState
    @State private var monitor = SystemMonitor.shared
    @AppStorage("notchMetrics") private var metrics = "cpuMem"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var g: NotchGeometry { state.geometry }
    private var size: CGSize { state.expanded ? g.expandedSize : g.collapsedSize }
    private var flare: CGFloat { g.hasNotch ? NotchGeometry.flare : 0 }
    private var radius: CGFloat { state.expanded ? 24 : (g.hasNotch ? 12 : 14) }
    private var shape: NotchShape { NotchShape(flare: flare, radius: radius, attached: g.hasNotch) }
    private var showNet: Bool { metrics == "cpuMemNet" }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Color.black)
                VStack(spacing: 0) {
                    band
                    if state.expanded {
                        ExpandedNotchContent(state: state, monitor: monitor)
                            .padding(.horizontal, 18)
                            .padding(.top, g.hasNotch ? 10 : 6)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, flare)
            }
            .frame(width: size.width + 2 * flare, height: size.height)
            .clipShape(shape)
            .overlay { if !g.hasNotch { shape.stroke(Color.white.opacity(0.1), lineWidth: 1) } }
            .shadow(color: .black.opacity(state.expanded ? 0.55 : 0), radius: 18, y: 10)
            Spacer(minLength: 0)
        }
        .frame(width: g.canvas.width, height: g.canvas.height, alignment: .top)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.36, dampingFraction: 0.8),
                   value: state.expanded)
        .animation(.tidy, value: g)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Collapsed band

    @ViewBuilder
    private var band: some View {
        if g.hasNotch {
            HStack(spacing: 0) {
                cpuWing
                    .padding(.leading, 14)
                    .frame(width: g.wing, alignment: .leading)
                Color.clear.frame(width: g.notchWidth)
                memWing
                    .padding(.trailing, 14)
                    .frame(width: g.wing, alignment: .trailing)
            }
            .frame(height: g.barHeight)
        } else {
            HStack(spacing: 10) {
                cpuWing
                Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 12)
                memWing
            }
            .frame(height: 28)
        }
    }

    private var cpuWing: some View {
        HStack(spacing: 5) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(NotchReadings.cpu(monitor))
                .font(.mono(11.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, alignment: .leading)
            if showNet {
                Text("↓\(compactRate(monitor.netDown))")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 40, alignment: .leading)
            }
        }
        .fixedSize()
        .help("CPU")
    }

    private var memWing: some View {
        HStack(spacing: 5) {
            if showNet {
                Text("↑\(compactRate(monitor.netUp))")
                    .font(.mono(10))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 40, alignment: .trailing)
            }
            Image(systemName: "memorychip")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(NotchReadings.memory(monitor))
                .font(.mono(11.5, weight: .semibold))
                .foregroundStyle(pressureColor(monitor.memory.pressure))
                .frame(width: 34, alignment: .trailing)
        }
        .fixedSize()
        .help("Memory")
    }
}

// MARK: - Readings

/// Formatting with guards: no value until the monitor has a real delta
/// (the first CPU sample after start() has none), clamped to 0–100.
enum NotchReadings {
    @MainActor static func cpu(_ m: SystemMonitor) -> String {
        guard m.cpuHistory.count >= 2, m.cpu.isFinite else { return "–" }
        return percent(m.cpu)
    }

    @MainActor static func cpuFraction(_ m: SystemMonitor) -> Double {
        guard m.cpuHistory.count >= 2, m.cpu.isFinite else { return 0 }
        return clamp(m.cpu)
    }

    @MainActor static func memory(_ m: SystemMonitor) -> String {
        guard m.memory.total > 0, m.memory.usedFraction.isFinite else { return "–" }
        return percent(m.memory.usedFraction)
    }

    @MainActor static func memoryDetail(_ m: SystemMonitor) -> String {
        guard m.memory.total > 0 else { return "–" }
        let gib = 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", Double(m.memory.used) / gib, Double(m.memory.total) / gib)
    }
}

private func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }

private func percent(_ v: Double) -> String { "\(Int((clamp(v) * 100).rounded()))%" }

private func pressureColor(_ p: MemoryPressure) -> Color {
    switch p {
    case .normal: Palette.success
    case .warning: Palette.warning
    case .critical: Palette.danger
    }
}

/// "1.2M", "120K", "0": bytes per second, for tight spaces.
private func compactRate(_ bps: Double) -> String {
    guard bps.isFinite else { return "0" }
    switch bps {
    case ..<1_000: return "0"
    case ..<1_000_000: return String(format: "%.0fK", bps / 1_000)
    case ..<10_000_000: return String(format: "%.1fM", bps / 1_000_000)
    default: return String(format: "%.0fM", bps / 1_000_000)
    }
}

// MARK: - Expanded

private struct ExpandedNotchContent: View {
    @Bindable var state: NotchState
    let monitor: SystemMonitor
    @State private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                MetricRow(symbol: "cpu", label: "CPU",
                          detail: "\(monitor.machine.performanceCores)P + \(monitor.machine.efficiencyCores)E cores",
                          value: NotchReadings.cpu(monitor),
                          fraction: NotchReadings.cpuFraction(monitor), color: Palette.info)
                MetricRow(symbol: "memorychip", label: "Memory",
                          detail: "\(NotchReadings.memoryDetail(monitor)) · \(monitor.memory.pressure.label)",
                          value: NotchReadings.memory(monitor),
                          fraction: clamp(monitor.memory.usedFraction), color: pressureColor(monitor.memory.pressure))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))

            HStack(spacing: 0) {
                stat("Swap", Int64(monitor.memory.swapUsed).formattedBytes)
                stat("GPU", monitor.gpu.map { percent($0) } ?? "–")
                stat("Network ↓ ↑", "\(compactRate(monitor.netDown)) \(compactRate(monitor.netUp))")
                stat("Disk free", model.volume.available.formattedBytes)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                healthChip
                Spacer(minLength: 4)
                NotchButton(title: "Monitor", symbol: "waveform.path.ecg") {
                    NotchController.shared.openApp(pane: .monitor)
                }
                NotchButton(title: cleanTitle, symbol: "sparkles", prominent: state.confirmClean, busy: busy) {
                    NotchController.shared.cleanSafeTapped()
                }
                .disabled(busy)
                NotchButton(title: "Open", symbol: "macwindow") {
                    NotchController.shared.openApp()
                }
            }
        }
    }

    private var busy: Bool { model.scanPhase == .scanning || model.scanPhase == .cleaning }

    private var cleanTitle: String {
        switch model.scanPhase {
        case .scanning: return "Scanning…"
        case .cleaning: return "Cleaning…"
        default:
            if let c = model.celebration, c.freed > 0, !state.confirmClean { return "Freed \(c.freed.formattedBytes)" }
            if state.confirmClean {
                return model.scanPhase == .ready ? "Confirm · \(model.safeTotal.formattedBytes)" : "Click to confirm"
            }
            return "Clean safe items"
        }
    }

    private var healthChip: some View {
        let score = max(0, min(100, monitor.health))
        let color = score >= 80 ? Palette.success : (score >= 60 ? Palette.warning : Palette.danger)
        return HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 2.5)
                Circle().trim(from: 0, to: Double(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            Text("\(score)").font(.mono(11.5, weight: .semibold)).foregroundStyle(.white)
            Text("health").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(Palette.textTertiary)
            Text(value).font(.mono(11, weight: .medium)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Icon · label · thin bar · detail · value.
private struct MetricRow: View {
    let symbol: String
    let label: String
    let detail: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 16)
                Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text)
                Text(detail).font(.mono(10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                Spacer(minLength: 6)
                Text(value)
                    .font(.mono(12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color)
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
            .padding(.leading, 24)
            .animation(.easeOut(duration: 0.4), value: fraction)
        }
    }
}

private struct NotchButton: View {
    let title: String
    let symbol: String
    var prominent = false
    var busy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(prominent ? Palette.accent : Color.white.opacity(hovering ? 0.14 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Shape

/// Flush with the top edge of the screen, with concave flares where it meets
/// the menu bar (so it reads as part of the notch) and rounded bottom corners.
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat
    var attached: Bool

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard attached else {
            return Path(roundedRect: rect, cornerRadius: min(radius, rect.height / 2), style: .continuous)
        }
        let w = rect.width, h = rect.height
        let r = min(radius, (w - 2 * flare) / 2, h - flare)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: flare, y: flare), control: CGPoint(x: flare, y: 0))
        p.addLine(to: CGPoint(x: flare, y: h - r))
        p.addQuadCurve(to: CGPoint(x: flare + r, y: h), control: CGPoint(x: flare, y: h))
        p.addLine(to: CGPoint(x: w - flare - r, y: h))
        p.addQuadCurve(to: CGPoint(x: w - flare, y: h - r), control: CGPoint(x: w - flare, y: h))
        p.addLine(to: CGPoint(x: w - flare, y: flare))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - flare, y: 0))
        p.closeSubpath()
        return p
    }
}
