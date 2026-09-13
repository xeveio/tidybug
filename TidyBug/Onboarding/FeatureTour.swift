import SwiftUI
import TidyBugCore

/// "How to use TidyBug": a short walkthrough with live, looping mini-demos of
/// each feature. Shown once after setup; reopen from Help or ⌘K.
struct FeatureTour: View {
    let onClose: () -> Void
    @State private var step = 0
    @State private var forward = true
    @FocusState private var focused: Bool

    struct Step {
        let eyebrow: String
        let title: String
        let body: String
        let hints: [(keys: String, label: String)]
        let demo: Demo
    }

    enum Demo { case scan, review, space, collector, projects, duplicates, palette }

    static let steps: [Step] = [
        Step(eyebrow: "Overview", title: "Scan in seconds",
             body: "TidyBug checks 19 known locations in parallel: Xcode DerivedData, device support files, package-manager caches, app caches, logs, installers and more. Scanning is read-only.",
             hints: [("⌘R", "Scan"), ("⌘1", "Overview")], demo: .scan),
        Step(eyebrow: "Clean", title: "Review before anything moves",
             body: "Results are grouped by risk. Safe items are regenerable and pre-selected, Review items need your decision, and Manual items only show guidance. Everything goes to the Trash and is logged.",
             hints: [("⌘2", "Clean")], demo: .review),
        Step(eyebrow: "Space", title: "See exactly where space goes",
             body: "An interactive map of any folder. Click a ring to zoom in and the centre to go back up. Sizes are hardlink-aware, so pnpm stores and clones are never double-counted.",
             hints: [("⌘3", "Space"), ("⇧⌘R", "Map home folder")], demo: .space),
        Step(eyebrow: "Collector", title: "Drag to collect, delete in one go",
             body: "Drag anything into the Collector at the bottom of the window: a slice of the map, a row from any list, or files straight from Finder. Check the total, then Delete All moves everything to the Trash at once.",
             hints: [("Drag", "Add to Collector"), ("⇧⌘⌫", "Delete All")], demo: .collector),
        Step(eyebrow: "Projects", title: "Reclaim build leftovers",
             body: "Finds node_modules, build folders, .venv, Pods, target and more across your repositories. Only folders a lockfile or manifest can recreate are suggested. Signed archives are never touched.",
             hints: [("⌘4", "Projects")], demo: .projects),
        Step(eyebrow: "Duplicates", title: "Remove exact and near duplicates",
             body: "Files are matched by SHA-256 and photos by visual similarity. One copy in every group is always kept, so you can never delete the last one.",
             hints: [("⌘5", "Duplicates"), ("Space", "Quick Look")], demo: .duplicates),
        Step(eyebrow: "Keyboard", title: "Everything is a keystroke away",
             body: "Press ⌘K to search and run any command. TidyBug also lives in the menu bar for a quick look at free space and a one-click clean of safe items.",
             hints: [("⌘K", "Command palette")], demo: .palette),
    ]

