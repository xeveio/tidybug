import AppKit
import Charts
import SwiftUI
import TidyBugCore

/// Live system status: health score, CPU, memory, GPU, disk, network, power, processes.
struct MonitorView: View {
    @State private var monitor = SystemMonitor.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MonitorHeader(m: monitor)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)], spacing: 14) {
                    CPUPanel(m: monitor)
                    MemoryPanel(m: monitor)
                    GPUPanel(m: monitor)
                    DiskPanel(m: monitor)
                    NetworkPanel(m: monitor)
                    PowerPanel(m: monitor)
                }
                ProcessesPanel(m: monitor)
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 28)
            .frame(maxWidth: 1260)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

// MARK: - Header

private struct MonitorHeader: View {
    let m: SystemMonitor
    @State private var showBreakdown = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HealthRing(score: m.health)
                .frame(width: 58, height: 58)
                .onTapGesture { showBreakdown.toggle() }
                .help("Health score — click for the breakdown")
                .popover(isPresented: $showBreakdown, arrowEdge: .bottom) {
                    HealthBreakdown(score: m.health, factors: m.healthFactors)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Monitor").pageTitle()
                Text(m.machine.subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle().fill(m.isRunning ? Palette.success : Palette.textTertiary).frame(width: 6, height: 6)
                        .phaseAnimator([0.4, 1.0]) { dot, phase in dot.opacity(phase) }
                    Text("Live · 1 s").font(.mono(11)).foregroundStyle(Palette.textSecondary)
                }
                Divider().frame(height: 14)
                HStack(spacing: 5) {
                    Text("Uptime").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                    Text(formatUptime(m.uptime)).font(.mono(11.5)).foregroundStyle(Palette.text)
                }
                Divider().frame(height: 14)
                HStack(spacing: 5) {
                    Text("Thermal").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                    Text(m.thermal.label).font(.mono(11.5)).foregroundStyle(thermalColor(m.thermal))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .panel(radius: 8)
        }
    }
}

private struct HealthRing: View {
    let score: Int
    var color: Color { score >= 80 ? Palette.success : (score >= 60 ? Palette.warning : Palette.danger) }

    var body: some View {
        ZStack {
            Circle().stroke(Palette.border, lineWidth: 5)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: 6)
            VStack(spacing: -2) {
                Text("\(score)").font(.number(18)).foregroundStyle(Palette.text)
                    .contentTransition(.numericText(value: Double(score)))
                Text("health").font(.system(size: 8.5, weight: .medium)).foregroundStyle(Palette.textTertiary)
            }
        }
        .animation(.tidy, value: score)
    }
}

private struct HealthBreakdown: View {
    let score: Int
    let factors: [HealthFactor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Health score").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(score) / 100").font(.mono(12, weight: .semibold))
            }
            Rectangle().fill(Palette.border).frame(height: 1)
            ForEach(factors) { f in
                HStack(spacing: 10) {
                    Circle().fill(f.penalty == 0 ? Palette.success : (f.penalty < 10 ? Palette.warning : Palette.danger))
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.label).font(.system(size: 12, weight: .medium))
                        Text(f.detail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 16)
                    Text(f.penalty == 0 ? "0" : "−\(f.penalty)").font(.mono(11.5))
                        .foregroundStyle(f.penalty == 0 ? Palette.textTertiary : Palette.warning)
                }
            }
            Text("Starts at 100; each factor subtracts points.").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
        }
        .padding(14)
        .frame(width: 300)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Panel chrome

private struct MetricPanel<Content: View>: View {
    let title: String
    let symbol: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textTertiary)
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                Spacer()
                if let trailing {
                    Text(trailing).font(.mono(11)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .panel()
    }
}

private struct BigPercent: View {
    let value: Double
    var body: some View {
        Text(String(format: "%.0f%%", value * 100))
            .font(.number(28))
            .foregroundStyle(Palette.text)
            .contentTransition(.numericText(value: value * 100))
            .animation(.tidy, value: Int(value * 100))
    }
}

