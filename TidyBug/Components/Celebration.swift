import SwiftUI
import TidyBugCore

/// Bottom toast summarising a completed clean. Replaces the old modal.
struct ResultToast: View {
    let summary: CleanSummary
    let dismiss: () -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((summary.freed > 0 ? Palette.success : Palette.warning).opacity(0.14))
                Image(systemName: summary.freed > 0 ? "checkmark" : "exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(summary.freed > 0 ? Palette.success : Palette.warning)
                    .symbolEffect(.bounce, value: shown)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(summary.freed > 0 ? "Reclaimed" : "Nothing removed")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    if summary.freed > 0 {
                        BytesText(bytes: shown ? summary.freed : 0)
                            .font(.mono(13, weight: .semibold))
                            .foregroundStyle(Palette.success)
                    }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 20)
            Button("Activity") { model.pane = .history; dismiss() }.buttonStyle(.tidySecondary)
            Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.tidyQuiet)
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 10)
        .frame(width: 520)
        .panel(radius: 12, lifted: true)
        .onAppear { withAnimation(.gentle.delay(0.1)) { shown = true } }
        .sensoryFeedback(.success, trigger: shown)
        .task {
            try? await Task.sleep(for: .seconds(8))
            dismiss()
        }
    }

    private var detail: String {
        var parts: [String] = []
        if summary.count > 0 {
            parts.append("\(summary.count) item\(summary.count == 1 ? "" : "s") \(summary.permanent ? "deleted" : "moved to Trash")")
        }
        if summary.failures > 0 { parts.append("\(summary.failures) skipped by safety checks") }
        if parts.isEmpty { parts.append("Command finished") }
        return parts.joined(separator: " · ")
    }
}

/// Kept for source compatibility with older screens; a small, restrained spark burst.
struct ConfettiView: View {
    @State private var start = Date()
    private let sparks: [(angle: Double, speed: Double)] = (0..<28).map { _ in
        (.random(in: 0...(2 * .pi)), .random(in: 60...160))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let o = CGPoint(x: size.width / 2, y: size.height / 2)
                let alpha = max(0, 1 - t / 1.2)
                guard alpha > 0 else { return }
                for s in sparks {
                    let d = s.speed * min(t, 1.2) * (1 - t / 3)
                    let p = CGPoint(x: o.x + cos(s.angle) * d, y: o.y + sin(s.angle) * d)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)),
                             with: .color(Palette.accent.opacity(alpha * 0.8)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path { Path(ellipseIn: rect) }
}

/// Legacy modal; now just shows the toast centred.
struct CelebrationOverlay: View {
    let summary: CleanSummary
    let dismiss: () -> Void
    var body: some View { ResultToast(summary: summary, dismiss: dismiss) }
}
