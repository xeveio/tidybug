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
        var timedOut = false
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            // SIGTERM, then SIGKILL if the process ignores it.
            timedOut = true
            process.terminate()
            let grace = Date().addingTimeInterval(2)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        // Never block here: a grandchild that inherited the pipe can keep it open
        // indefinitely, so only drain what is already buffered.
        output.append(Self.drainNonBlocking(pipe.fileHandleForReading))
        try? pipe.fileHandleForReading.close()
        if timedOut { output.append(Data("\n[timed out after \(Int(timeout))s]".utf8)) }
        return CommandResult(status: timedOut ? 124 : process.terminationStatus, output: output.string)
    }

    private static func drainNonBlocking(_ handle: FileHandle) -> Data {
        let fd = handle.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n > 0 { data.append(buffer, count: n) } else { break }
        }
        return data
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