private struct StatLine: View {
    let label: String
    let value: String
    var color: Color = Palette.text
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
            Spacer()
            Text(value).font(.mono(11.5)).foregroundStyle(color)
        }
    }
}

/// Scrolling area sparkline; optional second series drawn as a line.
private struct Sparkline: View {
    let points: [SeriesPoint]
    var color: Color
    var maxValue: Double?
    var secondary: [SeriesPoint]?
    var secondaryColor: Color = Palette.violet

    private var xDomain: ClosedRange<Int> {
        // Anchor the newest sample at the right edge; history grows leftward.
        let last = points.last?.id ?? 0
        return (last - SystemMonitor.historyLength + 1)...last
    }

    private var yMax: Double {
        if let maxValue { return maxValue }
        let peak = max(points.map(\.value).max() ?? 0, secondary?.map(\.value).max() ?? 0)
        return max(peak * 1.2, 1024)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("t", p.id), y: .value("v", min(p.value, yMax)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.32), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", p.id), y: .value("v", min(p.value, yMax)), series: .value("s", "a"))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.monotone)
            }
            if let secondary {
                ForEach(secondary) { p in
                    LineMark(x: .value("t", p.id), y: .value("v", min(p.value, yMax)), series: .value("s", "b"))
                        .foregroundStyle(secondaryColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(Palette.border)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yMax)
        .chartLegend(.hidden)
        // No per-tick animation: animating 7 charts for 0.9 s every second kept
        // them redrawing ~90% of the time (the Monitor tab's main CPU cost).
        .transaction { $0.animation = nil }
    }
}

private func thermalColor(_ t: ProcessInfo.ThermalState) -> Color {
    switch t {
    case .nominal: Palette.success
    case .fair: Palette.warning
    default: Palette.danger
    }
}

// MARK: - Panels

private struct CPUPanel: View {
    let m: SystemMonitor

    var body: some View {
        MetricPanel(title: "CPU", symbol: "cpu", trailing: "\(m.machine.performanceCores)P + \(m.machine.efficiencyCores)E cores") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BigPercent(value: m.cpu)
                Text("total").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text(m.load.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    .font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                    .help("Load average: 1, 5 and 15 minutes")
            }
            Sparkline(points: m.cpuHistory, color: Palette.info, maxValue: 1)
                .frame(height: 58)
            CoreBars(cores: m.cores, efficiency: m.machine.efficiencyCores)
        }
    }
}

/// Per-core utilisation. On Apple silicon the efficiency cores are numbered first.
private struct CoreBars: View {
    let cores: [Double]
    let efficiency: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(cores.indices, id: \.self) { i in
                    let isE = i < efficiency
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05))
                        RoundedRectangle(cornerRadius: 2).fill((isE ? Palette.teal : Palette.info).opacity(0.85))
                            .frame(height: max(1.5, 30 * min(1, cores[i])))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .padding(.leading, i == efficiency && efficiency > 0 ? 6 : 0) // gap between E and P groups
                    .help(String(format: "%@ core %d: %.0f%%", isE ? "Efficiency" : "Performance", i, cores[i] * 100))
                }
            }
            HStack(spacing: 12) {
                legend(Palette.teal, "Efficiency")
                legend(Palette.info, "Performance")
            }
        }
        .animation(.easeOut(duration: 0.25), value: cores)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct MemoryPanel: View {
    let m: SystemMonitor

    var body: some View {
        let mem = m.memory
        MetricPanel(title: "Memory", symbol: "memorychip", trailing: "\(m.machine.memoryGB) GB total") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BytesText(bytes: Int64(mem.used)).font(.number(28)).foregroundStyle(Palette.text)
                Text("used").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Pill(text: mem.pressure.label,
                     color: mem.pressure == .normal ? Palette.success : (mem.pressure == .warning ? Palette.warning : Palette.danger),
                     symbol: "gauge.with.dots.needle.33percent")
                    .help("Memory pressure")
            }
            StackedBar(segments: [
                (Double(mem.app), Palette.info),
                (Double(mem.wired), Palette.violet),
                (Double(mem.compressed), Palette.warning),
                (Double(mem.cached), Palette.teal.opacity(0.55)),
            ], total: Double(max(mem.total, 1)))
            .frame(height: 10)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 6) {
                legend(Palette.info, "App", mem.app)
                legend(Palette.violet, "Wired", mem.wired)
                legend(Palette.warning, "Compressed", mem.compressed)
                legend(Palette.teal.opacity(0.55), "Cached files", mem.cached)
            }
            StatLine(label: "Swap", value: "\(Int64(mem.swapUsed).formattedBytes) of \(Int64(mem.swapTotal).formattedBytes)",
                     color: mem.swapUsed > 1_073_741_824 ? Palette.warning : Palette.text)
        }
    }

    private func legend(_ color: Color, _ label: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text(Int64(bytes).formattedBytes).font(.mono(11)).foregroundStyle(Palette.text)
                .contentTransition(.numericText())
        }
    }
}

