import AppKit
import SwiftUI
import TidyBugCore

// MARK: - Palette
//
// Dark, precise, data-first. One brand accent; everything else is neutral
// surfaces, and colour is reserved for meaning (status) and data (charts).

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }

    /// Kept for source compatibility; the app is dark-only, so `dark` wins.
    static func dynamic(light: NSColor, dark: NSColor) -> Color { Color(nsColor: dark) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Palette {
    // Surfaces
    static let bg = Color(hex: 0x0A0B0D)
    static let surface = Color(hex: 0x111317)
    static let raised = Color(hex: 0x181A1F)
    static let sunken = Color(hex: 0x070809)
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.14)

    // Text
    static let text = Color(hex: 0xEDEEF0)
    static let textSecondary = Color(hex: 0x8C919A)
    static let textTertiary = Color(hex: 0x5D626C)

    // Brand & semantic
    static let accent = Color(hex: 0xFF5F57)
    static let accentMuted = Color(hex: 0xFF5F57, alpha: 0.14)
    static let success = Color(hex: 0x3DD68C)
    static let warning = Color(hex: 0xF5B545)
    static let danger = Color(hex: 0xEF4F4F)
    static let info = Color(hex: 0x5B9CF6)
    static let violet = Color(hex: 0x9D7CF6)
    static let teal = Color(hex: 0x36C5B4)
    static let rose = Color(hex: 0xF0719B)

    /// Categorical series for charts.
    static let series: [Color] = [info, violet, teal, warning, rose, Color(hex: 0x8FD14F), Color(hex: 0x4CC6E8), accent]

    // Legacy names (earlier design) mapped onto the new tokens.
    static let paper = bg
    static let paperRaised = raised
    static let paperSunken = sunken
    static let ink = text
    static let inkSoft = textSecondary
    static let inkFaint = textTertiary
    static let hairline = border
    static let ladybug = accent
    static let ladybugDeep = accent
    static let leaf = success
    static let moss = success
    static let sun = warning
    static let sky = info
    static let plum = violet
    static let blush = rose
    static let shellInk = Color(hex: 0x2A2D33)
}

enum Brand {
    static let coral = Palette.accent
    static let magenta = Palette.accent
    static let violet = Palette.violet
    static let mint = Palette.success
    static let amber = Palette.warning
    static let sky = Palette.info

    static let gradient = LinearGradient(colors: [Color(hex: 0xFF6E66), Palette.accent], startPoint: .top, endPoint: .bottom)
    static let ring = AngularGradient(colors: [Palette.info, Palette.violet, Palette.info], center: .center)

    /// Data colour for a rule hue.
    static func tint(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.58, brightness: 0.94) }

    static func color(for safety: SafetyLevel) -> Color {
        switch safety {
        case .safe: Palette.success
        case .review: Palette.warning
        case .advisor: Palette.violet
        }
    }

    static func pressure(_ usedFraction: Double) -> Color {
        usedFraction < 0.8 ? Palette.success : (usedFraction < 0.92 ? Palette.warning : Palette.danger)
    }
}

// MARK: - Type

extension Font {
    /// Headline — SF Pro, tight.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Figures with tabular digits.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    /// SF Mono for paths, commands and sizes in tables.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Motion

extension Animation {
    static let tidy = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let bouncy = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.95)
}

// MARK: - Surfaces

struct Panel: ViewModifier {
    var radius: CGFloat = 12
    var tint: Color?
    var lifted = false

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Palette.surface)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint.opacity(0.05))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(lifted ? Palette.borderStrong : Palette.border, lineWidth: 1)
                }
                .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 18, y: 10)
        }
    }
}

extension View {
    func panel(radius: CGFloat = 12, tint: Color? = nil, lifted: Bool = false) -> some View {
        modifier(Panel(radius: radius, tint: tint, lifted: lifted))
    }

    /// Legacy name → panel (radius capped so older call sites stay crisp).
    func paperCard(radius: CGFloat = 12, tint: Color? = nil, lifted: Bool = false) -> some View {
        panel(radius: min(radius, 14), tint: tint, lifted: lifted)
    }

    func glassCard(radius: CGFloat = 12, tint: Color? = nil, interactive: Bool = false) -> some View {
        panel(radius: min(radius, 14), tint: tint)
    }

    /// Small bordered chip background.
    func paperCapsule(selected: Bool = false) -> some View {
        background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Palette.accentMuted : Palette.raised)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1))
        }
    }

    func pageTitle() -> some View {
        font(.system(size: 22, weight: .semibold)).kerning(-0.3).foregroundStyle(Palette.text)
    }
}

// MARK: - Buttons

struct TidyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, danger }
    var kind: Kind = .primary
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        TidyButtonBody(configuration: configuration, kind: kind, large: large)
    }
}

private struct TidyButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: TidyButtonStyle.Kind
    let large: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: kind == .quiet ? .medium : .semibold))
            .padding(.horizontal, large ? 16 : 11)
            .padding(.vertical, large ? 9 : 5.5)
            .foregroundStyle(foreground)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                switch kind {
                case .primary, .danger:
                    shape.fill(kind == .danger ? Palette.danger : Palette.accent)
                        .brightness(hovering && isEnabled ? 0.06 : 0)
                        .overlay(shape.strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1))
                        .shadow(color: Palette.accent.opacity(hovering && isEnabled ? 0.35 : 0.0), radius: 10, y: 2)
                case .secondary:
                    shape.fill(hovering ? Color(hex: 0x1F2228) : Palette.raised)
                        .overlay(shape.strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 1))
                case .quiet:
                    shape.fill(hovering ? Color.white.opacity(0.06) : .clear)
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.bouncy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: .white
        case .secondary: Palette.text
        case .quiet: hovering ? Palette.text : Palette.textSecondary
        }
    }
}

extension ButtonStyle where Self == TidyButtonStyle {
    static var tidy: TidyButtonStyle { TidyButtonStyle() }
    static var tidyLarge: TidyButtonStyle { TidyButtonStyle(large: true) }
    static var tidySecondary: TidyButtonStyle { TidyButtonStyle(kind: .secondary) }
    static var tidyQuiet: TidyButtonStyle { TidyButtonStyle(kind: .quiet) }
    static var tidyDanger: TidyButtonStyle { TidyButtonStyle(kind: .danger) }
}

/// Keyboard shortcut hint, e.g. ⌘K.
struct KeyHint: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border, lineWidth: 1))
    }
}

// MARK: - Background

/// Near-black canvas with a faint dot grid and a soft glow at the top.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Palette.bg
            DotGrid()
                .mask(RadialGradient(colors: [.white, .white.opacity(0)], center: .top, startRadius: 0, endRadius: 900))
            RadialGradient(colors: [Palette.accent.opacity(0.07), .clear], center: UnitPoint(x: 0.5, y: -0.1),
                           startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct DotGrid: View {
    var spacing: CGFloat = 22
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white.opacity(0.07)))
                    x += spacing
                }
                y += spacing
            }
        }
        .drawingGroup()
    }
}

/// Retained for older call sites; renders nothing visible in the new design.
struct PaperGrain: View {
    var body: some View { Color.clear }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
