import SwiftUI
import TidyBugCore

struct SunSegment: Identifiable {
    var id: ObjectIdentifier { node.id }
    let node: DiskNode
    let depth: Int
    let start: Double
    let end: Double
    let color: Color
}

enum SunburstLayout {
    static let maxDepth = 5

    /// Top-level children take a series colour; deeper rings darken toward the background.
    static func segments(for focus: DiskNode) -> [SunSegment] {
        var out: [SunSegment] = []
        func walk(_ node: DiskNode, depth: Int, start: Double, span: Double, base: Color?) {
            guard depth <= maxDepth, node.size > 0 else { return }
            var angle = start
            var colorIndex = 0
            for child in node.children {
                let s = span * Double(child.size) / Double(node.size)
                defer { angle += s }
                guard s > 0.004 else { continue }
                let seriesColor = base ?? Palette.series[colorIndex % Palette.series.count]
                if base == nil && !child.isAggregate { colorIndex += 1 }
                let color: Color = child.isAggregate || child.unreadable
                    ? Color(hex: 0x2A2E35)
                    : seriesColor.mix(with: Palette.bg, by: min(0.55, Double(depth - 1) * 0.14))
                out.append(SunSegment(node: child, depth: depth, start: angle, end: angle + s, color: color))
                if child.isDirectory { walk(child, depth: depth + 1, start: angle, span: s, base: seriesColor) }
            }
        }
        walk(focus, depth: 1, start: 0, span: 2 * .pi, base: nil)
        return out
    }
}

struct SunburstGeometry {
    let size: CGSize
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    var radius: CGFloat { min(size.width, size.height) / 2 - 8 }
    var core: CGFloat { radius * 0.3 }
    var ring: CGFloat { (radius - core) / CGFloat(SunburstLayout.maxDepth) }

    enum Hit { case center, segment(SunSegment), none }

    func hit(_ p: CGPoint, in segments: [SunSegment]) -> Hit {
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = sqrt(dx * dx + dy * dy)
        if dist < core { return .center }
        let depth = Int((dist - core) / ring) + 1
        var theta = atan2(Double(dy), Double(dx)) + .pi / 2
        if theta < 0 { theta += 2 * .pi }
        if let s = segments.first(where: { $0.depth == depth && theta >= $0.start && theta < $0.end }) {
            return .segment(s)
        }
        return .none
    }
}

/// Canvas-drawn sunburst. `reveal` animates 0→1 to sweep the rings in.
struct SunburstCanvas: View, Animatable {
    var reveal: Double
    let segments: [SunSegment]
    let hovered: ObjectIdentifier?

    var animatableData: Double {
        get { reveal }
        set { reveal = newValue }
    }

    var body: some View {
        Canvas { ctx, size in
            let g = SunburstGeometry(size: size)
            let limit = reveal * 2 * .pi
            for seg in segments {
                let start = min(seg.start, limit), end = min(seg.end, limit)
                guard end - start > 0.0005 else { continue }
                let isHovered = seg.id == hovered
                let inner = g.core + CGFloat(seg.depth - 1) * g.ring
                var outer = inner + g.ring
                if isHovered { outer += 4 }
                var path = Path()
                path.addArc(center: g.center, radius: outer, startAngle: .radians(start - .pi / 2),
                            endAngle: .radians(end - .pi / 2), clockwise: false)
                path.addArc(center: g.center, radius: inner, startAngle: .radians(end - .pi / 2),
                            endAngle: .radians(start - .pi / 2), clockwise: true)
                path.closeSubpath()
                let dim = hovered != nil && !isHovered
                ctx.fill(path, with: .color(seg.color.opacity(dim ? 0.55 : 1)))
                ctx.stroke(path, with: .color(isHovered ? .white.opacity(0.85) : Palette.bg), lineWidth: 1)
            }
        }
    }
}