private struct StackedBar: View {
    let segments: [(Double, Color)]
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<segments.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segments[i].1)
                        .frame(width: max(0, geo.size.width * segments[i].0 / total - 2))
                }
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.05))
            }
        }
        .animation(.easeOut(duration: 0.25), value: segments.map(\.0))
    }
}

private struct GPUPanel: View {
    let m: SystemMonitor

    var body: some View {
        MetricPanel(title: "GPU", symbol: "square.stack.3d.up", trailing: m.machine.chip) {
            if let gpu = m.gpu {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BigPercent(value: gpu)
                    Text("utilisation").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    let peak = m.gpuHistory.map(\.value).max() ?? 0
                    Text(String(format: "peak %.0f%%", peak * 100)).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                }
                Sparkline(points: m.gpuHistory, color: Palette.violet, maxValue: 1)
                    .frame(height: 88)
            } else {
                Text("GPU statistics are not available on this Mac.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

private struct DiskPanel: View {
    let m: SystemMonitor

    var body: some View {
        let vol = VolumeInfo.current()
        MetricPanel(title: "Disk", symbol: "internaldrive", trailing: "Macintosh HD") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                BytesText(bytes: vol.available).font(.number(28)).foregroundStyle(Palette.text)
                Text("free of \(vol.total.formattedBytes)").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                Spacer()
            }
            RelativeBar(fraction: vol.usedFraction, color: Brand.pressure(vol.usedFraction))
            Sparkline(points: m.readHistory, color: Palette.teal, secondary: m.writeHistory, secondaryColor: Palette.rose)
                .frame(height: 58)
            HStack(spacing: 16) {
                rate("Read", m.diskRead, Palette.teal)
                rate("Write", m.diskWrite, Palette.rose)
                Spacer()
            }
        }
    }

    private func rate(_ label: String, _ v: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 10, height: 2)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
            Text(formatRate(v)).font(.mono(11.5)).foregroundStyle(Palette.text)
        }
    }
}

private struct NetworkPanel: View {
    let m: SystemMonitor

    var body: some View {
        MetricPanel(title: "Network", symbol: "network", trailing: m.interface) {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Download").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    Text(formatRate(m.netDown)).font(.number(20)).foregroundStyle(Palette.info)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Upload").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    Text(formatRate(m.netUp)).font(.number(20)).foregroundStyle(Palette.violet)
                }
                Spacer()
            }
            Sparkline(points: m.downHistory, color: Palette.info, secondary: m.upHistory, secondaryColor: Palette.violet)
                .frame(height: 58)
            StatLine(label: "Local IP", value: m.ip ?? "—")
        }
    }
}

private struct PowerPanel: View {
    let m: SystemMonitor