    private var current: Step { Self.steps[step] }
    private var isLast: Bool { step == Self.steps.count - 1 }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            HStack(spacing: 0) {
                demoArea
                    .frame(width: 470)
                    .frame(maxHeight: .infinity)
                    .background(Palette.sunken)
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.border).frame(width: 1) }
                content
            }
            .frame(width: 900, height: 540)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .panel(radius: 16, lifted: true)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { go(step + 1); return .handled }
        .onKeyPress(.leftArrow) { go(step - 1); return .handled }
        .onKeyPress(.return) { isLast ? onClose() : go(step + 1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onAppear { focused = true }
    }

    // MARK: Demo side

    private var demoArea: some View {
        ZStack {
            DotGrid(spacing: 18).opacity(0.7)
            Group {
                switch current.demo {
                case .scan: ScanDemo()
                case .review: ReviewDemo()
                case .space: SpaceDemo()
                case .collector: CollectorDemo()
                case .projects: ProjectsDemo()
                case .duplicates: DuplicatesDemo()
                case .palette: PaletteDemo()
                }
            }
            .padding(28)
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
        }
        .clipped()
    }

    // MARK: Text side

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(format: "%02d / %02d", step + 1, Self.steps.count))
                    .font(.mono(11)).foregroundStyle(Palette.textTertiary)
                Spacer()
                Button("Skip tour", action: onClose).buttonStyle(.tidyQuiet)
            }
            Spacer(minLength: 20)
            VStack(alignment: .leading, spacing: 12) {
                Text(current.eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold)).kerning(0.8)
                    .foregroundStyle(Palette.accent)
                Text(current.title)
                    .font(.system(size: 26, weight: .semibold)).kerning(-0.4)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(current.body)
                    .font(.system(size: 13.5)).lineSpacing(3)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(current.hints.enumerated()), id: \.offset) { _, hint in
                        HStack(spacing: 8) {
                            KeyHint(keys: hint.keys)
                            Text(hint.label).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 16 : -16)), removal: .opacity))
            Spacer(minLength: 20)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<Self.steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? Palette.accent : (i < step ? Palette.textTertiary : Palette.border))
                            .frame(width: i == step ? 18 : 6, height: 4)
                            .onTapGesture { go(i) }
                    }
                }
                Spacer()
                if step > 0 {
                    Button { go(step - 1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.tidySecondary)
                }
                Button {
                    isLast ? onClose() : go(step + 1)
                } label: {
                    HStack(spacing: 8) {
                        Text(isLast ? "Start using TidyBug" : "Next")
                        Text("↵").opacity(0.7)
                    }
                }
                .buttonStyle(.tidy)
            }
        }
        .padding(28)
        .animation(.tidy, value: step)
    }

    private func go(_ target: Int) {
        guard (0..<Self.steps.count).contains(target), target != step else { return }
        forward = target > step
        withAnimation(.tidy) { step = target }
    }
}

// MARK: - Demo helpers

/// Loops `content(p)` with p in 0…1 over `period` seconds, starting at 0 on appear.
private struct DemoClock<Content: View>: View {
    let period: Double
    @ViewBuilder let content: (Double) -> Content
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            content(t.truncatingRemainder(dividingBy: period) / period)
        }
    }
}

/// Smoothstep from a to b.
private func ramp(_ p: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(1, max(0, (p - a) / (b - a)))
    return x * x * (3 - 2 * x)
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }

private struct DemoCheck: View {
    let on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 3.5)
            .fill(on ? Palette.accent : .clear)
            .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(on ? .clear : Palette.borderStrong, lineWidth: 1.2))
            .overlay(Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white).opacity(on ? 1 : 0))
            .frame(width: 14, height: 14)
    }
}

private struct DemoWindow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white.opacity(0.12)).frame(width: 7, height: 7) }
            }
            .padding(10)
            Rectangle().fill(Palette.border).frame(height: 1)
            content.padding(14)
        }
        .panel(radius: 10)
    }
}

// MARK: - Demos

private struct ScanDemo: View {
    let rows: [(String, String, Double, String, Color)] = [
        ("iphone", "iOS Device Support", 1.0, "17.6 GB", Palette.violet),
        ("hammer", "Xcode DerivedData", 0.73, "12.9 GB", Palette.info),
        ("opticaldisc", "Installers", 0.61, "10.8 GB", Palette.rose),
        ("internaldrive", "App Caches", 0.57, "10.1 GB", Palette.teal),
        ("shippingbox", "Package Caches", 0.33, "5.8 GB", Palette.warning),
        ("doc.text", "Logs", 0.04, "31 MB", Palette.series[5]),
    ]

    var body: some View {
        DemoClock(period: 5) { p in
            DemoWindow {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        LogoMark(state: p < 0.72 ? .scanning : .idle, size: 11).padding(3)
                        Text(p < 0.72 ? "Scanning \(min(19, Int(p / 0.72 * 19)))/19" : "57.2 GB reclaimable")
                            .font(.mono(11)).foregroundStyle(p < 0.72 ? Palette.textSecondary : Palette.success)
                        Spacer()
                    }
                    ForEach(0..<rows.count, id: \.self) { i in
                        let r = ramp(p, 0.06 + Double(i) * 0.09, 0.3 + Double(i) * 0.09)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: rows[i].0).font(.system(size: 10)).foregroundStyle(rows[i].4).frame(width: 14)
                                Text(rows[i].1).font(.system(size: 11.5)).foregroundStyle(Palette.text)
                                Spacer()
                                Text(r > 0.98 ? rows[i].3 : "—").font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                            }
                            GeometryReader { g in
                                Capsule().fill(Color.white.opacity(0.05))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(rows[i].4.opacity(0.85)).frame(width: g.size.width * rows[i].2 * r)
                                    }
                            }
                            .frame(height: 3)
                        }
                        .opacity(0.35 + 0.65 * min(1, r * 2))
                    }
                }
            }
        }
    }
}

