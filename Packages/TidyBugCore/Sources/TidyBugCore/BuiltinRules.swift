import Foundation

/// The rule catalog, distilled from the hand-run cleanup session of 2026-09-01
/// (106 GB freed) plus the usual developer-Mac suspects.
public enum BuiltinRules {
    public static var all: [CleanRule] {
        [derivedData, deviceSupport, simulatorCaches, unavailableSimulators, homebrew, devCaches,
         userCaches, userLogs, trash,
         installers, dbDumps, editorBackups, iosBackups, mailDownloads,
         docker, whatsapp, chrome, claudeVMs, timeMachine]
    }

    // Directories inside ~/Library/Caches that other rules own, or that should be left alone.
    static let cacheExclusions: Set<String> = [
        "Homebrew", "pip", "Yarn", "CocoaPods", "go-build", "com.tidybug.TidyBug",
        "com.apple.HomeKit", "com.apple.Safari", "CloudKit", "com.apple.bird", "com.apple.nsurlsessiond",
        "FamilyCircle", "com.apple.containermanagerd", "com.apple.akd", "com.apple.ap.adprivacyd",
    ]

    // MARK: Developer

    static let derivedData = CleanRule(
        id: "xcode-derived-data", title: "Xcode DerivedData",
        detail: "Build intermediates and indexes. Xcode rebuilds them on the next build.",
        symbol: "hammer.circle.fill", hue: 0.58, group: .developer, safety: .safe, allowsPermanent: true,
        locate: { Paths.children(of: Paths.h("Library/Developer/Xcode/DerivedData")) })

    static let deviceSupport = CleanRule(
        id: "xcode-device-support", title: "Old iOS Device Support",
        detail: "Debug symbols copied from each iOS version you've connected. The newest per device is kept.",
        symbol: "iphone.gen3.circle.fill", hue: 0.62, group: .developer, safety: .safe, allowsPermanent: true,
        locate: {
            ["iOS", "watchOS", "tvOS", "visionOS"].flatMap { os in
                staleDeviceSupport(Paths.children(of: Paths.h("Library/Developer/Xcode/\(os) DeviceSupport")))
            }
        })

    /// Keep the highest OS version per device model; everything else is stale.
    static func staleDeviceSupport(_ dirs: [URL]) -> [URL] {
        var byModel: [String: [(URL, [Int])]] = [:]
        for dir in dirs {
            let parts = dir.lastPathComponent.split(separator: " ").map(String.init)
            // "iPhone14,3 26.5.2 (23F77)" or legacy "16.0 (20A362)"
            let hasModel = parts.first.map { $0.contains(",") || $0.first?.isLetter == true } ?? false
            let model = hasModel ? parts[0] : ""
            let versionText = hasModel ? (parts.count > 1 ? parts[1] : "") : (parts.first ?? "")
            let version = versionText.split(separator: ".").compactMap { Int($0) }
            byModel[model, default: []].append((dir, version))
        }
        return byModel.values.flatMap { entries -> [URL] in
            let sorted = entries.sorted { $0.1.lexicographicallyPrecedes($1.1) }
            return sorted.dropLast().map(\.0)
        }
    }

    static let simulatorCaches = CleanRule(
        id: "simulator-caches", title: "Simulator Caches",
        detail: "CoreSimulator dyld and runtime caches. Rebuilt when a simulator boots.",
        symbol: "ipad.and.iphone", hue: 0.66, group: .developer, safety: .safe, allowsPermanent: true,
        locate: { Paths.existing([Paths.h("Library/Developer/CoreSimulator/Caches")]) })

    static let unavailableSimulators = CleanRule(
        id: "unavailable-simulators", title: "Unavailable Simulators",
        detail: "Simulator devices whose runtime is no longer installed.",
        symbol: "xmark.rectangle.fill", hue: 0.70, group: .developer, safety: .safe,
        command: CommandAction(title: "Delete unavailable", tool: "xcrun", arguments: ["simctl", "delete", "unavailable"]),
        requiredTool: "xcrun",
        locate: { unavailableSimulatorPaths() })

