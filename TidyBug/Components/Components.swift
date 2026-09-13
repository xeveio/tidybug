import AppKit
import SwiftUI
import TidyBugCore

/// Byte count with rolling digits.
struct BytesText: View {
    let bytes: Int64
    var body: some View {
        Text(bytes.formattedBytes)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(bytes)))
            .animation(.tidy, value: bytes)
    }
}

/// Thin progress ring; colour follows disk pressure.
struct SizeRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 6
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(Palette.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown ? max(0.001, min(fraction, 1)) : 0.001)
                .stroke(Brand.pressure(fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.9), value: shown)
        .animation(.tidy, value: fraction)
        .onAppear { shown = true }
    }
}

/// Bordered tile with a coloured category symbol.
struct RuleIcon: View {
    let symbol: String
    let hue: Double
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Brand.tint(hue).opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).strokeBorder(Brand.tint(hue).opacity(0.22)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(Brand.tint(hue))
            }
    }
}

/// Status dot + label, e.g. "● Safe".
struct SafetyBadge: View {
    let level: SafetyLevel
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Brand.color(for: level)).frame(width: 6, height: 6)
            Text(label)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Palette.textSecondary)
    }

    private var label: String {
        switch level {
        case .safe: "Safe"
        case .review: "Review"
        case .advisor: "Manual"
        }
    }
}

struct Pill: View {
    let text: String
    var color: Color = Palette.textSecondary
    var symbol: String?
    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
        .foregroundStyle(color)
    }
}

struct AgeBadge: View {
    let days: Int
    var body: some View {
        Text(Self.describe(days))
            .font(.mono(11.5))
            .foregroundStyle(days > 180 ? Palette.warning : Palette.textSecondary)
    }

    static func describe(_ days: Int) -> String {
        switch days {
        case 0: "today"
        case 1: "1d"
        case ..<30: "\(days)d"
        case ..<365: "\(days / 30)mo"
        default: "\(days / 365)y"
        }
    }
}

/// Square checkbox with a mixed state.
struct CheckToggle: View {
    let state: AppModel.CheckState
    var tint: Color = Palette.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(state == .off ? Color.clear : tint)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(state == .off ? Palette.borderStrong : .clear, lineWidth: 1.2))
                Image(systemName: state == .mixed ? "minus" : "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(state == .off ? 0.4 : 1)
                    .opacity(state == .off ? 0 : 1)
            }
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.bouncy, value: state)
        .sensoryFeedback(.selection, trigger: state)
    }
}

extension AppModel.CheckState {
    init(_ on: Bool) { self = on ? .on : .off }
}

/// Activity indicator: the mark with a rotating scan arc.
struct ScanOrb: View {
    var size: CGFloat = 48
    var active = true
    var body: some View {
        LogoMark(state: active ? .scanning : .idle, size: size * 0.55)
            .frame(width: size, height: size)
    }
}

/// Quiet empty state: icon tile, title, one line of explanation, actions.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var mood: MascotMood = .idle
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.raised)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            actions.padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileIcon: View {
    let path: String
    var size: CGFloat = 18
    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Thin bar showing a value relative to the largest in a list.
struct RelativeBar: View {
    let fraction: Double
    var color: Color = Palette.accent
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(Color.white.opacity(0.05))
                .overlay(alignment: .leading) {
                    Capsule().fill(color.opacity(0.9)).frame(width: max(3, geo.size.width * min(1, fraction)))
                }
        }
        .frame(height: 4)
        .animation(.tidy, value: fraction)
    }
}

/// Linear progress bar.
struct GardenProgress: View {
    let value: Double
    let total: Double
    var color: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule().fill(color)
                    .frame(width: max(4, geo.size.width * min(1, value / max(total, 1))))
            }
        }
        .frame(height: 4)
        .animation(.tidy, value: value)
    }
}

/// Inline status row while a scan runs.
struct ScanStatusBar: View {
    let text: String
    let detail: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LogoMark(state: .scanning, size: 14).padding(4)
            Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.text)
            Text(detail)
                .font(.mono(11.5))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Stop", action: onCancel).buttonStyle(.tidySecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .panel(radius: 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Section title used on dashboards.
struct SectionHeading: View {
    let title: String
    var subtitle: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
            if let subtitle { Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.textTertiary) }
        }
    }
}
