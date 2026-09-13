import CoreServices
import Foundation
import Security

/// An installed application bundle that TidyBug may offer to uninstall.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    /// Allocated size in bytes; -1 until measured.
    public var size: Int64
    public let lastUsed: Date?
    public let isAppStore: Bool

    public init(url: URL, name: String, bundleID: String?, version: String?, size: Int64 = -1,
                lastUsed: Date? = nil, isAppStore: Bool = false) {
        self.url = url
        self.name = name
        self.bundleID = bundleID
        self.version = version
        self.size = size
        self.lastUsed = lastUsed
        self.isAppStore = isAppStore
    }

    public var isSized: Bool { size >= 0 }
}

public enum AppInventory {
    public static var defaultRoots: [String] { ["/Applications", NSHomeDirectory() + "/Applications"] }

    /// Apple apps that users install (and may remove) themselves.
    static let appleAllowlist: Set<String> = [
        "com.apple.dt.Xcode", "com.apple.iWork.Pages", "com.apple.iWork.Keynote", "com.apple.iWork.Numbers",
        "com.apple.garageband10", "com.apple.iMovieApp", "com.apple.FinalCut", "com.apple.logic10",
        "com.apple.mainstage3", "com.apple.Compressor", "com.apple.motionapp", "com.apple.configurator.ui",
        "com.apple.developer.securitypolicy", "com.apple.TestFlight", "com.apple.dt.CreateMLApp",
    ]

    /// `.app` bundles directly in `root`, plus one level into folders such as
    /// Utilities or vendor directories ("Adobe Photoshop 2024/…").
    public static func bundleURLs(in root: String) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") {
            let url = URL(fileURLWithPath: root).appendingPathComponent(name)
            if name.hasSuffix(".app") {
                out.append(url)
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            for inner in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where inner.hasSuffix(".app") {
                out.append(url.appendingPathComponent(inner))
            }
        }
        return out
    }

    /// System apps are never offered: anything that resolves into /System, and
    /// Apple bundle ids outside a small allowlist of user-installable apps.
    public static func isSystemApp(url: URL, bundleID: String?) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        if resolved.hasPrefix("/System/") { return true }
        if let id = bundleID, id.hasPrefix("com.apple."), !appleAllowlist.contains(id) { return true }
        return false
    }

    /// Reads bundle metadata. Returns nil for system apps or unreadable bundles.
    public static func info(for url: URL) -> InstalledApp? {
        let dict = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let bundleID = dict["CFBundleIdentifier"] as? String
        guard !isSystemApp(url: url, bundleID: bundleID) else { return nil }
        let version = (dict["CFBundleShortVersionString"] as? String) ?? (dict["CFBundleVersion"] as? String)
        let isMAS = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        return InstalledApp(url: url, name: url.deletingPathExtension().lastPathComponent, bundleID: bundleID,
                            version: version, lastUsed: lastUsedDate(url), isAppStore: isMAS)
    }

    /// Spotlight's last-used date, falling back to the bundle's access date.
    public static func lastUsedDate(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date {
            return date
        }
        return (try? url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
    }

    /// Lists apps without measuring them (fast). Duplicates via symlinks are dropped.
    public static func list(roots: [String] = defaultRoots) -> [InstalledApp] {
        var seen = Set<String>()
        var apps: [InstalledApp] = []
        for root in roots {
            for url in bundleURLs(in: root) {
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted, let app = info(for: url) else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Code-signing team identifier (e.g. "UBF8T346G9"), used to tell whether a
    /// shared group container still belongs to another installed app.
    public static func teamIdentifier(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
