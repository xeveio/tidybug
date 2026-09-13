import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public var succeeded: Bool { status == 0 }
}

/// Runs developer CLIs (brew, docker, xcrun). GUI apps get a minimal PATH, so
/// tools are resolved against the usual install locations.
public enum CommandRunner {
    static var searchPaths: [String] {
        let home = NSHomeDirectory()
        return ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "\(home)/.orbstack/bin",
                "\(home)/.local/bin", "\(home)/.docker/bin", "/Applications/OrbStack.app/Contents/MacOS/xbin"]
    }

    public static func resolve(_ tool: String) -> String? {
        if tool.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil }
        return searchPaths.lazy.map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func isAvailable(_ tool: String) -> Bool { resolve(tool) != nil }

    /// Blocking run; call from a background context.
    public static func runSync(_ tool: String, _ arguments: [String], timeout: TimeInterval = 600) -> CommandResult {
        guard let exe = resolve(tool) else { return CommandResult(status: 127, output: "\(tool) not found") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let output = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { h in output.append(h.availableData) }
        do { try process.run() } catch {
            return CommandResult(status: 126, output: error.localizedDescription)
        }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline { process.terminate(); break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        output.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return CommandResult(status: process.terminationStatus, output: output.string)
    }

    public static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 600) async -> CommandResult {
        await Task.detached(priority: .utility) { runSync(tool, arguments, timeout: timeout) }.value
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