struct DiskMapView: View {
    @Environment(AppModel.self) private var model
    @State private var segments: [SunSegment] = []
    @State private var hovered: SunSegment?
    @State private var reveal: Double = 0
    @State private var binTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.mapScanning {
                scanning
            } else if let focus = model.mapFocus {
                breadcrumb(focus)
                HStack(alignment: .top, spacing: 14) {
                    sunburst(focus).padding(16).panel()
                        .popoverTip(DiskMapCollectorTip(), arrowEdge: .bottom)
                    childList(focus).frame(width: 360)
                }
            } else {
                EmptyStateView(symbol: "chart.pie", title: "No map yet",
                               message: "Build an interactive map of a folder's disk usage. Click a folder to zoom in; click a file or drag any segment to the Collector to review it for removal.") {
                    HStack(spacing: 8) {
                        Button { model.scanDiskMap() } label: {
                            ShortcutLabel(title: "Map Home Folder", symbol: "chart.pie", keys: "⇧⌘R")
                        }
                        .buttonStyle(.tidyLarge)
                        Button("Choose Folder…") {
                            if let path = Finder.chooseFolder(startingAt: model.mapRootPath) { model.scanDiskMap(path: path) }
                        }
                        .buttonStyle(TidyButtonStyle(kind: .secondary, large: true))
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 18)
        .onChange(of: model.mapFocus?.id, initial: true) { rebuild(animated: true) }
        .onChange(of: model.mapVersion) { rebuild(animated: false) }
    }

    private func rebuild(animated: Bool) {
        guard let focus = model.mapFocus else { segments = []; return }
        segments = SunburstLayout.segments(for: focus)
        hovered = nil
        if animated {
            reveal = 0
            withAnimation(.easeOut(duration: 0.6)) { reveal = 1 }
        } else {
            reveal = 1
        }
    }

    private var subtitle: String {
        if model.mapScanning { return "Scanning \(Finder.abbreviate(model.mapRootPath))…" }
        if let root = model.mapRoot {
            return "\(Finder.abbreviate(root.path)) · \(root.size.formattedBytes) in \(root.fileCount.formatted()) files"
        }
        return "Interactive map of disk usage by folder."
    }

    // MARK: Header

    private var header: some View {
        ScreenHeader(title: "Space", subtitle: subtitle) {
            Button {
                if let path = Finder.chooseFolder(startingAt: model.mapRootPath) { model.scanDiskMap(path: path) }
            } label: { Label("Choose Folder…", systemImage: "folder") }
                .buttonStyle(.tidySecondary)
            Button { model.scanDiskMap() } label: {
                ShortcutLabel(title: "Rescan", symbol: "arrow.clockwise", keys: "⇧⌘R")
            }
            .buttonStyle(.tidySecondary)
            .disabled(model.mapScanning)
        }
    }

    private func breadcrumb(_ focus: DiskNode) -> some View {
        HStack(spacing: 2) {
            ForEach(focus.ancestors) { node in
                Button {
                    model.focus(node)
                } label: {
                    Text(node === focus.ancestors.first ? Finder.abbreviate(node.path) : node.name)
                        .font(.mono(12, weight: node === focus ? .semibold : .regular))
                        .foregroundStyle(node === focus ? Palette.text : Palette.textSecondary)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                if node !== focus { Text("/").font(.mono(12)).foregroundStyle(Palette.textTertiary) }
            }
            Spacer()
            if focus.parent != nil {
                Button { model.focus(focus.parent) } label: { Label("Up", systemImage: "arrow.up") }
                    .buttonStyle(.tidyQuiet)
            }
        }
        .animation(.tidy, value: model.mapFocus?.id)
    }

    // MARK: Scanning

    private var scanning: some View {
        VStack(spacing: 12) {
            Spacer()
            LogoMark(state: .scanning, size: 26).padding(10)
            Text("Scanning \(Finder.abbreviate(model.mapRootPath))")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            BytesText(bytes: model.mapProgress?.bytes ?? 0)
                .font(.mono(30, weight: .semibold)).foregroundStyle(Palette.text)
            Text("\((model.mapProgress?.files ?? 0).formatted()) files")
                .font(.mono(12)).foregroundStyle(Palette.textSecondary)
                .contentTransition(.numericText())
            Text(Finder.abbreviate(model.mapProgress?.currentPath ?? model.mapRootPath))
                .font(.mono(11)).foregroundStyle(Palette.textTertiary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
            Button("Stop") { model.cancelDiskMap() }.buttonStyle(.tidySecondary).padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .animation(.tidy, value: model.mapProgress?.files)
    }

    // MARK: Sunburst

    private func sunburst(_ focus: DiskNode) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let g = SunburstGeometry(size: CGSize(width: side, height: side))
            ZStack {
                SunburstCanvas(reveal: reveal, segments: segments, hovered: hovered?.id)
                    .animation(.easeOut(duration: 0.12), value: hovered?.id)
                Circle().fill(Palette.surface).frame(width: g.core * 2 - 4, height: g.core * 2 - 4)
                    .allowsHitTesting(false)
                VStack(spacing: 3) {
                    let shown = hovered?.node ?? focus
                    Text(shown.name)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                    BytesText(bytes: shown.size).font(.mono(18, weight: .semibold)).foregroundStyle(Palette.text)
                    if shown.fileCount > 0 {
                        Text("\(shown.fileCount.formatted()) files").font(.mono(10.5)).foregroundStyle(Palette.textTertiary)
                    }
                    if hovered == nil && focus.parent != nil {
                        Text("click to go up").font(.system(size: 10)).foregroundStyle(Palette.textTertiary).padding(.top, 2)
                    }
                }
                .frame(width: g.core * 1.6)
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    if case .segment(let s) = g.hit(p, in: segments) {
                        if hovered?.id != s.id { hovered = s }
                    } else if hovered != nil {
                        hovered = nil
                    }
                case .ended:
                    hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { p in
                switch g.hit(p, in: segments) {
                case .center: model.focus(focus.parent)
                case .segment(let s):
                    if s.node.isDirectory && !s.node.children.isEmpty { model.focus(s.node) }
                    else { model.addToCollector(s.node) }
                case .none: break
                }
            }
            .contextMenu {
                if let node = hovered?.node, !node.isAggregate {
                    Button("Add “\(node.name)” to Collector") { model.addToCollector(node) }
                    Button("Reveal in Finder") { Finder.reveal(node.url) }
                }
            }
            .draggable((hovered.map { $0.node.isAggregate ? focus : $0.node } ?? focus).url) {
                let node = hovered.map { $0.node.isAggregate ? focus : $0.node } ?? focus
                HStack(spacing: 6) {
                    Text(node.name).font(.mono(12)).foregroundStyle(Palette.text)
                    Text(node.size.formattedBytes).font(.mono(11)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .paperCapsule()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 380, minHeight: 380)
    }

    // MARK: Child list

    private func childList(_ focus: DiskNode) -> some View {
        let children = focus.children
        let biggest = Double(children.first?.size ?? 1)
        let colors = Dictionary(segments.filter { $0.depth == 1 }.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a })
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeading(title: "Contents")
                Spacer()
                Text("\(children.count) items").font(.mono(11)).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(children) { node in
                        MapRow(node: node, fraction: Double(node.size) / max(biggest, 1),
                               highlighted: hovered?.node === node,
                               color: colors[node.id] ?? Palette.textTertiary,
                               open: { model.focus(node) },
                               collect: { model.addToCollector(node) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .panel()
    }

}

struct MapRow: View {
    let node: DiskNode
    let fraction: Double
    let highlighted: Bool
    var color: Color = Palette.info
    let open: () -> Void
    let collect: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 26)
            if node.isAggregate {
                Image(systemName: "square.grid.3x3").font(.system(size: 11)).foregroundStyle(Palette.textTertiary).frame(width: 16)
            } else {
                FileIcon(path: node.path, size: 16)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(node.name).font(.system(size: 12.5)).foregroundStyle(Palette.text).lineLimit(1)
                    if node.unreadable { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(Palette.warning) }
                    Spacer()
                    Text(node.size.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                }
                RelativeBar(fraction: fraction, color: node.isAggregate ? Palette.textTertiary : color)
            }
            if !node.isAggregate {
                Button(action: collect) { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .opacity(hovering ? 1 : 0)
                    .help("Add to Collector")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background((hovering || highlighted) ? Color.white.opacity(0.04) : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { open() }
        .onTapGesture { if node.isDirectory { open() } }
        .draggable(node.url) {
            Text(node.name).font(.mono(12)).padding(.horizontal, 8).padding(.vertical, 4).paperCapsule()
        }
        .contextMenu {
            if !node.isAggregate {
                Button("Add to Collector", action: collect)
                Button("Reveal in Finder") { Finder.reveal(node.url) }
            }
        }
    }
}