    static func unavailableSimulatorPaths() -> [URL] {
        let r = CommandRunner.runSync("xcrun", ["simctl", "list", "devices", "unavailable", "-j"], timeout: 30)
        guard r.succeeded, let data = r.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return [] }
        return devices.values.flatMap { $0 }.compactMap { d in
            guard let udid = d["udid"] as? String else { return nil }
            return URL(fileURLWithPath: Paths.h("Library/Developer/CoreSimulator/Devices/\(udid)"))
        }.filter { Paths.exists($0.path) }
    }

    static let homebrew = CleanRule(
        id: "homebrew", title: "Homebrew Cleanup",
        detail: "Old formula versions and downloaded bottles.",
        symbol: "mug.fill", hue: 0.08, group: .developer, safety: .safe,
        command: CommandAction(title: "brew cleanup", tool: "brew", arguments: ["cleanup", "-s", "--prune=all"]),
        requiredTool: "brew",
        locate: { Paths.existing([Paths.h("Library/Caches/Homebrew")]) })

    static let devCaches = CleanRule(
        id: "dev-caches", title: "Package Manager Caches",
        detail: "npm, Yarn, pip, uv, Gradle, CocoaPods, Go and Bun download caches. Re-downloaded on demand.",
        symbol: "shippingbox.fill", hue: 0.33, group: .developer, safety: .safe, allowsPermanent: true,
        locate: {
            Paths.existing([
                Paths.h(".npm/_cacache"), Paths.h("Library/Caches/Yarn"), Paths.h("Library/Caches/pip"),
                Paths.h(".cache/uv"), Paths.h(".cache/pip"), Paths.h(".gradle/caches"),
                Paths.h("Library/Caches/CocoaPods"), Paths.h("Library/Caches/go-build"),
                Paths.h(".bun/install/cache"), Paths.h(".cache/yarn"),
            ])
        })

    // MARK: System & Apps

    static let userCaches = CleanRule(
        id: "user-caches", title: "App Caches",
        detail: "Per-app caches in ~/Library/Caches (Spotify, Playwright browsers, updaters...). Apps rebuild them.",
        symbol: "internaldrive.fill", hue: 0.52, group: .system, safety: .safe, allowsPermanent: true,
        locate: {
            Paths.children(of: Paths.h("Library/Caches"), excluding: cacheExclusions)
                .filter { !$0.lastPathComponent.hasPrefix("com.apple.") }
        })

    static let userLogs = CleanRule(
        id: "user-logs", title: "App Logs",
        detail: "Log files and diagnostic reports written by apps.",
        symbol: "doc.text.fill", hue: 0.45, group: .system, safety: .safe, allowsPermanent: true,
        locate: { Paths.children(of: Paths.h("Library/Logs"), excluding: ["TidyBug"]) })

    static let trash = CleanRule(
        id: "trash", title: "Trash",
        detail: "Items already in the Trash. Emptying is permanent.",
        symbol: "trash.fill", hue: 0.0, group: .system, safety: .review, permanentOnly: true,
        locate: { Paths.children(of: Paths.h(".Trash")) })

    // MARK: Files

    static let installers = CleanRule(
        id: "installers", title: "Installers & Disk Images",
        detail: ".dmg, .pkg, .iso and .xip files in Downloads and Desktop — usually already installed.",
        symbol: "opticaldisc.fill", hue: 0.78, group: .files, safety: .review,
        locate: {
            let exts: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
            return ["Downloads", "Desktop"].flatMap { Paths.children(of: Paths.h($0)) }
                .filter { exts.contains($0.pathExtension.lowercased()) }
        })

    static let dbDumps = CleanRule(
        id: "db-dumps", title: "Database Dumps",
        detail: "SQL dumps and backup tarballs in your home folder's backup/dump folders. Check before removing.",
        symbol: "cylinder.split.1x2.fill", hue: 0.12, group: .files, safety: .review,
        locate: {
            let exts: Set<String> = ["sql", "gz", "dump", "bak", "tar", "tgz", "zst", "bz2"]
            let dirs = Paths.children(of: Paths.home, hidden: false).filter { url in
                let n = url.lastPathComponent.lowercased()
                return (n.contains("dump") || n.contains("backup")) && isDirectory(url)
            }
            return dirs.flatMap { Paths.children(of: $0.path) }
                .filter { exts.contains($0.pathExtension.lowercased()) }
        })

    static let editorBackups = CleanRule(
        id: "editor-backups", title: "Editor State Backups",
        detail: "Stale state.vscdb.backup copies from Cursor / VS Code. The live database is untouched.",
        symbol: "chevron.left.forwardslash.chevron.right", hue: 0.55, group: .files, safety: .review,
        allowsPermanent: true,
        locate: {
            ["Cursor", "Code", "Windsurf", "Code - Insiders"].map {
                Paths.h("Library/Application Support/\($0)/User/globalStorage/state.vscdb.backup")
            }.filter(Paths.exists).map { URL(fileURLWithPath: $0) }
        })

    static let iosBackups = CleanRule(
        id: "ios-backups", title: "iPhone & iPad Backups",
        detail: "Local device backups made by Finder. Make sure you have a newer or iCloud backup first.",
        symbol: "externaldrive.fill.badge.timemachine", hue: 0.6, group: .files, safety: .review,
        locate: { Paths.children(of: Paths.h("Library/Application Support/MobileSync/Backup")) })

    static let mailDownloads = CleanRule(
        id: "mail-downloads", title: "Mail Attachments Cache",
        detail: "Attachments Mail saved when you opened them. They stay in your mailbox.",
        symbol: "paperclip", hue: 0.57, group: .files, safety: .review, allowsPermanent: true,
        locate: { Paths.children(of: Paths.h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")) })

    // MARK: Heavy hitters (advice only)

    static let docker = CleanRule(
        id: "docker", title: "Docker / OrbStack",
        detail: "Unused images, stopped containers and build cache inside the VM disk.",
        symbol: "cube.box.fill", hue: 0.56, group: .heavy, safety: .advisor,
        advice: "Never delete the VM disk image directly — it destroys every container and volume. Use the prune button (unused images, stopped containers, build cache; volumes are kept).",
        command: CommandAction(title: "Run docker prune", tool: "docker", arguments: ["system", "prune", "-a", "-f"]),
        requiredTool: "docker",
        locate: {
            Paths.existing([Paths.h("Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img.raw"),
                            Paths.h("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")])
        },
        probe: { dockerReclaimable() })

    static func dockerReclaimable() -> (bytes: Int64, note: String)? {
        let r = CommandRunner.runSync("docker", ["system", "df", "--format", "{{.Type}}\t{{.Reclaimable}}"], timeout: 6)
        guard r.succeeded else { return (0, "Docker isn't running — start it to see what can be pruned.") }
        var total: Int64 = 0
        for line in r.output.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count == 2 else { continue }
            let value = cols[1].split(separator: " ").first.map(String.init) ?? ""
            total += parseSize(value) ?? 0
        }
        return (total, "\(total.formattedBytes) reclaimable by prune")
    }

    static let whatsapp = CleanRule(
        id: "whatsapp", title: "WhatsApp Media",
        detail: "Photos, videos and documents from chats.",
        symbol: "message.fill", hue: 0.38, group: .heavy, safety: .advisor,
        advice: "Deleting these files by hand corrupts WhatsApp's database. Use WhatsApp → Settings → Storage and Data → Manage Storage.",
        openURL: URL(fileURLWithPath: "/Applications/WhatsApp.app"),
        locate: { Paths.existing([Paths.h("Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message")]) })

    static let chrome = CleanRule(
        id: "chrome", title: "Chrome Profile",
        detail: "History, service workers, IndexedDB and cached site data.",
        symbol: "globe", hue: 0.1, group: .heavy, safety: .advisor,
        advice: "Deleting the profile logs you out everywhere. Use Chrome → Settings → Privacy → Delete browsing data (cached images and files, site data).",
        openURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
        locate: { Paths.existing([Paths.h("Library/Application Support/Google/Chrome")]) })

    static let claudeVMs = CleanRule(
        id: "claude-vm-bundles", title: "Claude VM Bundles",
        detail: "Sandbox VM images downloaded by the Claude desktop app.",
        symbol: "sparkles", hue: 0.06, group: .heavy, safety: .advisor,
        advice: "Quit Claude first. The app re-downloads what it needs, but deleting while it runs can break an active session.",
        locate: { Paths.existing([Paths.h("Library/Application Support/Claude/vm_bundles")]) })

    static let timeMachine = CleanRule(
        id: "time-machine", title: "Time Machine Local Snapshots",
        detail: "APFS snapshots macOS keeps until space is needed.",
        symbol: "clock.arrow.circlepath", hue: 0.3, group: .heavy, safety: .advisor,
        advice: "macOS frees these automatically under pressure. To thin now: tmutil thinlocalsnapshots / 999999999999 4",
        requiredTool: "tmutil",
        locate: { [] },
        probe: {
            let r = CommandRunner.runSync("tmutil", ["listlocalsnapshots", "/"], timeout: 15)
            let count = r.output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
            return (0, count == 0 ? "No local snapshots" : "\(count) local snapshot\(count == 1 ? "" : "s")")
        })

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
