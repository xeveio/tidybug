import Foundation

public struct LargeFile: Sendable, Identifiable, Hashable {
    public var id: String { item.id }
    public var item: CleanItem
    public let accessed: Date
    public let kind: Kind

    public enum Kind: String, Sendable, CaseIterable {
        case video = "Video", archive = "Archive", installer = "Installer", image = "Disk Image",
             document = "Document", data = "Data", other = "Other"
    }

    public var ageDays: Int {
        let ref = max(item.modified ?? .distantPast, accessed)
        return max(0, Int(Date().timeIntervalSince(ref) / 86_400))
    }

    static func kind(for ext: String) -> Kind {
        switch ext {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": .video
        case "zip", "tar", "gz", "tgz", "rar", "7z", "bz2", "xz", "zst": .archive
        case "pkg", "mpkg", "xip": .installer
        case "dmg", "iso", "img", "raw", "vmdk", "qcow2", "vdi": .image
        case "pdf", "psd", "key", "pptx", "docx", "sketch", "fig": .document
        case "sql", "db", "sqlite", "csv", "json", "log", "dump", "bak": .data
        default: .other
        }
    }
}

/// Walks a folder for files above a size threshold.
public enum LargeFileFinder {
    /// Folders that are handled elsewhere or must not be offered here.
    static let skip: Set<String> = [".git", "node_modules", ".Trash", "Library", ".photoslibrary"]

    public static func scan(
        root: String = NSHomeDirectory(),
        minimumSize: Int64 = 100 << 20,
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        progress: (String) -> Void = { _ in },
        found: (LargeFile) -> Void
    ) {
        let guardRail = SafetyGuard()
        var counter = 0
        FileWalker.walk(root) { e in
            counter += 1
            if counter & 0xFFF == 0 { if isCancelled() { return .stop }; progress(e.path) }
            switch e.kind {
            case .directory:
                let name = e.name
                if e.level > 0 && (skip.contains(name) || name.hasSuffix(".photoslibrary") || name.hasSuffix(".app")
                                   || name.hasSuffix(".xcarchive")) {
                    return .skipChildren
                }
            case .file:
                let size = e.allocatedSize
                guard size >= minimumSize else { return .proceed }
                let url = URL(fileURLWithPath: e.path)
                guard guardRail.isAllowed(url) else { return .proceed }
                found(LargeFile(item: CleanItem(url: url, size: size, modified: e.modified),
                                accessed: e.accessed, kind: LargeFile.kind(for: url.pathExtension.lowercased())))
            default: break
            }
            return .proceed
        }
    }
}