    var body: some View {
        MetricPanel(title: "Power", symbol: "bolt", trailing: m.battery == nil ? "AC power" : m.battery?.stateLabel) {
            if let b = m.battery {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    BigPercent(value: b.level)
                    Image(systemName: b.isCharging ? "bolt.fill" : (b.onAC ? "powerplug" : "battery.75"))
                        .font(.system(size: 13)).foregroundStyle(b.isCharging ? Palette.success : Palette.textSecondary)
                    Spacer()
                    if let mins = b.minutesRemaining, !b.onAC {
                        Text("\(mins / 60)h \(mins % 60)m left").font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                    }
                }
                GardenProgress(value: b.level, total: 1,
                               color: b.level < 0.2 ? Palette.danger : (b.level < 0.4 ? Palette.warning : Palette.success))
                VStack(spacing: 6) {
                    StatLine(label: "Condition", value: b.condition ?? "—")
                    StatLine(label: "Max capacity", value: b.healthFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                             color: (b.healthFraction ?? 1) < 0.8 ? Palette.warning : Palette.text)
                    StatLine(label: "Cycle count", value: b.cycles.map(String.init) ?? "—")
                    StatLine(label: "Temperature", value: b.temperature.map { String(format: "%.1f °C", $0) } ?? "—")
                    StatLine(label: "Thermal state", value: m.thermal.label, color: thermalColor(m.thermal))
                }
            } else {
                Text("Desktop Mac").font(.number(22)).foregroundStyle(Palette.text)
                Text("No internal battery. Running on AC power.").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                StatLine(label: "Thermal state", value: m.thermal.label, color: thermalColor(m.thermal))
            }
        }
    }
}

// MARK: - Processes

private struct ProcessesPanel: View {
    let m: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "list.bullet.indent").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textTertiary)
                Text("Processes").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Your processes by CPU").font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("\(m.zombieCount) zombie\(m.zombieCount == 1 ? "" : "s")")
                    .font(.mono(11)).foregroundStyle(m.zombieCount > 0 ? Palette.warning : Palette.textTertiary)
                    .help("Exited processes whose parent hasn't collected them yet")
            }
            HStack(spacing: 10) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 60, alignment: .trailing)
                Text("CPU").frame(width: 170, alignment: .leading)
                Text("Memory").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 8)
            Rectangle().fill(Palette.border).frame(height: 1)
            if m.processes.isEmpty {
                Text("Sampling…").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                let peak = max(m.processes.map(\.cpu).max() ?? 1, 0.01)
                VStack(spacing: 0) {
                    ForEach(m.processes) { p in
                        ProcessRow(process: p, fraction: p.cpu / peak)
                    }
                }
                .animation(.tidy, value: m.processes.map(\.pid))
            }
        }
        .padding(16)
        .panel()
    }
}

private struct ProcessRow: View {
    let process: ProcessStat
    let fraction: Double
    @State private var hovering = false

    private var app: NSRunningApplication? { NSRunningApplication(processIdentifier: process.pid) }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                if let icon = app?.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "terminal").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        .frame(width: 16, height: 16)
                }
                Text(app?.localizedName ?? process.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(process.pid)").font(.mono(11.5)).foregroundStyle(Palette.textTertiary).frame(width: 60, alignment: .trailing)
            HStack(spacing: 8) {
                Text(String(format: "%.1f%%", process.cpu * 100)).font(.mono(11.5)).foregroundStyle(Palette.text)
                    .frame(width: 56, alignment: .trailing)
                RelativeBar(fraction: fraction, color: process.cpu > 0.8 ? Palette.warning : Palette.info)
            }
            .frame(width: 170)
            Text(Int64(process.memory).formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.white.opacity(0.04) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if let app, app.activationPolicy == .regular, app.processIdentifier != getpid() {
                Button("Quit \(app.localizedName ?? process.name)") { app.terminate() }
                Divider()
            }
            Button("Show in Activity Monitor") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
            Button("Copy PID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(process.pid)", forType: .string)
            }
        }
    }
}
