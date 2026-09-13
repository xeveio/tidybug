import CryptoKit
import Darwin
import Foundation

public struct DuplicateFile: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let size: Int64
    public let modified: Date
    /// False for copies living somewhere we'd rather the user decide by hand
    /// (source repos, app bundles...). Never preselected.
    public let autoSelectable: Bool

    public init(url: URL, size: Int64, modified: Date, autoSelectable: Bool = true) {
        self.url = url
        self.size = size
        self.modified = modified
        self.autoSelectable = autoSelectable
    }

    public var name: String { url.lastPathComponent }
    public var item: CleanItem { CleanItem(url: url, size: size, modified: modified) }
}

public struct DuplicateGroup: Sendable, Identifiable, Hashable {
    public let id: String          // content hash
    public let size: Int64         // bytes per copy
    public let files: [DuplicateFile]
    public let keeperID: String

    public init(id: String, size: Int64, files: [DuplicateFile], keeperID: String) {
        self.id = id
        self.size = size
        self.files = files
        self.keeperID = keeperID
    }

    /// Same group without the given paths; nil once fewer than two copies remain.
    public func removing(_ paths: Set<String>) -> DuplicateGroup? {
        let left = files.filter { !paths.contains($0.id) }
        guard left.count > 1 else { return nil }
        let keeper = left.contains { $0.id == keeperID } ? keeperID : DuplicateFinder.chooseKeeper(left).id
        return DuplicateGroup(id: id, size: size, files: left, keeperID: keeper)
    }

    public var keeper: DuplicateFile { files.first { $0.id == keeperID } ?? files[0] }
    public var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
}

public struct DuplicateProgress: Sendable {
    public enum Phase: Sendable { case collecting, hashing, done }
    public var phase: Phase
    public var filesSeen: Int
    public var candidates: Int
    public var hashed: Int
    public var currentPath: String
}