private struct ReviewDemo: View {
    let rows: [(String, String, Int64, SafetyLevel, Double)] = [
        ("hammer", "Xcode DerivedData", 12_900_000_000, .safe, 0.12),
        ("iphone", "Old Device Support", 17_600_000_000, .safe, 0.22),
        ("shippingbox", "Package Caches", 5_800_000_000, .safe, 0.32),
        ("opticaldisc", "Installers", 10_800_000_000, .review, 0.52),
        ("globe", "Chrome Profile", 48_500_000_000, .advisor, 2),
    ]

    var body: some View {
        DemoClock(period: 5) { p in
            let total = rows.filter { p > $0.4 }.reduce(Int64(0)) { $0 + $1.2 }
            DemoWindow {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { i in
                        HStack(spacing: 10) {
                            if rows[i].3 == .advisor {
                                Color.clear.frame(width: 14, height: 14)
                            } else {
                                DemoCheck(on: p > rows[i].4)
                            }
                            Image(systemName: rows[i].0).font(.system(size: 10)).foregroundStyle(Palette.textSecondary).frame(width: 14)
                            Text(rows[i].1).font(.system(size: 11.5)).foregroundStyle(Palette.text)
                            Spacer()
                            SafetyBadge(level: rows[i].3)
                            Text(rows[i].2.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                                .frame(width: 58, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        if i < rows.count - 1 { Rectangle().fill(Palette.border).frame(height: 1) }
                    }
                    HStack {
                        Text("Selected").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                        Text(total.formattedBytes).font(.mono(12, weight: .semibold)).foregroundStyle(Palette.text)
                            .contentTransition(.numericText(value: Double(total)))
                        Spacer()
                        Text("Move to Trash")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accent))
                            .scaleEffect(p > 0.8 && p < 0.86 ? 0.94 : 1)
                            .shadow(color: Palette.accent.opacity(p > 0.75 ? 0.5 : 0), radius: 10)
                    }
                    .padding(.top, 12)
                    .animation(.tidy, value: total)
                }
            }
        }
    }
}

/// Mini sunburst; one slice lifts off and is dragged into the Collector.
private struct SpaceDemo: View {
    var body: some View {
        DemoClock(period: 5.5) { p in
            GeometryReader { geo in SpaceScene(p: p, size: geo.size) }
        }
    }
}

private struct SpaceScene: View {
    let p: Double
    let size: CGSize

