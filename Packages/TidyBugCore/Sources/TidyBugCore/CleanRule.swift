import Foundation

public enum SafetyLevel: String, Codable, Sendable, CaseIterable, Comparable {
    /// Regenerable — preselected.
    case safe
    /// User decides item by item — never preselected.
    case review
    /// Shown with guidance only; TidyBug never deletes these files.
    case advisor

    public static func < (a: Self, b: Self) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }

    public var label: String {
        switch self {
        case .safe: "Safe to clean"
        case .review: "Review"
        case .advisor: "Advice"
        }
    }
}

public enum RuleGroup: String, Sendable, CaseIterable {
    case system = "System & Apps"
    case developer = "Developer"
    case files = "Files"
    case heavy = "Heavy Hitters"

    public var symbol: String {
        switch self {
        case .system: "macwindow"
        case .developer: "hammer.fill"
        case .files: "doc.on.doc.fill"
        case .heavy: "scalemass.fill"
        }
    }
}

/// A CLI-based clean (e.g. `brew cleanup`), used instead of trashing files.
public struct CommandAction: Sendable {
    public let title: String
    public let tool: String
    public let arguments: [String]

    public var display: String { ([tool] + arguments).joined(separator: " ") }
}

public struct CleanRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    /// Hue 0...1 for the category tint.
    public let hue: Double
    public let group: RuleGroup
    public let safety: SafetyLevel
    /// Items may be deleted permanently (skipping the Trash) — only regenerable data.
    public let allowsPermanent: Bool
    /// Items can only be deleted permanently (e.g. emptying the Trash).
    public let permanentOnly: Bool
    public let advice: String?
    /// App / Settings pane to open for advisor rules.
    public let openURL: URL?
    public let command: CommandAction?
    public let requiredTool: String?
    let locate: @Sendable () -> [URL]
    /// Optional extra size source (e.g. `docker system df` reclaimable).
    let probe: (@Sendable () -> (bytes: Int64, note: String)?)?

    init(id: String, title: String, detail: String, symbol: String, hue: Double, group: RuleGroup,
         safety: SafetyLevel, allowsPermanent: Bool = false, permanentOnly: Bool = false,
         advice: String? = nil, openURL: URL? = nil, command: CommandAction? = nil,
         requiredTool: String? = nil,
         locate: @escaping @Sendable () -> [URL],
         probe: (@Sendable () -> (bytes: Int64, note: String)?)? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.symbol = symbol; self.hue = hue
        self.group = group; self.safety = safety; self.allowsPermanent = allowsPermanent
        self.permanentOnly = permanentOnly; self.advice = advice; self.openURL = openURL
        self.command = command; self.requiredTool = requiredTool; self.locate = locate; self.probe = probe
    }

    public var isCommandBased: Bool { command != nil && safety != .advisor }
}

public struct RuleResult: Sendable, Identifiable {
    public var id: String { rule.id }
    public let rule: CleanRule
    public var items: [CleanItem]
    public var probeBytes: Int64?
    public var probeNote: String?
    public var available = true

    public var total: Int64 {
        if let probeBytes, rule.isCommandBased || rule.safety == .advisor, items.isEmpty { return probeBytes }
        return items.reduce(0) { $0 + $1.size }
    }
}

public enum ScanEngine {
    /// Scan rules concurrently, reporting each result as soon as it is ready.
    public static func scan(_ rules: [CleanRule] = BuiltinRules.all,
                            onResult: @escaping @Sendable (RuleResult) -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for rule in rules {
                group.addTask(priority: .utility) {
                    let result = scan(rule)
                    if !Task.isCancelled { onResult(result) }
                }
            }
        }
    }

    public static func scan(_ rule: CleanRule) -> RuleResult {
        if let tool = rule.requiredTool, !CommandRunner.isAvailable(tool) {
            return RuleResult(rule: rule, items: [], available: false)
        }
        let sizer = Sizer()
        var items: [CleanItem] = []
        for url in rule.locate() {
            if Task.isCancelled { break }
            let r = sizer.measure(url.path, inspect: rule.safety == .review)
            guard r.bytes > 0 else { continue }
            items.append(CleanItem(url: url, size: r.bytes, modified: r.newest == .distantPast ? nil : r.newest,
                                   containsData: r.containsData, containsProtected: r.containsProtected))
        }
        items.sort { $0.size > $1.size }
        let probe = rule.probe?()
        return RuleResult(rule: rule, items: items, probeBytes: probe?.bytes, probeNote: probe?.note)
    }

    /// Run a command-based rule (brew cleanup, simctl delete unavailable...).
    public static func runCommand(for rule: CleanRule, estimatedBytes: Int64) async -> CommandResult {
        guard let command = rule.command else { return CommandResult(status: 1, output: "No command") }
        let result = await CommandRunner.run(command.tool, command.arguments)
        OperationLog.shared.record([LogEntry(date: Date(), source: "smart-clean", rule: rule.id,
                                             path: command.display, bytes: result.succeeded ? estimatedBytes : 0,
                                             mode: .command, success: result.succeeded,
                                             message: String(result.output.suffix(500)))])
        return result
    }
}
