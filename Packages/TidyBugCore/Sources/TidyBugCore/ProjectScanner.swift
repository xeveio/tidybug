import Foundation

public struct ProjectArtifact: Sendable, Identifiable, Hashable {
    public var id: String { item.id }
    public var item: CleanItem
    public let kind: String          // "node_modules", "Xcode build", ...
    public let projectName: String
    public let projectPath: String
    /// Last time the project itself was touched.
    public let projectModified: Date
    /// Reinstallable from a lockfile / manifest.
    public let reinstallable: Bool

    public var ageDays: Int { max(0, Int(Date().timeIntervalSince(projectModified) / 86_400)) }
}

/// Finds build artifacts (node_modules, build dirs, venvs...) under project roots.
public enum ProjectScanner {
    public static var defaultRoots: [String] {
        ["Documents/GitHub", "Developer", "Projects", "code", "src", "dev", "Documents"]
            .map { "\(NSHomeDirectory())/\($0)" }
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Returns the artifact kind if `name` inside `parent` is a removable artifact.
    static func classify(name: String, parent: String) -> (kind: String, reinstallable: Bool)? {
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: "\(parent)/\(f)") }
        func hasExt(_ ext: String) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: parent)) ?? []).contains { $0.hasSuffix(ext) }
        }
        let lockfiles = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb", "bun.lock"]

        switch name {
        case "node_modules":
            guard has("package.json") else { return nil }
            return ("node_modules", lockfiles.contains(where: has))
        case ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".expo":
            return has("package.json") ? ("\(name) cache", true) : nil
        case "dist":
            return has("package.json") ? ("dist", true) : nil
        case ".build":
            return has("Package.swift") ? ("SwiftPM .build", true) : nil
        case "DerivedData":
            return hasExt(".xcodeproj") || hasExt(".xcworkspace") ? ("DerivedData", true) : nil
        case "Pods":
            return has("Podfile") ? ("CocoaPods", has("Podfile.lock")) : nil
        case "target":
            return has("Cargo.toml") ? ("Rust target", true) : (has("pom.xml") ? ("Maven target", true) : nil)
        case ".venv", "venv", "env":
            return fm.fileExists(atPath: "\(parent)/\(name)/pyvenv.cfg")
                ? ("Python venv", has("requirements.txt") || has("pyproject.toml") || has("uv.lock")) : nil
        case ".gradle":
            return has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") ? (".gradle", true) : nil
        case "build-archive", "build-export":
            return nil // signed release artifacts — never
        default:
            if name == "build" || name.hasPrefix("build-") {
                if hasExt(".xcodeproj") || hasExt(".xcworkspace") { return ("Xcode build", true) }
                if name == "build" && (has("build.gradle") || has("build.gradle.kts") || has("CMakeLists.txt") || has("package.json")) {
                    return ("build", true)
                }
            }
            return nil
        }
    }

    static let skipDirectories: Set<String> = [".git", "Library", ".Trash", ".claude", "worktrees"]

    public static func scan(
        roots: [String] = defaultRoots,
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        progress: (String) -> Void = { _ in },
        found: (ProjectArtifact) -> Void
    ) {
        let sizer = Sizer(isCancelled: isCancelled)
        var visitedRoots = Set<String>()
        for root in roots {
            // Skip roots nested in an already-scanned root (e.g. Documents/GitHub inside Documents).
            if visitedRoots.contains(where: { root.hasPrefix($0 + "/") }) { continue }
            visitedRoots.insert(root)
            var counter = 0
            FileWalker.walk(root) { e in
                counter += 1
                if counter & 0x1FF == 0 { if isCancelled() { return .stop }; progress(e.path) }
                guard e.kind == .directory, e.level > 0 else { return .proceed }
                let name = e.name
                if skipDirectories.contains(name) || name.hasSuffix(".app") || name.hasSuffix(".xcarchive") {
                    return .skipChildren
                }
                let path = e.path
                let parent = (path as NSString).deletingLastPathComponent
                guard let (kind, reinstallable) = classify(name: name, parent: parent) else { return .proceed }
                progress(path)
                let size = sizer.measure(path, inspect: true)
                if size.bytes > 0 {
                    let url = URL(fileURLWithPath: path)
                    found(ProjectArtifact(
                        item: CleanItem(url: url, size: size.bytes, modified: size.newest,
                                        containsData: size.containsData, containsProtected: size.containsProtected),
                        kind: kind,
                        projectName: (parent as NSString).lastPathComponent,
                        projectPath: parent,
                        projectModified: projectModified(parent),
                        reinstallable: reinstallable))
                }
                return .skipChildren
            }
        }
    }

    /// Git index mtime is the best "last worked on" signal; else the manifest's.
    static func projectModified(_ project: String) -> Date {
        let fm = FileManager.default
        for f in [".git/index", ".git/HEAD", "package.json", "Package.swift", "Cargo.toml", "Podfile"] {
            if let d = (try? fm.attributesOfItem(atPath: "\(project)/\(f)"))?[.modificationDate] as? Date { return d }
        }
        return ((try? fm.attributesOfItem(atPath: project))?[.modificationDate] as? Date) ?? Date()
    }
}
