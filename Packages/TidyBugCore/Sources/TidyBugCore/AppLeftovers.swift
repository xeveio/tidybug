import Foundation

/// A file or folder in ~/Library that belongs to a specific app.
public struct AppLeftover: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: String
    public var size: Int64

    public init(url: URL, category: String, size: Int64) {
        self.url = url
        self.category = category
        self.size = size
    }
}

/// Library data named after a bundle id whose app is no longer installed.
public struct OrphanLeftover: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let category: String
    public let bundleID: String
    public var size: Int64

    /// Best guess at the app's name from its bundle id ("com.spotify.client" → "Spotify").
    public var probableAppName: String {
        let parts = bundleID.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return bundleID }
        let generic: Set<String> = ["client", "app", "mac", "macos", "desktop", "osx", "helper", "agent",
                                    "com", "net", "org", "io", "network", "cache", "caches"]
        let pick = parts.count >= 3 && !generic.contains(parts[2].lowercased()) ? parts[2] : parts[1]
        return pick.prefix(1).uppercased() + pick.dropFirst()
    }
}

/// Finds an app's leftovers in a Library folder. The Library root is
/// injectable so the matching rules can be tested against a temp directory.
public struct LeftoverFinder: Sendable {
    public let library: URL

    public init(library: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")) {
        self.library = library
    }

    // MARK: Leftovers of one app

    /// Everything tied to one app, by bundle id and exact app name.
    /// - Parameters:
    ///   - otherBundleIDs: bundle ids of the *other* installed apps; a vendor
    ///     folder (e.g. "Application Support/Google") is only included when no
    ///     other installed app shares the vendor.
    ///   - teamID / otherTeamIDs: group containers prefixed with the team id are
    ///     only included when no other installed app is signed by that team.
    public func leftovers(bundleID: String?, appName: String, appPath: String? = nil, teamID: String? = nil,
                          otherBundleIDs: Set<String> = [], otherTeamIDs: Set<String> = [],
                          measure: Bool = true) -> [AppLeftover] {
        let fm = FileManager.default
        var found: [(URL, String)] = []
        var paths = Set<String>()

        func add(_ url: URL, _ category: String) {
            guard fm.fileExists(atPath: url.path), paths.insert(url.path).inserted else { return }
            found.append((url, category))
        }
        func add(_ rel: String, _ category: String) { add(library.appendingPathComponent(rel), category) }
        func children(_ rel: String) -> [String] {
            (try? fm.contentsOfDirectory(atPath: library.appendingPathComponent(rel).path)) ?? []
        }

        if let b = bundleID, !b.isEmpty {
            add("Application Support/\(b)", "Application Support")
            add("Caches/\(b)", "Caches")
            add("Preferences/\(b).plist", "Preferences")
            for name in children("Preferences/ByHost") where name.hasPrefix(b + ".") && name.hasSuffix(".plist") {
                add("Preferences/ByHost/\(name)", "Preferences")
            }
            add("Containers/\(b)", "Container")
            for name in children("Group Containers") {
                let ownsByID = name == b || name.hasSuffix("." + b)
                let ownsByTeam = teamID.map { !otherTeamIDs.contains($0) && name.hasPrefix($0 + ".") } ?? false
                if ownsByID || ownsByTeam { add("Group Containers/\(name)", "Group Container") }
            }
            add("Saved Application State/\(b).savedState", "Saved State")
            add("Logs/\(b)", "Logs")
            add("HTTPStorages/\(b)", "HTTP Storage")
            add("HTTPStorages/\(b).binarycookies", "HTTP Storage")
            add("WebKit/\(b)", "WebKit")
            add("Cookies/\(b).binarycookies", "Cookies")
            add("Application Scripts/\(b)", "Scripts")

            // Launch agents that name the bundle id or point into the app bundle.
            for name in children("LaunchAgents") where name.hasSuffix(".plist") {
                let url = library.appendingPathComponent("LaunchAgents/\(name)")
                if name.contains(b) || launchAgent(url, references: appPath) { add(url, "Launch Agent") }
            }

            // Vendor folder ("com.google.Chrome" → "Google"), only when no other app shares it.
            let parts = b.split(separator: ".").map { $0.lowercased() }
            if parts.count >= 3 {
                let vendor = parts[1]
                let shared = otherBundleIDs.contains { other in
                    let o = other.split(separator: ".").map { $0.lowercased() }
                    return o.count >= 2 && o[1] == vendor
                }
                if !shared {
                    for dir in ["Application Support", "Caches"] {
                        for name in children(dir) where name.lowercased() == vendor {
                            add("\(dir)/\(name)", dir)
                        }
                    }
                }
            }
        }

        // Exact app-name folders only, to avoid false positives.
        let name = appName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            add("Application Support/\(name)", "Application Support")
            add("Caches/\(name)", "Caches")
            add("Logs/\(name)", "Logs")
        }

