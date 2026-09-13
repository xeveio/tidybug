import SwiftUI

/// Activity state shown by the logo mark.
enum MascotMood: Equatable, Sendable {
    case idle, happy, curious, scanning, sweeping, celebrating, worried, sleeping, waving
}

/// TidyBug's mark: a geometric ladybug — split shell, head, four cut-out
/// spots. It animates only to communicate state (scanning, cleaning, done).
///
/// Named `Tidy` for source compatibility; `look` is accepted and ignored.
struct Tidy: View {
    var mood: MascotMood = .idle
    var size: CGFloat = 200
    var look: CGPoint? = nil

    init(mood: MascotMood = .idle, size: CGFloat = 200, look: CGPoint? = nil) {
        self.mood = mood
        self.size = size
        self.look = look
    }

    var body: some View {
        LogoMark(state: mood, size: size)
            .frame(width: size, height: size)
    }
}

struct LogoMark: View {
    var state: MascotMood = .idle
    var size: CGFloat = 20
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animated: Bool {
        !reduceMotion && [.scanning, .sweeping, .celebrating].contains(state)
    }

    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            MarkDrawing(state: state, t: t)
        }
        .frame(width: size, height: size)
        .opacity(state == .sleeping ? 0.45 : 1)
        .animation(.tidy, value: state)
        .accessibilityLabel("TidyBug")
    }
}

private struct MarkDrawing: View {
    let state: MascotMood
    let t: Double

    private var shellColor: Color {
        switch state {
        case .worried: Palette.warning
        case .celebrating: Palette.success
        default: Palette.accent
        }
    }

    private var open: Double {
        switch state {
        case .sweeping: abs(sin(t * 5)) * 12
        case .celebrating: 14 + sin(t * 9) * 4
        default: 0
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                if state == .scanning {
                    Circle()
                        .trim(from: 0, to: 0.22)
                        .stroke(AngularGradient(colors: [shellColor.opacity(0), shellColor], center: .center,
                                                startAngle: .degrees(0), endAngle: .degrees(80)),
                                style: StrokeStyle(lineWidth: max(1.5, s * 0.05), lineCap: .round))
                        .rotationEffect(.degrees(t * 300))
                        .frame(width: s * 1.12, height: s * 1.12)
                    Circle()
                        .stroke(shellColor.opacity(0.12), lineWidth: max(1, s * 0.03))
                        .frame(width: s * 1.12, height: s * 1.12)
                }
                // Head
                Circle()
                    .fill(Palette.shellInk)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: max(0.5, s * 0.012)))
                    .frame(width: s * 0.38, height: s * 0.38)
                    .position(x: s * 0.5, y: s * 0.22)
                // Shell halves with cut-out spots
                ForEach([true, false], id: \.self) { left in
                    ShellHalf(left: left)
                        .fill(shellColor, style: FillStyle(eoFill: true))
                        .frame(width: s * 0.8, height: s * 0.8)
                        .rotationEffect(.degrees((left ? -1 : 1) * open), anchor: UnitPoint(x: 0.5, y: 0.05))
                        .position(x: s * 0.5, y: s * 0.58)
                }
            }
            .frame(width: s, height: s)
        }
    }
}

/// Half a disc with a centre gap and two circular holes (even-odd fill).
struct ShellHalf: Shape {
    let left: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let gap = r * 0.06
        let cx = left ? c.x - gap : c.x + gap
        var p = Path()
        p.move(to: CGPoint(x: cx, y: c.y - r))
        p.addArc(center: CGPoint(x: cx, y: c.y), radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: left)
        p.closeSubpath()
        let dir: CGFloat = left ? -1 : 1
        for (dx, dy, dr) in [(0.42, -0.18, 0.17), (0.5, 0.36, 0.13)] as [(CGFloat, CGFloat, CGFloat)] {
            p.addEllipse(in: CGRect(x: cx + dir * dx * r - dr * r, y: c.y + dy * r - dr * r, width: dr * r * 2, height: dr * r * 2))
        }
        return p
    }
}

/// Neutral callout box (formerly a speech bubble).
struct SpeechBubble: View {
    let text: String
    var tail: HorizontalAlignment = .leading

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.raised)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border)))
            .contentTransition(.opacity)
            .animation(.tidy, value: text)
    }
}

// Shapes kept for any remaining call sites.
struct HalfDome: Shape {
    let left: Bool
    func path(in rect: CGRect) -> Path { ShellHalf(left: left).path(in: rect) }
}

struct Drop: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX + rect.width * 0.4, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX - rect.width * 0.4, y: rect.maxY))
        return p
    }
}

#Preview("Mark states") {
    HStack(spacing: 30) {
        ForEach([MascotMood.idle, .scanning, .sweeping, .celebrating, .worried], id: \.self) { LogoMark(state: $0, size: 64) }
    }
    .padding(40)
    .background(Palette.bg)
}