    static let ring1: [Double] = [0.28, 0.22, 0.17, 0.13, 0.11, 0.09]
    static let ring2: [[Double]] = [[0.6, 0.4], [0.5, 0.3, 0.2], [0.7, 0.3], [0.5, 0.5], [1], [0.6, 0.4]]

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }
    private var center: CGPoint { CGPoint(x: w / 2, y: h * 0.4) }
    private var radius: CGFloat { min(w, h) * 0.3 }
    private var reveal: Double { ramp(p, 0, 0.25) }
    private var dragT: Double { ramp(p, 0.45, 0.78) }
    private var collected: Bool { p > 0.78 }
    private var hovering: Bool { p > 0.3 }

    /// Mid-point of the slice that gets dragged (ring 2, first child of segment 0).
    private var sliceStart: CGPoint {
        let angle = 0.28 * 0.6 * Double.pi - Double.pi / 2
        let rr = Double(radius) * 0.83
        return CGPoint(x: Double(center.x) + cos(angle) * rr, y: Double(center.y) + sin(angle) * rr)
    }

    /// Quadratic Bézier from the slice down into the Collector strip.
    private var chip: CGPoint {
        let from = sliceStart
        let to = CGPoint(x: w * 0.36, y: h - 26)
        let ctrl = CGPoint(x: w * 0.9, y: h * 0.62)
        let t = CGFloat(dragT)
        let u = 1 - t
        let x = u * u * from.x + 2 * u * t * ctrl.x + t * t * to.x
        let y = u * u * from.y + 2 * u * t * ctrl.y + t * t * to.y
        return CGPoint(x: x, y: y)
    }

    private var cursor: CGPoint {
        if dragT > 0 { return CGPoint(x: chip.x + 10, y: chip.y + 12) }
        let k = ramp(p, 0.25, 0.4)
        return CGPoint(x: lerp(w * 0.8, sliceStart.x, k) + 10, y: lerp(h * 0.1, sliceStart.y, k) + 12)
    }

    var body: some View {
        ZStack {
            rings
            centerLabel
            strip
            if dragT > 0 && !collected { dragChip }
            if p > 0.25 && p < 0.85 {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .position(cursor)
            }
        }
    }

    private var rings: some View {
        Canvas { ctx, _ in
            let limit = reveal * 2 * .pi
            var a = 0.0
            for (i, f) in Self.ring1.enumerated() {
                let span = f * 2 * .pi
                let color = Palette.series[i]
                Self.arc(&ctx, center, radius * 0.32, radius * 0.62, a, a + span, limit, color)
                var b = a
                for (j, g) in Self.ring2[i].enumerated() {
                    let s2 = span * g
                    let isSlice = i == 0 && j == 0
                    let lifted = isSlice && hovering && dragT == 0
                    let fade: Double = isSlice && dragT > 0 ? 0.25 : 1
                    let outer = radius * (lifted ? 1.06 : 1.0)
                    let shade = color.mix(with: Palette.bg, by: 0.25).opacity(fade)
                    Self.arc(&ctx, center, radius * 0.64, outer, b, b + s2, limit, shade)
                    b += s2
                }
                a += span
            }
        }
    }

    private var centerLabel: some View {
        VStack(spacing: 1) {
            Text("~/Library").font(.mono(10)).foregroundStyle(Palette.textTertiary)
            Text("148.3 GB").font(.mono(13, weight: .semibold)).foregroundStyle(Palette.text)
        }
        .position(center)
        .opacity(reveal)
    }

    private var strip: some View {
        let armed = dragT > 0.8
        return HStack(spacing: 8) {
            Image(systemName: collected ? "tray.full.fill" : "tray")
                .font(.system(size: 11))
                .foregroundStyle(collected || armed ? Palette.accent : Palette.textSecondary)
            Text("Collector").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
            if collected {
                Text("DerivedData").font(.system(size: 10.5)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 6).padding(.vertical, 3).paperCapsule()
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
            Text(collected ? "12.9 GB" : "Zero KB").font(.mono(11)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(width: w, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(armed && !collected ? Palette.accentMuted : Palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(armed ? Palette.accent.opacity(0.6) : Palette.border))
        )
        .position(x: w / 2, y: h - 20)
        .animation(.bouncy, value: collected)
    }

    private var dragChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(Palette.info)
            Text("DerivedData · 12.9 GB").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.raised)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.borderStrong)))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .position(chip)
    }

    private static func arc(_ ctx: inout GraphicsContext, _ c: CGPoint, _ inner: CGFloat, _ outer: CGFloat,
                            _ a: Double, _ b: Double, _ limit: Double, _ color: Color) {
        let s = min(a, limit), e = min(b, limit)
        guard e - s > 0.001 else { return }
        var path = Path()
        path.addArc(center: c, radius: outer, startAngle: .radians(s - .pi / 2), endAngle: .radians(e - .pi / 2), clockwise: false)
        path.addArc(center: c, radius: inner, startAngle: .radians(e - .pi / 2), endAngle: .radians(s - .pi / 2), clockwise: true)
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(Palette.sunken), lineWidth: 1)
    }
}

