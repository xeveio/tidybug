import SwiftUI
import TidyBugCore

/// Window-wide drop zone. Drag files or folders here from any view (or Finder),
/// review the total, then Delete All moves everything to the Trash at once.
struct CollectorStrip: View {
    @Environment(AppModel.self) private var model
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(targeted ? Palette.accent : Palette.border)
                .frame(height: targeted ? 2 : 1)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(targeted ? Palette.accentMuted : Palette.raised)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(targeted ? Palette.accent.opacity(0.5) : Palette.border))
                    Image(systemName: targeted ? "tray.and.arrow.down.fill" : (model.staged.isEmpty ? "tray" : "tray.full.fill"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(targeted || !model.staged.isEmpty ? Palette.accent : Palette.textSecondary)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: model.staged.count)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Collector").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(model.stagingNotice != nil ? Palette.warning : Palette.textTertiary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(width: model.staged.isEmpty ? nil : 150, alignment: .leading)

                if model.staged.isEmpty {
                    Spacer()
                    if targeted {
                        Text("Release to add").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                            .transition(.opacity)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.staged) { item in
                                StagedChip(item: item)
                                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                                            removal: .scale(scale: 0.6).combined(with: .opacity)))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))

                    HStack(spacing: 8) {
                        if model.isMeasuringStaged { ProgressView().controlSize(.mini) }
                        BytesText(bytes: model.stagedTotal)
                            .font(.mono(13, weight: .semibold))
                            .foregroundStyle(Palette.text)
                    }
                    Button("Clear") { model.clearStaged() }
                        .buttonStyle(.tidyQuiet)
                    Button {
                        model.requestDeleteStaged()
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                    .buttonStyle(.tidyDanger)
                    .disabled(model.isMeasuringStaged)
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                    .help("Move everything in the Collector to the Trash (⇧⌘⌫)")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(targeted ? Palette.accent.opacity(0.06) : Palette.surface.opacity(0.94))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.stage(urls: urls, source: "drop")
            return !urls.isEmpty
        } isTargeted: { targeted = $0 }
        .animation(.tidy, value: targeted)
        .animation(.tidy, value: model.staged.isEmpty)
        .animation(.tidy, value: model.stagingNotice)
    }

    private var subtitle: String {
        if let notice = model.stagingNotice { return notice }
        if model.staged.isEmpty { return "Drag files or folders here from any view or from Finder" }
        return "\(model.staged.count) item\(model.staged.count == 1 ? "" : "s") ready to delete"
    }
}

struct StagedChip: View {
    @Environment(AppModel.self) private var model
    let item: AppModel.StagedItem
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            FileIcon(path: item.url.path, size: 14)
            Text(item.name).font(.system(size: 11.5)).foregroundStyle(Palette.text).lineLimit(1)
            if let size = item.size {
                Text(size.formattedBytes).font(.mono(10.5)).foregroundStyle(Palette.textSecondary)
            } else {
                ProgressView().controlSize(.mini)
            }
            Button { model.unstage(item) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(hovering ? Palette.text : Palette.textTertiary)
        }
        .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 5)
        .paperCapsule()
        .onHover { hovering = $0 }
        .help(Finder.abbreviate(item.url.path))
        .contextMenu {
            Button("Reveal in Finder") { Finder.reveal(item.url) }
            Button("Remove from Collector") { model.unstage(item) }
        }
        .draggable(item.url)
    }
}
