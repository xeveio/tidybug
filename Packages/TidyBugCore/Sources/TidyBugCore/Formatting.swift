import Foundation

public extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

public struct VolumeInfo: Sendable, Equatable {
    public let total: Int64
    public let available: Int64
    public var used: Int64 { total - available }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func current(path: String = NSHomeDirectory()) -> VolumeInfo {
        #if DEBUG
        if let demo = DemoOverrides.volume { return demo }
        #endif
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                       .volumeAvailableCapacityForImportantUsageKey])
        return VolumeInfo(total: Int64(values?.volumeTotalCapacity ?? 0),
                          available: values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

enum Paths {
    static var home: String { NSHomeDirectory() }
    static func h(_ rel: String) -> String { "\(home)/\(rel)" }

    static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    static func children(of dir: String, excluding: Set<String> = [], hidden: Bool = true) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names
            .filter { !excluding.contains($0) && $0 != ".DS_Store" && (hidden || !$0.hasPrefix(".")) }
            .map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
    }

    static func existing(_ paths: [String]) -> [URL] {
        paths.filter(exists).map { URL(fileURLWithPath: $0) }
    }
}

/// Parses human-readable sizes like `3.1GB`, `512MB`, `1.2kB` (docker output).
func parseSize(_ text: String) -> Int64? {
    let s = text.trimmingCharacters(in: .whitespaces)
    let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
    for (suffix, mult) in units where s.hasSuffix(suffix) {
        guard let v = Double(s.dropLast(suffix.count)) else { return nil }
        return Int64(v * mult)
    }
    return nil
}