private struct CollectorDemo: View {
    let sources: [(String, String, Int64, String)] = [
        ("folder.fill", "DerivedData", 12_900_000_000, "Space"),
        ("opticaldisc", "Win11_ARM64.iso", 7_400_000_000, "Large Files"),
        ("doc.fill", "state.vscdb.backup", 9_250_000_000, "Finder"),
    ]

    var body: some View {
        DemoClock(period: 6) { p in
            let arrive = [0.2, 0.36, 0.52]
            let deleting = ramp(p, 0.74, 0.82)
            let toast = p > 0.82
            let count = arrive.filter { p > $0 }.count
            let total = sources.prefix(count).reduce(Int64(0)) { $0 + $1.2 }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<sources.count, id: \.self) { i in
                    let flying = ramp(p, arrive[i] - 0.12, arrive[i])
                    HStack(spacing: 8) {
                        Image(systemName: sources[i].0).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).frame(width: 16)
                        Text(sources[i].1).font(.system(size: 11.5)).foregroundStyle(Palette.text)
                        Spacer()
                        Text(sources[i].3).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        Text(sources[i].2.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(10)
                    .panel(radius: 8)
                    .opacity(1 - 0.55 * flying)
                    .offset(x: flying > 0 && flying < 1 ? CGFloat(flying) * 6 : 0)
                }
                Spacer()
                if toast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                        Text("Moved 3 items to Trash").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("29.6 GB").font(.mono(11, weight: .semibold)).foregroundStyle(Palette.success)
                    }
                    .padding(10)
                    .panel(radius: 8, lifted: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 8) {
                    Image(systemName: count > 0 && !toast ? "tray.full.fill" : "tray")
                        .font(.system(size: 11)).foregroundStyle(count > 0 && !toast ? Palette.accent : Palette.textSecondary)
                    Text("Collector").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
                    HStack(spacing: 4) {
                        ForEach(0..<(toast ? 0 : count), id: \.self) { i in
                            Text(sources[i].1).font(.system(size: 10)).foregroundStyle(Palette.text).lineLimit(1)
                                .padding(.horizontal, 5).padding(.vertical, 3).paperCapsule()
                                .scaleEffect(1 - deleting * 0.6).opacity(1 - deleting)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Spacer(minLength: 4)
                    Text((toast ? 0 : total).formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
                    Text("Delete All")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.danger.opacity(count > 0 && !toast ? 1 : 0.35)))
                        .scaleEffect(p > 0.7 && p < 0.75 ? 0.92 : 1)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(count > 0 && !toast ? Palette.accent.opacity(0.4) : Palette.border)))
            }
            .animation(.bouncy, value: count)
            .animation(.tidy, value: toast)
        }
    }
}

private struct ProjectsDemo: View {
    let rows: [(String, String, String, Int)] = [
        ("web-dashboard", "node_modules", "1.9 GB", 142),
        ("ios-app", "build", "4.1 GB", 96),
        ("api", "node_modules", "812 MB", 3),
        ("ml-scripts", ".venv", "2.3 GB", 210),
        ("cli-tool", "target", "1.2 GB", 41),
    ]