/// Finds byte-identical files: size buckets → partial hash (first + last 64 KB)
/// → full streaming SHA-256 only where partial hashes collide.
public enum DuplicateFinder {
    public static var defaultRoots: [String] {
        ["Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music"]
            .map { "\(NSHomeDirectory())/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    static let skipNames: Set<String> = [".git", "node_modules", "Library", ".Trash", ".build", "DerivedData",
                                         "Pods", ".venv", "venv", ".next", ".cache", "build-archive", "build-export"]
    static let skipSuffixes = [".photoslibrary", ".app", ".xcarchive", ".bundle", ".framework", ".musiclibrary",
                               ".tvlibrary", ".imovielibrary", ".fcpbundle", ".xcodeproj", ".xcworkspace"]

    static func shouldSkip(directory name: String) -> Bool {
        skipNames.contains(name) || skipSuffixes.contains { name.hasSuffix($0) }
    }

    /// Collapse roots nested inside other roots.
    static func normalizedRoots(_ roots: [String]) -> [String] {
        let std = Set(roots.map { ($0 as NSString).standardizingPath }).sorted { $0.count < $1.count }
        var out: [String] = []
        for r in std where !out.contains(where: { r == $0 || r.hasPrefix($0 + "/") }) { out.append(r) }
        return out
    }

    public static func scan(
        roots: [String] = defaultRoots,
        minimumSize: Int64 = 1 << 20,
        guard safety: SafetyGuard = SafetyGuard(),
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        progress: (DuplicateProgress) -> Void = { _ in }
    ) -> [DuplicateGroup] {
        var bySize: [Int64: [(path: String, modified: Date)]] = [:]
        var seenIDs = Set<FileID>()
        var seen = 0
        var cancelled = false

        // 1. Collect candidate files, bucketed by logical size.
        for root in normalizedRoots(roots) {
            FileWalker.walk(root) { e in
                seen += 1
                if seen & 0x3FF == 0 {
                    if isCancelled() { cancelled = true; return .stop }
                    progress(DuplicateProgress(phase: .collecting, filesSeen: seen, candidates: 0, hashed: 0,
                                               currentPath: e.path))
                }
                switch e.kind {
                case .directory:
                    return e.level > 0 && shouldSkip(directory: e.name) ? .skipChildren : .proceed
                case .file:
                    // Allocated size is a cheap prefilter; logical size decides the bucket.
                    guard e.allocatedSize >= minimumSize / 2 else { return .proceed }
                    // Hardlinks to the same inode are one file, not duplicates.
                    guard seenIDs.insert(e.fileID).inserted else { return .proceed }
                    let path = e.path
                    var st = stat()
                    guard lstat(path, &st) == 0 else { return .proceed }
                    let size = Int64(st.st_size)
                    guard size >= minimumSize else { return .proceed }
                    bySize[size, default: []].append((path, e.modified))
                    return .proceed
                default:
                    return .proceed
                }
            }
            if cancelled { return [] }
        }

        let candidates = bySize.filter { $0.value.count > 1 }
        let total = candidates.values.reduce(0) { $0 + $1.count }
        var hashed = 0
        var groups: [DuplicateGroup] = []

        // 2 + 3. Partial hash, then full hash on collisions.
        for (size, files) in candidates.sorted(by: { $0.key > $1.key }) {
            if isCancelled() { return [] }
            var byPartial: [Data: [(path: String, modified: Date)]] = [:]
            for f in files {
                hashed += 1
                if let h = partialHash(f.path, size: size) { byPartial[h, default: []].append(f) }
            }
            progress(DuplicateProgress(phase: .hashing, filesSeen: seen, candidates: total, hashed: hashed,
                                       currentPath: files.first?.path ?? ""))
            for (_, sameStart) in byPartial where sameStart.count > 1 {
                var byFull: [Data: [(path: String, modified: Date)]] = [:]
                for f in sameStart {
                    if isCancelled() { return [] }
                    if let h = fullHash(f.path) { byFull[h, default: []].append(f) }
                }
                for (hash, same) in byFull where same.count > 1 {
                    let dupes = same.compactMap { f -> DuplicateFile? in
                        let url = URL(fileURLWithPath: f.path)
                        guard safety.isAllowed(url) else { return nil }
                        return DuplicateFile(url: url, size: size, modified: f.modified,
                                             autoSelectable: isAutoSelectable(f.path))
                    }
                    guard dupes.count > 1 else { continue }
                    let keeper = chooseKeeper(dupes)
                    groups.append(DuplicateGroup(id: hash.map { String(format: "%02x", $0) }.joined(),
                                                 size: size, files: sortedForDisplay(dupes, keeper: keeper),
                                                 keeperID: keeper.id))
                }
            }
        }
        progress(DuplicateProgress(phase: .done, filesSeen: seen, candidates: total, hashed: hashed, currentPath: ""))
        return groups.sorted { $0.wasted > $1.wasted }
    }

    // MARK: Keeper heuristic

    static let transientDirs = ["/Downloads/", "/Desktop/", "/tmp/", "/Caches/", "/.Trash/"]

    /// Prefer copies outside Downloads/Desktop, then the oldest (the original),
    /// then the shortest path, then alphabetical for stability.
    public static func chooseKeeper(_ files: [DuplicateFile]) -> DuplicateFile {
        files.min { a, b in
            let ta = isTransient(a.url.path), tb = isTransient(b.url.path)
            if ta != tb { return !ta }
            if a.modified != b.modified { return a.modified < b.modified }
            if a.url.path.count != b.url.path.count { return a.url.path.count < b.url.path.count }
            return a.url.path < b.url.path
        }!
    }

    static func isTransient(_ path: String) -> Bool {
        let p = path.lowercased()
        return transientDirs.contains { p.contains($0.lowercased()) } || p.contains("copy") || p.range(of: #" \(\d+\)\."#, options: .regularExpression) != nil
    }

    /// Source trees and bundles are for the user to decide, never preselected.
    static func isAutoSelectable(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let risky = ["\(home)/Documents/GitHub/", "\(home)/Developer/", "\(home)/Projects/"]
        return !risky.contains { path.hasPrefix($0) }
    }

    static func sortedForDisplay(_ files: [DuplicateFile], keeper: DuplicateFile) -> [DuplicateFile] {
        [keeper] + files.filter { $0.id != keeper.id }.sorted { $0.url.path < $1.url.path }
    }

    // MARK: Hashing

    static let partialChunk = 64 * 1024

    static func partialHash(_ path: String, size: Int64) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        guard let head = try? h.read(upToCount: partialChunk) else { return nil }
        hasher.update(data: head)
        if size > Int64(partialChunk * 2) {
            try? h.seek(toOffset: UInt64(size) - UInt64(partialChunk))
            if let tail = try? h.read(upToCount: partialChunk) { hasher.update(data: tail) }
        }
        return Data(hasher.finalize())
    }

    static func fullHash(_ path: String) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do { chunk = try autoreleasepool { try h.read(upToCount: 1 << 20) } } catch { return nil }
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return Data(hasher.finalize())
    }
}
