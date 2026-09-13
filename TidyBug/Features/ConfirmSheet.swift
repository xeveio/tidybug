import SwiftUI
import TidyBugCore

/// Review sheet shown before anything is removed. Runs a dry run through the
/// safety guard first so blocked paths are visible up front.
struct ConfirmSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: ConfirmRequest

    struct Blocked: Identifiable {
        var id: String { item.id }
        let item: CleanItem
        let reason: String
    }

    @State private var blocked: [Blocked] = []
    @State private var checked = false
    @State private var working = false

    private var blockedIDs: Set<String> { Set(blocked.map(\.id)) }
    private var effectiveBytes: Int64 {
        request.items.filter { !blockedIDs.contains($0.id) }.reduce(request.extraBytes) { $0 + $1.size }
    }
    private var effectiveCount: Int { request.items.count - blocked.count + request.commands.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(request.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                HStack(spacing: 6) {
                    Image(systemName: modeSymbol).font(.system(size: 11, weight: .semibold))
                    Text(modeText)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(request.permanent ? Palette.danger : Palette.textSecondary)
            }
            .padding(20)

            Rectangle().fill(Palette.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(request.commands, id: \.display) { command in
                        HStack(spacing: 10) {
                            Text("$").font(.mono(12)).foregroundStyle(Palette.textTertiary)
                            Text(command.display).font(.mono(12)).foregroundStyle(Palette.text)
                            Spacer()
                        }
                        .padding(.horizontal, 20).padding(.vertical, 7)
                    }
                    ForEach(request.items) { item in
                        let reason = blocked.first { $0.id == item.id }?.reason
                        HStack(spacing: 10) {
                            FileIcon(path: item.url.path, size: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Finder.abbreviate(item.url.path))
                                    .font(.mono(11.5)).foregroundStyle(reason != nil ? Palette.textTertiary : Palette.text)
                                    .strikethrough(reason != nil)
                                    .lineLimit(1).truncationMode(.middle)
                                if let reason {
                                    Label(reason, systemImage: "lock.fill")
                                        .font(.system(size: 11)).foregroundStyle(Palette.warning).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(item.size.formattedBytes).font(.mono(11.5)).foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 320)
            .background(Palette.sunken)

            Rectangle().fill(Palette.border).frame(height: 1)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    BytesText(bytes: effectiveBytes).font(.mono(15, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(footerNote).font(.system(size: 11.5)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.tidySecondary)
                Button {
                    working = true
                    Task {
                        await request.perform()
                        dismiss()
                    }
                } label: {
                    if working {
                        ProgressView().controlSize(.small).tint(.white).padding(.horizontal, 18)
                    } else {
                        Text(confirmText)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(request.permanent ? .tidyDanger : .tidy)
                .disabled(working || !checked || (effectiveBytes == 0 && request.commands.isEmpty
                                                  && request.items.count == blocked.count))
            }
            .padding(16)
        }
        .frame(width: 600)
        .background(Palette.surface)
        .preferredColorScheme(.dark)
        .task {
            let preview = await Cleaner.remove(request.items, source: "preview", dryRun: true,
                                               guard: request.safetyGuard ?? model.safetyGuard)
            blocked = preview.failures.map { Blocked(item: $0.item, reason: $0.reason) }
            checked = true
        }
    }

    private var modeSymbol: String {
        if request.items.isEmpty { return "terminal" }
        return request.permanent ? "exclamationmark.triangle.fill" : "trash"
    }

    private var modeText: String {
        if request.items.isEmpty { return "Runs the command below. Output is written to the activity log." }
        return request.permanent
            ? "Some items are deleted permanently and cannot be recovered."
            : "Items are moved to the Trash and can be restored until it is emptied."
    }

    private var footerNote: String {
        var s = "\(effectiveCount) item\(effectiveCount == 1 ? "" : "s")"
        if !blocked.isEmpty { s += " · \(blocked.count) blocked by safety checks" }
        return s
    }

    private var confirmText: String {
        if request.items.isEmpty { return "Run" }
        return request.permanent ? "Delete Permanently" : "Move to Trash"
    }
}
