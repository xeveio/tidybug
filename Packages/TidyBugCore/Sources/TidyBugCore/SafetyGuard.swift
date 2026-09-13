import Foundation

public enum GuardError: LocalizedError, Equatable {
    case outsideAllowedRoots(String)
    case protectedLocation(String)
    case protectedArtifact(String)
    case whitelisted(String)

    public var errorDescription: String? {
        switch self {
        case .outsideAllowedRoots(let p): "\(p) is outside the folders TidyBug may clean."
        case .protectedLocation(let p): "\(p) is a protected location."
        case .protectedArtifact(let p): "\(p) is a release artifact (archive / ipa) and is always kept."
        case .whitelisted(let p): "\(p) is on your protected list."
        }
    }
}

/// Last line of defence before anything is trashed or deleted.
public struct SafetyGuard: Sendable {
    public var home: String
    public var allowedRoots: [String]
    public var whitelist: [String]

    public init(home: String = NSHomeDirectory(), allowedRoots: [String]? = nil, whitelist: [String] = []) {
        let h = Self.normalize(home)
        self.home = h
        self.allowedRoots = (allowedRoots ?? [h]).map(Self.normalize)
        self.whitelist = whitelist.map(Self.normalize)
    }

    /// Folders that must never be removed themselves (their contents may be).
    var exactForbidden: Set<String> {
        let rel = ["", "Documents", "Desktop", "Downloads", "Library", "Library/Application Support",
                   "Library/Caches", "Library/Containers", "Library/Group Containers", "Library/Developer",
                   "Library/Preferences", "Library/Logs", "Pictures", "Movies", "Music", "Applications",
                   ".Trash", "Documents/GitHub", "Developer", "Projects", ".config", ".local"]
        return Set(rel.map { $0.isEmpty ? home : "\(home)/\($0)" })
    }

    /// Subtrees that are never touched.
    var forbiddenSubtrees: [String] {
        ["Library/Mobile Documents", "Library/Keychains", "Library/Messages", "Library/Mail",
         "Library/Photos", ".ssh", ".gnupg", ".secrets", ".aws", ".kube",
         "Library/CloudStorage"].map { "\(home)/\($0)" }
    }

    static let protectedComponents: Set<String> = ["build-archive", "build-export", ".git"]
    static let protectedSuffixes = [".xcarchive", ".ipa", ".photoslibrary", ".keychain-db"]

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Resolve symlinks in the *parent* (the item itself may be a symlink, in
    /// which case the link is removed, never its target).
    public func resolve(_ url: URL) -> String {
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return Self.normalize((parent as NSString).appendingPathComponent(url.lastPathComponent))
    }

    @discardableResult
    public func validate(_ url: URL) throws -> String {
        let path = resolve(url)
        let lowered = path.lowercased()

        guard allowedRoots.contains(where: { path.hasPrefix($0 + "/") }) else {
            throw GuardError.outsideAllowedRoots(path)
        }
        if exactForbidden.contains(path) { throw GuardError.protectedLocation(path) }
        if forbiddenSubtrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            throw GuardError.protectedLocation(path)
        }
        let components = path.split(separator: "/").map(String.init)
        if components.contains(where: { Self.protectedComponents.contains($0) }) {
            throw GuardError.protectedArtifact(path)
        }
        if components.contains(where: { c in Self.protectedSuffixes.contains { c.lowercased().hasSuffix($0) } }) {
            throw GuardError.protectedArtifact(path)
        }
        if whitelist.contains(where: { lowered == $0.lowercased() || lowered.hasPrefix($0.lowercased() + "/") }) {
            throw GuardError.whitelisted(path)
        }
        return path
    }

    public func isAllowed(_ url: URL) -> Bool { (try? validate(url)) != nil }
}
