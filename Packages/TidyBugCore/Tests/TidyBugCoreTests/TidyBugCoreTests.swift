import Foundation
import Testing
@testable import TidyBugCore

/// Creates a throwaway fake home directory for each test.
final class Sandbox {
    let root: URL
    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tidybug-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ rel: String, bytes: Int = 10_000) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func dir(_ rel: String) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var guardRail: SafetyGuard { SafetyGuard(home: root.path) }
}

@Suite struct SizerTests {
    @Test func countsHardlinksOnce() throws {
        let sb = try Sandbox()
        let a = try sb.file("a/data.bin", bytes: 1_000_000)
        _ = try sb.dir("b")
        try FileManager.default.linkItem(at: a, to: sb.root.appendingPathComponent("b/data.bin"))

        let sizer = Sizer()
        let first = sizer.measure(sb.root.appendingPathComponent("a").path)
        let second = sizer.measure(sb.root.appendingPathComponent("b").path)
        #expect(first.bytes >= 1_000_000)
        #expect(second.bytes < 100_000, "hardlinked bytes must not be counted twice")
    }

    @Test func flagsProtectedAndData() throws {
        let sb = try Sandbox()
        try sb.file("build/App.xcarchive/Info.plist")
        try sb.file("images/barcodes.db")
        let s = Sizer()
        #expect(s.measure(sb.root.appendingPathComponent("build").path, inspect: true).containsProtected)
        #expect(s.measure(sb.root.appendingPathComponent("images").path, inspect: true).containsData)
    }
}

@Suite struct GuardTests {
    @Test func rejectsDangerousPaths() throws {
        let sb = try Sandbox()
        let g = sb.guardRail
        let home = sb.root
        for rel in ["", "Documents", "Library", "Library/Caches", ".ssh/id_ed25519", "Library/Mobile Documents/x",
                    "proj/.git/objects", "DriveStream/build-archive/x", "out/App.xcarchive", "Pictures/Photos Library.photoslibrary/db"] {
            #expect(throws: GuardError.self, "\(rel) should be rejected") {
                try g.validate(rel.isEmpty ? home : home.appendingPathComponent(rel))
            }
        }
        #expect(throws: GuardError.self) { try g.validate(URL(fileURLWithPath: "/System/Library")) }
    }

    @Test func allowsCaches() throws {
        let sb = try Sandbox()
        #expect(sb.guardRail.isAllowed(sb.root.appendingPathComponent("Library/Caches/com.spotify.client")))
        #expect(sb.guardRail.isAllowed(sb.root.appendingPathComponent("Documents/GitHub/app/node_modules")))
    }

    @Test func honoursWhitelist() throws {
        let sb = try Sandbox()
        let g = SafetyGuard(home: sb.root.path, whitelist: [sb.root.appendingPathComponent("Library/Caches/keep").path])
        #expect(!g.isAllowed(sb.root.appendingPathComponent("Library/Caches/keep/inner")))
    }

    @Test func symlinkedParentIsResolved() throws {
        let sb = try Sandbox()
        let ssh = try sb.dir(".ssh")
        _ = try sb.dir("Library/Caches")
        let link = sb.root.appendingPathComponent("Library/Caches/sneaky")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: ssh.path)
        // Removing the link itself is fine; reaching through it into ~/.ssh is not.
        #expect(sb.guardRail.isAllowed(link))
        #expect(!sb.guardRail.isAllowed(link.appendingPathComponent("id_ed25519")))
    }
}

@Suite struct CleanerTests {
    @Test func trashesAndLogs() async throws {
        let sb = try Sandbox()
        let target = try sb.file("Library/Caches/junk/blob.bin", bytes: 50_000)
        let log = OperationLog(url: sb.root.appendingPathComponent("ops.jsonl"))
        let item = CleanItem(url: target.deletingLastPathComponent(), size: 50_000)

        let dry = await Cleaner.remove([item], source: "test", dryRun: true, guard: sb.guardRail, log: log)
        #expect(dry.removed.count == 1)
        #expect(FileManager.default.fileExists(atPath: target.path), "dry run must not touch files")

        let real = await Cleaner.remove([item], mode: .permanent, source: "test", guard: sb.guardRail, log: log)
        #expect(real.freed == 50_000)
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(log.entries().count == 1)
    }

    @Test func refusesProtected() async throws {
        let sb = try Sandbox()
        let docs = try sb.dir("Documents")
        let log = OperationLog(url: sb.root.appendingPathComponent("ops.jsonl"))
        let out = await Cleaner.remove([CleanItem(url: docs, size: 1)], mode: .permanent, source: "test",
                                       guard: sb.guardRail, log: log)
        #expect(out.removed.isEmpty)
        #expect(out.failures.count == 1)
        #expect(FileManager.default.fileExists(atPath: docs.path))
    }
}

@Suite struct RuleTests {
    @Test func deviceSupportKeepsNewestPerModel() {
        let names = ["iPhone14,3 26.3.1 (23D1)", "iPhone14,3 26.5 (23F1)", "iPhone14,3 26.6 (23G1)",
                     "iPhone15,2 18.1 (22B1)", "16.0 (20A362)", "17.2 (21C1)"]
        let urls = names.map { URL(fileURLWithPath: "/x/\($0)") }
        let stale = Set(BuiltinRules.staleDeviceSupport(urls).map(\.lastPathComponent))
        #expect(stale == ["iPhone14,3 26.3.1 (23D1)", "iPhone14,3 26.5 (23F1)", "16.0 (20A362)"])
    }

    @Test func parsesDockerSizes() {
        #expect(parseSize("3.1GB") == 3_100_000_000)
        #expect(parseSize("512MB") == 512_000_000)
        #expect(parseSize("0B") == 0)
        #expect(parseSize("1.5kB") == 1_500)
    }

    @Test func projectScannerFindsNodeModules() throws {
        let sb = try Sandbox()
        try sb.file("GitHub/web/package.json", bytes: 100)
        try sb.file("GitHub/web/pnpm-lock.yaml", bytes: 100)
        try sb.file("GitHub/web/node_modules/react/index.js", bytes: 20_000)
        try sb.file("GitHub/orphan/node_modules/x.js", bytes: 20_000)       // no package.json → ignored
        try sb.file("GitHub/ios/App.xcodeproj/project.pbxproj", bytes: 100)
        try sb.file("GitHub/ios/build/obj.o", bytes: 20_000)
        try sb.file("GitHub/ios/build-archive/App.xcarchive/Info.plist", bytes: 100) // never

        var found: [ProjectArtifact] = []
        ProjectScanner.scan(roots: [sb.root.appendingPathComponent("GitHub").path]) { found.append($0) }
        let kinds = Dictionary(uniqueKeysWithValues: found.map { ($0.projectName + "/" + $0.item.name, $0) })
        #expect(kinds.keys.sorted() == ["ios/build", "web/node_modules"])
        #expect(kinds["web/node_modules"]?.reinstallable == true)
    }

    @Test func diskTreeSumsAndFolds() throws {
        let sb = try Sandbox()
        try sb.file("big/huge.bin", bytes: 6 << 20)
        for i in 0..<5 { try sb.file("big/small\(i).txt", bytes: 300_000) }
        let tree = DiskTreeBuilder.build(root: sb.root.path) { _ in }
        #expect(tree != nil)
        let big = tree?.children.first { $0.name == "big" }
        #expect(big?.children.contains { $0.name == "huge.bin" } == true)
        #expect(big?.children.contains { $0.isAggregate } == true)
        #expect((tree?.size ?? 0) >= (6 << 20) + 1_500_000)
    }
}
