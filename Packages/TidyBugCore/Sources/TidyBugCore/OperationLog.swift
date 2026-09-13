import Foundation

public enum DeletionMode: String, Codable, Sendable {
    case trash, permanent, command
}

public struct LogEntry: Codable, Sendable, Identifiable, Hashable {
    public var id = UUID()
    public let date: Date
    public let source: String      // "smart-clean", "purge", "disk-map", "large-files", "menu-bar"
    public let rule: String?
    public let path: String
    public let bytes: Int64
    public let mode: DeletionMode
    public let success: Bool
    public let message: String?
}

/// Append-only JSONL log at ~/Library/Logs/TidyBug/operations.jsonl.
public final class OperationLog: @unchecked Sendable {
    public static let shared = OperationLog()

    public let url: URL
    private let lock = NSLock()

    public init(url: URL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/TidyBug/operations.jsonl")) {
        self.url = url
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func record(_ entries: [LogEntry]) {
        guard !entries.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        for entry in entries {
            if var line = try? Self.encoder.encode(entry) {
                line.append(0x0A)
                try? handle.write(contentsOf: line)
            }
        }
    }

    public func entries() -> [LogEntry] {
        #if DEBUG
        if let demo = DemoOverrides.logEntries { return demo }
        #endif
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(LogEntry.self, from: Data($0)) }
            .sorted { $0.date > $1.date }
    }
}
