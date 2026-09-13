import Foundation

/// Something the user can remove: a file or folder with a measured size.
public struct CleanItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public var name: String
    public var size: Int64
    public var modified: Date?
    public var note: String?
    public var containsData = false
    public var containsProtected = false

    public init(url: URL, name: String? = nil, size: Int64, modified: Date? = nil, note: String? = nil,
                containsData: Bool = false, containsProtected: Bool = false) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.modified = modified
        self.note = note
        self.containsData = containsData
        self.containsProtected = containsProtected
    }

    /// Items with release artifacts are never removable; data folders are
    /// removable but never preselected.
    public var isRemovable: Bool { !containsProtected }
}

public struct CleanOutcome: Sendable {
    public var freed: Int64 = 0
    public var removed: [CleanItem] = []
    public var failures: [(item: CleanItem, reason: String)] = []
    public var dryRun = false

    public init() {}

    public mutating func merge(_ other: CleanOutcome) {
        freed += other.freed
        removed += other.removed
        failures += other.failures
    }
}

public enum Cleaner {
    /// Trash (default) or permanently delete items after passing each through
    /// `SafetyGuard`. Every attempt is written to the operation log.
    public static func remove(
        _ items: [CleanItem],
        mode: DeletionMode = .trash,
        source: String,
        rule: String? = nil,
        dryRun: Bool = false,
        guard safety: SafetyGuard = SafetyGuard(),
        log: OperationLog = .shared
    ) async -> CleanOutcome {
        await Task.detached(priority: .userInitiated) {
            var outcome = CleanOutcome()
            outcome.dryRun = dryRun
            var entries: [LogEntry] = []
            let fm = FileManager.default
            for item in items {
                if Task.isCancelled { break }
                do {
                    guard item.isRemovable else { throw GuardError.protectedArtifact(item.url.path) }
                    try safety.validate(item.url)
                    if !dryRun {
                        switch mode {
                        case .trash: try fm.trashItem(at: item.url, resultingItemURL: nil)
                        case .permanent, .command: try fm.removeItem(at: item.url)
                        }
                    }
                    outcome.freed += item.size
                    outcome.removed.append(item)
                    if !dryRun {
                        entries.append(LogEntry(date: Date(), source: source, rule: rule, path: item.url.path,
                                                bytes: item.size, mode: mode, success: true, message: nil))
                    }
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    outcome.failures.append((item, reason))
                    if !dryRun {
                        entries.append(LogEntry(date: Date(), source: source, rule: rule, path: item.url.path,
                                                bytes: 0, mode: mode, success: false, message: reason))
                    }
                }
            }
            log.record(entries)
            return outcome
        }.value
    }
}
