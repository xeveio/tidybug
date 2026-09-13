import Charts
import SwiftUI
import TidyBugCore

/// Activity: totals, bytes reclaimed per day, and the operation log grouped by day.
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    private var succeeded: [LogEntry] { model.history.filter(\.success) }

    private var days: [(Date, [LogEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: model.history.prefix(1000)) { cal.startOfDay(for: $0.date) }
        return grouped.sorted { $0.key > $1.key }
    }

    struct DayBar: Identifiable {
        var id: Date { day }
        let day: Date
        let bytes: Int64
    }

    private var perDay: [DayBar] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date())) ?? .distantPast
        return Dictionary(grouping: succeeded.filter { $0.date >= cutoff }) { cal.startOfDay(for: $0.date) }
            .map { DayBar(day: $0.key, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Activity", subtitle: "Every operation is logged to ~/Library/Logs/TidyBug/operations.jsonl.") {
                    Button { Finder.reveal(OperationLog.shared.url) } label: { Label("Reveal Log", systemImage: "doc.text") }
                        .buttonStyle(.tidySecondary)
                }
                HStack(spacing: 12) {
                    StatTile(title: "Reclaimed", bytes: succeeded.reduce(0) { $0 + $1.bytes },
                             caption: "\(succeeded.count) operations", color: Palette.success)
                    StatTile(title: "This session", bytes: model.freedThisSession, caption: "since launch", color: Palette.accent)
                    StatTile(title: "Skipped", bytes: 0,
                             caption: "\(model.history.count - succeeded.count) blocked or failed", color: Palette.warning)
                }
                chartPanel

                if model.history.isEmpty {
                    EmptyStateView(symbol: "list.bullet.rectangle", title: "No activity yet",
                                   message: "Operations appear here after you clean something.") { EmptyView() }
                        .frame(height: 260)
                }

                ForEach(days, id: \.0) { day, entries in
                    VStack(spacing: 0) {
                        HStack {
                            Text(day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                            Text("\(entries.count)").font(.mono(11)).foregroundStyle(Palette.textTertiary)
                            Spacer()
                            Text(entries.filter(\.success).reduce(0) { $0 + $1.bytes }.formattedBytes)
                                .font(.mono(12, weight: .medium)).foregroundStyle(Palette.success)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        ForEach(entries.prefix(200)) { entry in
                            Rectangle().fill(Palette.border).frame(height: 1)
                            HistoryRow(entry: entry)
                        }
                    }
                    .panel()
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .onAppear { model.loadHistory() }
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Reclaimed per day", subtitle: "last 30 days")
            if perDay.isEmpty {
                Text("No data yet").font(.system(size: 12.5)).foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(perDay) { bar in
                    BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Bytes", Double(bar.bytes)))
                        .foregroundStyle(Palette.success.opacity(0.85))
                        .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Palette.border)
                        AxisValueLabel {
                            if let d = value.as(Double.self) { Text(d == 0 ? "0" : Int64(d).formattedBytes) }
                        }
                        .font(.mono(10)).foregroundStyle(Palette.textTertiary)
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(18)
        .panel()
    }
}

struct HistoryRow: View {
    let entry: LogEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(entry.success ? Palette.success : Palette.danger).frame(width: 6, height: 6)
            Text(entry.mode.rawValue)
                .font(.mono(10.5))
                .foregroundStyle(entry.mode == .permanent ? Palette.danger : Palette.textTertiary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(Finder.abbreviate(entry.path)).font(.mono(11.5)).foregroundStyle(Palette.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(entry.message ?? "\(entry.source)\(entry.rule.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.bytes.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                .frame(width: 80, alignment: .trailing)
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.mono(11)).foregroundStyle(Palette.textTertiary).frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(hovering ? Color.white.opacity(0.025) : .clear)
        .onHover { hovering = $0 }
    }
}
