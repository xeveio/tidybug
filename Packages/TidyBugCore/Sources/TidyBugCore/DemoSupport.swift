import Foundation

// Public constructors used by the app's DEBUG-only demo mode (marketing
// screenshots with synthetic data). Additive only: scanning code keeps using
// the internal memberwise initializers.

public extension RuleResult {
    init(rule: CleanRule, items: [CleanItem], probeBytes: Int64? = nil, probeNote: String? = nil) {
        self.rule = rule
        self.items = items
        self.probeBytes = probeBytes
        self.probeNote = probeNote
        self.available = true
    }
}

public extension ProjectArtifact {
    static func make(item: CleanItem, kind: String, projectName: String, projectPath: String,
                     projectModified: Date, reinstallable: Bool) -> ProjectArtifact {
        ProjectArtifact(item: item, kind: kind, projectName: projectName, projectPath: projectPath,
                        projectModified: projectModified, reinstallable: reinstallable)
    }
}

public extension LargeFile {
    init(item: CleanItem, accessed: Date) {
        self.item = item
        self.accessed = accessed
        self.kind = LargeFile.kind(for: item.url.pathExtension.lowercased())
    }
}

public extension LogEntry {
    init(date: Date, source: String, rule: String? = nil, path: String, bytes: Int64,
         mode: DeletionMode, success: Bool = true, message: String? = nil) {
        self.date = date
        self.source = source
        self.rule = rule
        self.path = path
        self.bytes = bytes
        self.mode = mode
        self.success = success
        self.message = message
    }
}

public extension VolumeInfo {
    static func make(total: Int64, available: Int64) -> VolumeInfo {
        VolumeInfo(total: total, available: available)
    }
}

public extension OrphanLeftover {
    static func make(url: URL, category: String, bundleID: String, size: Int64) -> OrphanLeftover {
        OrphanLeftover(url: url, category: category, bundleID: bundleID, size: size)
    }
}

public extension DiskNode {
    /// Builds a node for synthetic trees. Sizes are taken as given.
    static func make(name: String, path: String, isDirectory: Bool, size: Int64, fileCount: Int = 1,
                     isAggregate: Bool = false) -> DiskNode {
        DiskNode(name: name, path: path, isDirectory: isDirectory, isAggregate: isAggregate,
                 size: size, fileCount: fileCount)
    }

    /// Appends a child (keeps children sorted by size, largest first).
    func append(_ child: DiskNode) {
        child.parent = self
        children.append(child)
        children.sort { $0.size > $1.size }
    }
}

#if DEBUG
public enum DemoOverrides {
    /// When set, `VolumeInfo.current()` returns this instead of the real volume.
    nonisolated(unsafe) public static var volume: VolumeInfo?
    /// When set, `OperationLog.entries()` returns these instead of reading the log.
    nonisolated(unsafe) public static var logEntries: [LogEntry]?
}
#endif