        let sizer = Sizer(isCancelled: { false })
        return found.map { url, category in
            AppLeftover(url: url, category: category, size: measure ? sizer.measure(url.path).bytes : 0)
        }
    }

    private func launchAgent(_ url: URL, references appPath: String?) -> Bool {
        guard let appPath, let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return false }
        if let program = dict["Program"] as? String, program.hasPrefix(appPath) { return true }
        if let args = dict["ProgramArguments"] as? [String], args.contains(where: { $0.hasPrefix(appPath) }) { return true }
        return false
    }

    // MARK: Orphans

    /// Library entries named after a bundle id whose app is not installed.
    /// `isInstalled` decides installation (the app layer asks Launch Services).
    public func orphans(isInstalled: (String) -> Bool, measure: Bool = true) -> [OrphanLeftover] {
        let fm = FileManager.default
        let sources: [(dir: String, category: String, suffix: String)] = [
            ("Containers", "Container", ""),
            ("Saved Application State", "Saved State", ".savedState"),
            ("Preferences", "Preferences", ".plist"),
            ("Caches", "Caches", ""),
        ]
        let sizer = Sizer(isCancelled: { false })
        var out: [OrphanLeftover] = []
        for source in sources {
            let dir = library.appendingPathComponent(source.dir)
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                guard source.suffix.isEmpty || name.hasSuffix(source.suffix) else { continue }
                let id = source.suffix.isEmpty ? name : String(name.dropLast(source.suffix.count))
                guard Self.looksLikeBundleID(id), !Self.isSystemIdentifier(id), !isInstalled(id) else { continue }
                let url = dir.appendingPathComponent(name)
                out.append(OrphanLeftover(url: url, category: source.category, bundleID: id,
                                          size: measure ? sizer.measure(url.path).bytes : 0))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// Reverse-DNS shape: at least three dot-separated parts, a short lowercase first part.
    public static func looksLikeBundleID(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let first = parts[0]
        guard (2...6).contains(first.count), first.allSatisfy({ $0.isLowercase && $0.isLetter }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    /// Apple, system and developer-toolchain identifiers are never reported as
    /// orphans (e.g. SwiftPM's cache belongs to a command-line tool, not an app).
    public static func isSystemIdentifier(_ id: String) -> Bool {
        let lower = id.lowercased()
        let prefixes = ["com.apple.", "group.", "systemgroup.", "com.tidybug.", "com.xeve.tidybug",
                        "org.swift.", "org.llvm.", "com.github.xcodegen"]
        return prefixes.contains { lower.hasPrefix($0) } || lower.contains(".apple.")
    }

    /// Installation check against a set of installed bundle ids, treating helper
    /// and extension ids ("com.foo.App.Helper") as belonging to their app.
    public static func isInstalled(_ id: String, installed: Set<String>) -> Bool {
        let lower = id.lowercased()
        let set = Set(installed.map { $0.lowercased() })
        if set.contains(lower) { return true }
        return set.contains { lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }
    }
}