    var body: some View {
        DemoClock(period: 5) { p in
            DemoWindow {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { i in
                        let stale = rows[i].3 >= 30
                        let picked = stale && p > 0.35 + Double(i) * 0.07
                        HStack(spacing: 10) {
                            DemoCheck(on: picked)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rows[i].0).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.text)
                                Text(rows[i].1).font(.mono(10)).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Text(rows[i].2).font(.mono(10.5)).foregroundStyle(Palette.text)
                            Text(AgeBadge.describe(rows[i].3)).font(.mono(10.5))
                                .foregroundStyle(rows[i].3 > 90 ? Palette.warning : Palette.textSecondary)
                                .frame(width: 34, alignment: .trailing)
                        }
                        .padding(.vertical, 7)
                        .background(picked ? Palette.accent.opacity(0.06) : .clear)
                        if i < rows.count - 1 { Rectangle().fill(Palette.border).frame(height: 1) }
                    }
                    HStack {
                        Text("Select stale (30d+)")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.raised)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(p > 0.2 && p < 0.35 ? Palette.accent : Palette.border)))
                            .scaleEffect(p > 0.28 && p < 0.33 ? 0.94 : 1)
                        Spacer()
                        Text(p > 0.7 ? "9.5 GB selected" : "—").font(.mono(11)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

private struct DuplicatesDemo: View {
    let copies = ["~/Pictures/Trips/IMG_2041.HEIC", "~/Downloads/IMG_2041.HEIC", "~/Desktop/IMG_2041 copy.HEIC"]

    var body: some View {
        DemoClock(period: 5) { p in
            DemoWindow {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "photo").foregroundStyle(Palette.info)
                        Text("IMG_2041.HEIC").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("× 3").font(.mono(11)).foregroundStyle(Palette.textTertiary)
                        Spacer()
                        Text(p > 0.55 ? "8.4 MB wasted" : "hashing…").font(.mono(10.5))
                            .foregroundStyle(p > 0.55 ? Palette.warning : Palette.textTertiary)
                    }
                    Text("sha256  a41f 09c2 77be … 3e10")
                        .font(.mono(10)).foregroundStyle(Palette.textTertiary)
                        .opacity(ramp(p, 0.1, 0.4))
                    VStack(spacing: 0) {
                        ForEach(0..<copies.count, id: \.self) { i in
                            let keep = i == 0
                            let picked = !keep && p > 0.5 + Double(i) * 0.1
                            HStack(spacing: 10) {
                                if keep {
                                    Pill(text: "Keep", color: Palette.success)
                                } else {
                                    DemoCheck(on: picked)
                                }
                                Text(copies[i]).font(.mono(10.5)).foregroundStyle(Palette.textSecondary).lineLimit(1)
                                    .strikethrough(picked && p > 0.85)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            .opacity(picked && p > 0.85 ? 0.4 : 1)
                            if i < copies.count - 1 { Rectangle().fill(Palette.border).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }
}

private struct PaletteDemo: View {
    let queries = ["clean safe", "map home", "dupl"]
    let commands: [(String, String, String?)] = [
        ("sparkles", "Clean safe items", nil),
        ("chart.pie", "Map home folder", "⇧⌘R"),
        ("square.on.square", "Find duplicate files", nil),
        ("arrow.clockwise", "Scan for reclaimable space", "⌘R"),
        ("hammer", "Scan projects for build artifacts", nil),
    ]

    var body: some View {
        DemoClock(period: 7.5) { p in
            let slot = min(2, Int(p * 3))
            let local = p * 3 - Double(slot)
            let q = queries[slot]
            let typed = String(q.prefix(Int(Double(q.count) * ramp(local, 0.05, 0.5))))
            let matches = commands.filter { cmd in
                guard !typed.isEmpty else { return true }
                var it = cmd.1.lowercased().makeIterator()
                return typed.replacingOccurrences(of: " ", with: "").allSatisfy { ch in
                    while let c = it.next() { if c == ch { return true } }
                    return false
                }
            }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                    Text(typed.isEmpty ? "Search or run a command…" : typed)
                        .font(.system(size: 13)).foregroundStyle(typed.isEmpty ? Palette.textTertiary : Palette.text)
                    Rectangle().fill(Palette.accent).frame(width: 1.5, height: 14)
                        .opacity(Int(p * 30) % 2 == 0 ? 1 : 0)
                    Spacer()
                    KeyHint(keys: "⌘K")
                }
                .padding(12)
                Rectangle().fill(Palette.border).frame(height: 1)
                VStack(spacing: 1) {
                    ForEach(Array(matches.prefix(4).enumerated()), id: \.element.1) { i, cmd in
                        HStack(spacing: 8) {
                            Image(systemName: cmd.0).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).frame(width: 16)
                            Text(cmd.1).font(.system(size: 12)).foregroundStyle(Palette.text)
                            Spacer()
                            if let s = cmd.2 { KeyHint(keys: s) }
                            if i == 0 && local > 0.6 { KeyHint(keys: "↵") }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i == 0 ? Color.white.opacity(0.07) : .clear))
                    }
                }
                .padding(6)
                .animation(.tidy, value: matches.map(\.1))
            }
            .panel(radius: 12, lifted: true)
        }
    }
}
