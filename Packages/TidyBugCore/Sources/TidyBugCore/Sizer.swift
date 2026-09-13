import Foundation

public struct SizeResult: Sendable, Hashable {
    public var bytes: Int64 = 0
    public var files: Int = 0
    /// Contains a signed release artifact (.xcarchive / .ipa) — never auto-delete.
    public var containsProtected = false
    /// Contains extracted data (.db / .sqlite / .csv) — deselect by default.
    public var containsData = false
    public var newest: Date = .distantPast

    public init() {}
}

/// Hardlink-aware size measurement. Keep one `Sizer` per scan so a file
/// reachable from several folders is only counted once — `du` over-reports
/// pnpm-installed `node_modules` roughly 2x.
public final class Sizer {
    private var seen = Set<FileID>()
    private let isCancelled: () -> Bool

    public init(isCancelled: @escaping () -> Bool = { Task.isCancelled }) {
        self.isCancelled = isCancelled
    }

    static let dataExtensions: Set<String> = ["db", "sqlite", "sqlite3", "csv"]
    static let protectedExtensions: Set<String> = ["xcarchive", "ipa"]

    public func measure(_ path: String, inspect: Bool = false) -> SizeResult {
        var result = SizeResult()
        var counter = 0
        FileWalker.walk(path) { e in
            counter += 1
            if counter & 0x3FF == 0, isCancelled() { return .stop }
            switch e.kind {
            case .directoryEnd, .unreadable:
                return .proceed
            case .directory:
                result.bytes += e.allocatedSize
                if inspect, Self.protectedExtensions.contains(Self.ext(e.name)) {
                    result.containsProtected = true
                }
                return .proceed
            case .file, .symlink, .other:
                if e.linkCount > 1, !seen.insert(e.fileID).inserted { return .proceed }
                result.bytes += e.allocatedSize
                result.files += 1
                let m = e.modified
                if m > result.newest { result.newest = m }
                if inspect {
                    let x = Self.ext(e.name)
                    if Self.dataExtensions.contains(x) { result.containsData = true }
                    if Self.protectedExtensions.contains(x) { result.containsProtected = true }
                }
                return .proceed
            }
        }
        return result
    }

    static func ext(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}
