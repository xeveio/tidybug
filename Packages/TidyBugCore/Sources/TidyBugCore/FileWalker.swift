import Darwin
import Foundation

/// Identity of an on-disk file, used to count hardlinked files once
/// (pnpm stores hardlink the same bytes into many `node_modules`).
public struct FileID: Hashable, Sendable {
    public let dev: Int32
    public let ino: UInt64
}

/// A single entry yielded by `FileWalker`. Backed by the live `FTSENT`, so it
/// is only valid inside the visit closure; string properties are computed lazily.
public struct WalkEntry {
    public enum Kind { case file, directory, directoryEnd, symlink, other, unreadable }

    fileprivate let ent: UnsafeMutablePointer<FTSENT>
    public let kind: Kind

    public var level: Int { Int(ent.pointee.fts_level) }
    public var path: String { String(cString: ent.pointee.fts_path) }

    public var name: String {
        let raw = UnsafeRawPointer(ent).advanced(by: FileWalker.nameOffset)
        return String(cString: raw.assumingMemoryBound(to: CChar.self))
    }

    private var stat: UnsafeMutablePointer<Darwin.stat>? {
        kind == .unreadable ? nil : ent.pointee.fts_statp
    }

    /// Bytes actually allocated on disk (what deleting frees).
    public var allocatedSize: Int64 { stat.map { Int64($0.pointee.st_blocks) * 512 } ?? 0 }
    public var linkCount: Int { stat.map { Int($0.pointee.st_nlink) } ?? 1 }
    public var fileID: FileID {
        stat.map { FileID(dev: $0.pointee.st_dev, ino: $0.pointee.st_ino) } ?? FileID(dev: 0, ino: 0)
    }
    public var modified: Date {
        Date(timeIntervalSince1970: TimeInterval(stat?.pointee.st_mtimespec.tv_sec ?? 0))
    }
    public var accessed: Date {
        Date(timeIntervalSince1970: TimeInterval(stat?.pointee.st_atimespec.tv_sec ?? 0))
    }
}

public enum WalkDecision { case proceed, skipChildren, stop }

/// Thin, fast wrapper over BSD `fts(3)`. Never follows symlinks and never
/// crosses onto another volume.
public enum FileWalker {
    static let nameOffset = MemoryLayout<FTSENT>.offset(of: \FTSENT.fts_name)!

    public static func walk(_ root: String, _ visit: (WalkEntry) -> WalkDecision) {
        guard let cRoot = strdup(root) else { return }
        defer { free(cRoot) }
        let argv: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        let options = FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV
        guard let fts = argv.withUnsafeBufferPointer({ fts_open($0.baseAddress, options, nil) }) else { return }
        defer { fts_close(fts) }

        while let ent = fts_read(fts) {
            let kind: WalkEntry.Kind
            switch Int32(ent.pointee.fts_info) {
            case FTS_D: kind = .directory
            case FTS_DP: kind = .directoryEnd
            case FTS_F: kind = .file
            case FTS_SL, FTS_SLNONE: kind = .symlink
            case FTS_DNR, FTS_ERR, FTS_NS: kind = .unreadable
            default: kind = .other
            }
            switch visit(WalkEntry(ent: ent, kind: kind)) {
            case .proceed: break
            case .skipChildren: fts_set(fts, ent, FTS_SKIP)
            case .stop: return
            }
        }
    }
}
