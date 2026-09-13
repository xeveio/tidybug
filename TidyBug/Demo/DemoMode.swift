#if DEBUG
import AppKit
import SwiftUI
import TidyBugCore

/// DEBUG-only demo mode for marketing screenshots: `TidyBug --demo`.
/// Fills every tab with synthetic, non-personal data. Nothing is scanned,
/// written to the operation log, or deleted.
@MainActor
enum DemoMode {
    private(set) static var isActive = false

    static let home = NSHomeDirectory()
    static func h(_ rel: String) -> URL { URL(fileURLWithPath: home).appendingPathComponent(rel) }
    static func gb(_ v: Double) -> Int64 { Int64(v * 1_000_000_000) }
    static func ago(_ days: Double) -> Date { Date().addingTimeInterval(-days * 86_400) }

    static func install(stageCollector: Bool = false) {
        isActive = true
        DemoOverrides.volume = VolumeInfo.make(total: 1_000_000_000_000, available: 212_400_000_000)
        DemoOverrides.logEntries = history
        SystemMonitor.demoMode = true

        let m = AppModel.shared
        m.volume = VolumeInfo.current()
        m.history = history
        // AppModel's own launch-time log read can land after this; re-apply.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            m.history = history
        }
        // No TipKit popovers over marketing shots (Tips.configure runs right after this).
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            Tips.hideAllTipsForTesting()
        }
        installClean(m)
        installSpace(m)
        installProjects(m)
        installLarge(m)
        installDuplicates()
        installApps()
        if stageCollector {
            m.stage(h("Library/Developer/Xcode/DerivedData/AcmeWeb-bqzdlxkmrpqrgwgdtonhkwtbdrzp"), size: gb(4.8), source: "space")
            m.stage(h("Downloads/Win11_ARM64.iso"), size: gb(7.4), source: "large-files")
            m.stage(h("Documents/GitHub/analytics-dashboard/node_modules"), size: gb(1.4), source: "projects")
        }
    }

    // MARK: Clean

    private static func item(_ rel: String, _ size: Double, days: Double = 3, data: Bool = false) -> CleanItem {
        CleanItem(url: h(rel), size: gb(size), modified: ago(days), containsData: data)
    }

    private static func installClean(_ m: AppModel) {
        let rules = Dictionary(uniqueKeysWithValues: BuiltinRules.all.map { ($0.id, $0) })
        let dd = "Library/Developer/Xcode/DerivedData/"
        let ds = "Library/Developer/Xcode/iOS DeviceSupport/"
        let lc = "Library/Caches/"
        let spec: [(String, [CleanItem], Int64?, String?)] = [
            ("xcode-derived-data", [
                item(dd + "AcmeWeb-bqzdlxkmrpqrgwgdtonhkwtbdrzp", 4.8, days: 1),
                item(dd + "PaymentsKit-fjdkzqplxcvnmwerttyuiohgba", 3.1, days: 6),
                item(dd + "DesignSystem-akdjfhqpwoeirutyzmxncbvlaq", 2.2, days: 14),
                item(dd + "iOSApp-qpwoeiruty0zmxncbvlaksjdhfgp", 1.9, days: 30),
                item(dd + "ModuleCache.noindex", 0.9, days: 2),
            ], nil, nil),
            ("xcode-device-support", [
                item(ds + "iPhone16,2 18.6.2 (22G100)", 6.2, days: 140),
                item(ds + "iPhone15,3 17.5.1 (21F90)", 5.9, days: 300),
                item(ds + "iPad14,3 18.2 (22C152)", 5.5, days: 210),
            ], nil, nil),
            ("simulator-caches", [item("Library/Developer/CoreSimulator/Caches", 2.4, days: 5)], nil, nil),
            ("unavailable-simulators", [
                item("Library/Developer/CoreSimulator/Devices/8F3A2C61-5B0E-4D52-9C1B-7E2D4A6F9B10", 0.7, days: 190),
                item("Library/Developer/CoreSimulator/Devices/1C9E7B44-2A6F-4E83-B5D0-3F8A1C2E6D77", 0.4, days: 240),
            ], nil, nil),
            ("homebrew", [item(lc + "Homebrew", 1.2, days: 4)], nil, nil),
            ("dev-caches", [
                item(".npm/_cacache", 2.3, days: 1), item(lc + "Yarn", 1.4, days: 9), item(lc + "go-build", 0.9, days: 12),
                item(lc + "pip", 0.8, days: 20), item(lc + "CocoaPods", 0.4, days: 45),
            ], nil, nil),
            ("user-caches", [
                item(lc + "com.spotify.client", 2.1, days: 1), item(lc + "ms-playwright", 2.0, days: 16),
                item(lc + "Google", 1.3, days: 1), item(lc + "com.microsoft.VSCode.ShipIt", 1.1, days: 33),
                item(lc + "com.figma.Desktop", 0.9, days: 2), item(lc + "com.tinyspeck.slackmacgap", 0.8, days: 1),
                item(lc + "org.swift.swiftpm", 0.7, days: 8), item(lc + "JetBrains", 0.6, days: 60),
                item(lc + "SiriTTS", 0.6, days: 90),
            ], nil, nil),
            ("user-logs", [
                item("Library/Logs/DiagnosticReports", 0.12, days: 3), item("Library/Logs/CoreSimulator", 0.05, days: 5),
                item("Library/Logs/JetBrains", 0.03, days: 40),
            ], nil, nil),
            ("trash", [item(".Trash/old-recordings", 0.9, days: 12), item(".Trash/Figma-124.dmg", 0.4, days: 20)], nil, nil),
            ("installers", [
                item("Downloads/Win11_ARM64.iso", 7.4, days: 380), item("Downloads/Android Studio.dmg", 1.3, days: 95),
                item("Downloads/Docker.dmg", 0.62, days: 70), item("Downloads/Figma-126.dmg", 0.41, days: 30),
                item("Downloads/UTM.dmg", 0.3, days: 150), item("Downloads/Postman-osx-11.pkg", 0.21, days: 60),
                item("Downloads/node-v22.12.0.pkg", 0.08, days: 110),
            ], nil, nil),
            ("db-dumps", [
                item("db-backups/payments_prod_2026-08-30.sql.gz", 3.1, days: 14),
                item("db-backups/acme_staging.dump", 1.4, days: 40),
                item("db-backups/analytics_2026-06-01.tar.gz", 0.9, days: 104),
            ], nil, nil),
            ("editor-backups", [item("Library/Application Support/Cursor/User/globalStorage/state.vscdb.backup", 2.1, days: 7)], nil, nil),
            ("mail-downloads", [item("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/7A1C", 0.12, days: 30)], nil, nil),
            ("docker", [item("Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img.raw", 48.0, days: 1)],
             gb(34.2), "34.2 GB reclaimable by prune"),
            ("chrome", [item("Library/Application Support/Google/Chrome", 6.2, days: 1)], nil, nil),
            ("time-machine", [], 0, "No local snapshots"),
        ]
        var results: [RuleResult] = []
        for (id, items, probe, note) in spec {
            guard let rule = rules[id] else { continue }
            results.append(RuleResult(rule: rule, items: items.sorted { $0.size > $1.size }, probeBytes: probe, probeNote: note))
        }
        let order = m.ruleOrder
        results.sort { (order.firstIndex(of: $0.id) ?? 99) < (order.firstIndex(of: $1.id) ?? 99) }
        m.results = results
        m.selectedItems = []
        m.selectedCommands = []
        for r in results where r.rule.safety == .safe {
            if r.rule.isCommandBased {
                m.selectedCommands.insert(r.id)
            } else {
                for i in r.items where i.isRemovable && !i.containsData { m.selectedItems.insert(i.id) }
            }
        }
        m.scanPhase = .ready
        m.lastScan = Date().addingTimeInterval(-240)
    }

    // MARK: Space

    indirect enum Spec {
        case f(String, Double)
        case d(String, [Spec])
        case more(Int, Double)
    }

    private static func totals(_ s: Spec) -> (Double, Int) {
        switch s {
        case .f(_, let g): return (g, 1)
        case .more(let n, let g): return (g, n)
        case .d(_, let kids): return kids.map(totals).reduce((0, 0)) { ($0.0 + $1.0, $0.1 + $1.1) }
        }
    }

    private static func build(_ s: Spec, parent: String) -> DiskNode {
        switch s {
        case .f(let n, let g):
            return DiskNode.make(name: n, path: parent + "/" + n, isDirectory: false, size: gb(g))
        case .more(let count, let g):
            return DiskNode.make(name: "\(count.formatted()) smaller files", path: parent, isDirectory: false,
                                 size: gb(g), fileCount: count, isAggregate: true)
        case .d(let n, let kids):
            let path = parent + "/" + n
            let t = totals(s)
            let node = DiskNode.make(name: n, path: path, isDirectory: true, size: gb(t.0), fileCount: t.1)
            for k in kids { node.append(build(k, parent: path)) }
            return node
        }
    }

    private static let spaceSpec: [Spec] = [
        .d("Library", [
            .d("Developer", [
                .d("Xcode", [
                    .d("iOS DeviceSupport", [.f("iPhone16,2 18.6.2 (22G100)", 6.2), .f("iPhone15,3 17.5.1 (21F90)", 5.9), .f("iPad14,3 18.2 (22C152)", 5.5)]),
                    .d("DerivedData", [.f("AcmeWeb-bqzd", 4.8), .f("PaymentsKit-fjdk", 3.1), .f("DesignSystem-akdj", 2.2), .f("iOSApp-qpwo", 1.9), .more(412, 0.9)]),
                    .d("Archives", [.f("AcmeApp 2026-08-12.xcarchive", 1.8), .f("AcmeApp 2026-07-02.xcarchive", 1.4)]),
                ]),
                .d("CoreSimulator", [.d("Devices", [.f("iPhone 17 Pro", 5.1), .f("iPhone 16e", 4.2), .f("iPad Air 13-inch", 3.5)]), .f("Caches", 2.4)]),
            ]),
            .d("Group Containers", [.d("HUAQ24HBR6.dev.orbstack", [.f("data.img.raw", 48.0)]), .f("group.com.apple.notes", 1.2), .more(2_310, 2.4)]),
            .d("Application Support", [
                .d("Google", [.f("Chrome", 6.2)]), .d("Cursor", [.f("User", 4.1), .f("CachedData", 1.2)]),
                .f("Slack", 2.3), .f("Spotify", 1.6), .f("Figma", 1.1), .more(8_120, 3.9),
            ]),
            .d("Caches", [.f("com.spotify.client", 2.1), .f("ms-playwright", 2.0), .f("Google", 1.3), .f("Homebrew", 1.2), .f("Yarn", 1.4), .more(3_402, 2.1)]),
            .d("Containers", [.f("com.apple.mail", 6.1), .f("com.docker.docker", 3.2), .more(12_004, 4.4)]),
        ]),
        .d("Documents", [
            .d("GitHub", [
                .d("ml-pipeline", [.f("data", 14.2), .f(".venv", 2.3), .more(1_910, 0.6)]),
                .d("ios-app", [.f("build", 4.1), .f("Pods", 0.9), .more(3_004, 1.2)]),
                .d("acme-web", [.f("node_modules", 1.9), .f(".next", 0.4), .more(2_210, 0.5)]),
                .d("mobile-rn", [.f("node_modules", 2.2), .f("Pods", 0.9), .more(1_808, 0.4)]),
                .d("analytics-dashboard", [.f("node_modules", 1.4), .more(980, 0.2)]),
                .d("design-system", [.f("node_modules", 1.2), .f("storybook-static", 0.3), .more(740, 0.2)]),
                .d("cli-tool", [.f("target", 1.2), .more(210, 0.05)]),
                .d("payments-api", [.f("node_modules", 0.81), .more(530, 0.1)]),
            ]),
            .f("Board decks", 1.4), .more(4_120, 3.2),
        ]),
        .d("Downloads", [
            .f("Win11_ARM64.iso", 7.4), .f("old-photos-2019.zip", 6.2), .f("Xcode_16.4.xip", 3.4),
            .f("ubuntu-24.04-desktop-arm64.iso", 3.0), .f("Android Studio.dmg", 1.3), .more(1_460, 4.6),
        ]),
        .d("VMs", [.f("dev-box.qcow2", 18.2)]),
        .d("Pictures", [.f("Photos Library.photoslibrary", 21.4), .more(640, 1.1)]),
        .d("Movies", [.f("Screen Recording 2026-05-02.mov", 3.6), .f("demo-reel-4k.mp4", 2.8), .more(88, 1.9)]),
        .d("Music", [.f("Music", 6.2)]),
        .d("Desktop", [.f("conference-keynote.key", 1.2), .more(210, 1.4)]),
        .more(9_300, 2.2),
    ]

    private static func installSpace(_ m: AppModel) {
        let t = totals(.d("~", spaceSpec))
        let root = DiskNode.make(name: "~", path: home, isDirectory: true, size: gb(t.0), fileCount: t.1)
        for s in spaceSpec { root.append(build(s, parent: home)) }
        m.mapRootPath = home
        m.mapRoot = root
        m.mapFocus = root
        m.mapScanning = false
        m.mapVersion += 1
    }

    // MARK: Projects

    private static func installProjects(_ m: AppModel) {
        let rows: [(String, String, String, Double, Double, Bool)] = [
            ("mobile-rn", "node_modules", "node_modules", 2.2, 33, true),
            ("ml-pipeline", ".venv", "Python venv", 2.3, 210, true),
            ("acme-web", "node_modules", "node_modules", 1.9, 142, true),
            ("ios-app", "build", "Xcode build", 4.1, 96, true),
            ("analytics-dashboard", "node_modules", "node_modules", 1.4, 180, true),
            ("design-system", "node_modules", "node_modules", 1.2, 64, true),
            ("cli-tool", "target", "Rust target", 1.2, 41, true),
            ("legacy-admin", "node_modules", "node_modules", 1.1, 410, false),
            ("mobile-rn", "Pods", "CocoaPods", 0.9, 33, true),
            ("ios-app", "Pods", "CocoaPods", 0.9, 96, true),
            ("payments-api", "node_modules", "node_modules", 0.81, 3, true),
            ("data-notebooks", ".venv", "Python venv", 1.7, 300, true),
            ("acme-web", ".next", ".next cache", 0.4, 142, true),
            ("docs-site", ".next", ".next cache", 0.3, 12, true),
        ]
        m.artifacts = rows.map { repo, folder, kind, size, age, lock in
            let project = h("Documents/GitHub/\(repo)").path
            return ProjectArtifact.make(
                item: CleanItem(url: URL(fileURLWithPath: project).appendingPathComponent(folder), size: gb(size), modified: ago(age)),
                kind: kind, projectName: repo, projectPath: project, projectModified: ago(age), reinstallable: lock)
        }
        m.purgeSelection = []
        m.purgeScanning = false
        m.purgeScanned = true
    }

    // MARK: Large files

    private static func installLarge(_ m: AppModel) {
        let rows: [(String, Double, Double)] = [
            ("VMs/dev-box.qcow2", 18.2, 30), ("Downloads/Win11_ARM64.iso", 7.4, 380),
            ("Downloads/old-photos-2019.zip", 6.2, 700), ("Movies/Screen Recording 2026-05-02.mov", 3.6, 120),
            ("Downloads/Xcode_16.4.xip", 3.4, 200), ("db-backups/payments_prod_2026-08-30.sql.gz", 3.1, 14),
            ("Downloads/ubuntu-24.04-desktop-arm64.iso", 3.0, 240), ("Movies/demo-reel-4k.mp4", 2.8, 60),
            ("Documents/datasets/events-2025.csv", 1.9, 150), ("Downloads/Android Studio.dmg", 1.3, 95),
            ("Desktop/conference-keynote.key", 1.2, 90), ("Documents/Design/brand-assets.zip", 1.2, 210),
        ]
        m.largeFiles = rows.map { rel, size, age in
            LargeFile(item: CleanItem(url: h(rel), size: gb(size), modified: ago(age + 10)), accessed: ago(age))
        }
        m.largeSelection = []
        m.largeScanning = false
        m.largeScanned = true
    }

    // MARK: Duplicates

    private static func installDuplicates() {
        let d = DuplicatesModel.shared
        func group(_ id: String, _ name: String, _ size: Double, _ dirs: [(String, Double)]) -> DuplicateGroup {
            let files = dirs.map { dir, age in
                DuplicateFile(url: h("\(dir)/\(name)"), size: gb(size), modified: ago(age))
            }
            return DuplicateGroup(id: id, size: gb(size), files: files, keeperID: files[0].id)
        }
        d.groups = [
            group("a41f09c2", "brand-assets.zip", 1.2, [("Documents/Design", 210), ("Downloads", 12)]),
            group("7be03e10", "onboarding-video-final.mp4", 0.82, [("Movies", 90), ("Downloads", 40), ("Desktop", 3)]),
            group("c3d9aa71", "node-v22.12.0.pkg", 0.078, [("Downloads/Installers", 110), ("Downloads", 60), ("Desktop", 20)]),
            group("5e1f2b88", "Q3-board-deck.pdf", 0.048, [("Documents/Board decks", 80), ("Downloads", 79), ("Desktop", 75)]),
            group("9a0c4d12", "contract-signed.pdf", 0.004, [("Documents/Legal", 200), ("Downloads", 199)]),
        ]
        d.filesScanning = false
        d.filesScanned = true
        d.mode = .files
        d.selectSuggested()

        if let cluster = makePhotoCluster() {
            d.clusters = [cluster]
            d.photosScanning = false
            d.photosScanned = true
        }
    }

    private static func makePhotoCluster() -> PhotoCluster? {
        let dir = h("Library/Caches/TidyBugDemo/Trips")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let variants: [(String, Int, Int, CGFloat)] = [("IMG_2041.jpg", 4032, 3024, 0), ("IMG_2041 (1).jpg", 2048, 1536, 0.02),
                                                      ("IMG_2041-edited.jpg", 4032, 3024, 0.06)]
        var photos: [SimilarPhoto] = []
        for (name, w, hgt, shift) in variants {
            let url = dir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path), let data = gradientJPEG(shift: shift) {
                try? data.write(to: url)
            }
            photos.append(SimilarPhoto(url: url, size: Int64(Double(w * hgt) * 0.36), modified: ago(40), pixelWidth: w, pixelHeight: hgt))
        }
        return PhotoCluster(id: "trip-sunset", photos: photos, keeperID: photos[0].id, spread: 0.12)
    }

    private static func gradientJPEG(shift: CGFloat) -> Data? {
        let w = 640, hgt = 480
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: hgt, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: w, height: hgt)
        NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.55 + shift, blue: 0.28, alpha: 1),
                            NSColor(calibratedRed: 0.86, green: 0.30, blue: 0.42 + shift, alpha: 1),
                            NSColor(calibratedRed: 0.22, green: 0.18, blue: 0.42, alpha: 1)])?.draw(in: rect, angle: -90)
        NSColor(calibratedRed: 1, green: 0.9, blue: 0.6, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 250 + shift * 400, y: 150, width: 120, height: 120)).fill()
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
        let hills = NSBezierPath()
        hills.move(to: .zero)
        hills.curve(to: NSPoint(x: 640, y: 90), controlPoint1: NSPoint(x: 200, y: 200), controlPoint2: NSPoint(x: 420, y: 20))
        hills.line(to: NSPoint(x: 640, y: 0))
        hills.close()
        hills.fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: Apps

    private static func installApps() {
        let a = AppsModel.shared
        let rows: [(String, String, String, Double, Double, Bool)] = [
            ("Google Chrome", "com.google.Chrome", "140.0.7339", 1.42, 0.2, false),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "1.6.2", 0.71, 0.1, false),
            ("Slack", "com.tinyspeck.slackmacgap", "4.46.99", 0.52, 0.3, false),
            ("Discord", "com.hnc.Discord", "0.0.360", 0.44, 6, false),
            ("Postman", "com.postmanlabs.mac", "11.62.3", 0.63, 9, false),
            ("OrbStack", "dev.kdrag0n.MacVirt", "2.0.1", 0.46, 1, false),
            ("Spotify", "com.spotify.client", "1.2.72", 0.38, 2, false),
            ("zoom.us", "us.zoom.xos", "6.5.11", 0.42, 21, false),
            ("Obsidian", "md.obsidian", "1.9.12", 0.33, 4, false),
            ("Raycast", "com.raycast.macos", "1.103.0", 0.29, 0.05, false),
            ("TablePlus", "com.tinyapp.TablePlus", "6.7.1", 0.12, 11, false),
            ("1Password", "com.1password.1password", "8.11.4", 0.39, 0.4, false),
            ("Telegram", "ru.keepcoder.Telegram", "11.14", 0.21, 45, true),
            ("iTerm", "com.googlecode.iterm2", "3.6.1", 0.11, 0.2, false),
            ("The Unarchiver", "com.macpaw.site.theunarchiver", "4.3.9", 0.05, 160, true),
            ("Figma", "com.figma.Desktop", "126.1.4", 0.49, 3, false),
            ("Notion", "notion.id", "4.21.1", 0.41, 7, false),
            ("Linear", "com.linear", "1.29.0", 0.28, 1, false),
            ("Docker", "com.docker.docker", "4.45.0", 2.1, 200, false),
            ("Android Studio", "com.google.android.studio", "2025.1.3", 3.2, 260, false),
        ]
        a.apps = rows.map { name, id, version, size, used, store in
            InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: id, version: version,
                         size: gb(size), lastUsed: ago(used), isAppStore: store)
        }
        a.scanning = false
        a.sizing = false
        a.scanned = true
        a.selection = []
        a.orphans = [
            OrphanLeftover.make(url: h("Library/Containers/com.microsoft.teams2"), category: "Containers",
                           bundleID: "com.microsoft.teams2", size: gb(1.76)),
            OrphanLeftover.make(url: h("Library/Caches/com.getdropbox.dropbox"), category: "Caches",
                           bundleID: "com.getdropbox.dropbox", size: gb(0.24)),
            OrphanLeftover.make(url: h("Library/Application Support/com.sketchup.SketchUp.2023"), category: "Application Support",
                           bundleID: "com.sketchup.SketchUp.2023", size: gb(0.31)),
            OrphanLeftover.make(url: h("Library/Saved Application State/com.parallels.desktop.console.savedState"), category: "Saved State",
                           bundleID: "com.parallels.desktop.console", size: 1_800_000),
            OrphanLeftover.make(url: h("Library/Preferences/com.adobe.acc.AdobeCreativeCloud.plist"), category: "Preferences",
                           bundleID: "com.adobe.acc.AdobeCreativeCloud", size: 24_000),
        ]
        a.orphanSelection = []
        a.scanningOrphans = false
        a.orphansScanned = true
    }

    // MARK: Activity

    static let history: [LogEntry] = {
        let rows: [(Double, String, String?, String, Double, DeletionMode)] = [
            (0.1, "collector", nil, "~/Downloads/Xcode_16.2.xip", 3.1, .trash),
            (0.1, "collector", nil, "~/Documents/GitHub/legacy-web/node_modules", 1.3, .trash),
            (1.2, "smart-clean", "xcode-derived-data", "~/Library/Developer/Xcode/DerivedData/Checkout-akq", 2.8, .permanent),
            (1.2, "smart-clean", "user-caches", "~/Library/Caches/com.spotify.client", 1.9, .permanent),
            (3.4, "purge", nil, "~/Documents/GitHub/marketing-site/node_modules", 0.9, .trash),
            (3.4, "purge", nil, "~/Documents/GitHub/ios-app/build", 3.6, .trash),
            (5.8, "duplicates", nil, "~/Downloads/brand-assets (1).zip", 1.2, .trash),
            (7.0, "smart-clean", "xcode-device-support", "~/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,3 17.4", 5.4, .trash),
            (7.0, "smart-clean", "homebrew", "brew cleanup -s --prune=all", 0.8, .command),
            (9.5, "uninstall", nil, "/Applications/Microsoft Teams.app", 1.1, .trash),
            (11.2, "optimize", nil, "qlmanage -r cache", 0, .command),
            (13.6, "large-files", nil, "~/Movies/old-demo-4k.mov", 4.2, .trash),
        ]
        return rows.map { age, source, rule, path, size, mode in
            let full = path.hasPrefix("~") ? NSHomeDirectory() + path.dropFirst() : path
            return LogEntry(date: ago(age), source: source, rule: rule, path: full, bytes: gb(size), mode: mode)
        }
    }()
}
#endif
