import Foundation
import Testing
@testable import TidyBugCore

@Suite(.timeLimit(.minutes(1))) struct AppLeftoverTests {
    /// Builds a fake ~/Library inside a sandbox.
    private func library(_ sb: Sandbox) throws -> URL {
        try sb.dir("Library")
    }

    @Test func findsFilesByBundleIDAndExactName() throws {
        let sb = try Sandbox()
        let lib = try library(sb)
        try sb.file("Library/Application Support/com.acme.Widget/db.sqlite")
        try sb.file("Library/Application Support/Widget/state.json")
        try sb.file("Library/Application Support/Widgets Pro/other.json")        // different app — not matched
        try sb.file("Library/Caches/com.acme.Widget/cache.bin")
        try sb.file("Library/Preferences/com.acme.Widget.plist", bytes: 200)
        try sb.file("Library/Preferences/ByHost/com.acme.Widget.1234-ABCD.plist", bytes: 200)
        try sb.file("Library/Containers/com.acme.Widget/Data/x")
        try sb.file("Library/Saved Application State/com.acme.Widget.savedState/windows.plist")
        try sb.file("Library/Group Containers/ABCDE12345.com.acme.Widget/shared.db")
        try sb.file("Library/Cookies/com.acme.Widget.binarycookies", bytes: 100)
        try sb.file("Library/Preferences/com.acme.WidgetHelperOther.plist", bytes: 100) // prefix only — not matched

        let found = LeftoverFinder(library: lib).leftovers(bundleID: "com.acme.Widget", appName: "Widget")
        let rel = Set(found.map { String($0.url.path.dropFirst(lib.path.count + 1)) })
        #expect(rel == [
            "Application Support/com.acme.Widget", "Application Support/Widget", "Caches/com.acme.Widget",
            "Preferences/com.acme.Widget.plist", "Preferences/ByHost/com.acme.Widget.1234-ABCD.plist",
            "Containers/com.acme.Widget", "Saved Application State/com.acme.Widget.savedState",
            "Group Containers/ABCDE12345.com.acme.Widget", "Cookies/com.acme.Widget.binarycookies",
        ])
        #expect(found.allSatisfy { $0.size > 0 })
    }

    @Test func vendorFolderKeptWhenSharedWithAnotherApp() throws {
        let sb = try Sandbox()
        let lib = try library(sb)
        try sb.file("Library/Application Support/Google/Chrome/Default/History")
        let finder = LeftoverFinder(library: lib)

        let shared = finder.leftovers(bundleID: "com.google.Chrome", appName: "Google Chrome",
                                      otherBundleIDs: ["com.google.drivefs"])
        #expect(shared.isEmpty, "Google folder must stay while Google Drive is installed")

        let alone = finder.leftovers(bundleID: "com.google.Chrome", appName: "Google Chrome",
                                     otherBundleIDs: ["com.spotify.client"])
        #expect(alone.map(\.url.lastPathComponent) == ["Google"])
    }

    @Test func teamGroupContainerOnlyWhenTeamUnshared() throws {
        let sb = try Sandbox()
        let lib = try library(sb)
        try sb.file("Library/Group Containers/UBF8T346G9.Office/shared.db")
        let finder = LeftoverFinder(library: lib)
        #expect(finder.leftovers(bundleID: "com.microsoft.Word", appName: "Microsoft Word", teamID: "UBF8T346G9",
                                 otherTeamIDs: ["UBF8T346G9"]).isEmpty)
        #expect(finder.leftovers(bundleID: "com.microsoft.Word", appName: "Microsoft Word", teamID: "UBF8T346G9",
                                 otherTeamIDs: []).count == 1)
    }

    @Test func launchAgentReferencingAppPath() throws {
        let sb = try Sandbox()
        let lib = try library(sb)
        let plist: [String: Any] = ["Label": "net.vendor.updater", "ProgramArguments": ["/Applications/Widget.app/Contents/MacOS/updater"]]
        let url = try sb.dir("Library/LaunchAgents").appendingPathComponent("net.vendor.updater.plist")
        (plist as NSDictionary).write(to: url, atomically: true)
        let found = LeftoverFinder(library: lib).leftovers(bundleID: "com.acme.Widget", appName: "Widget",
                                                           appPath: "/Applications/Widget.app")
        #expect(found.map(\.category) == ["Launch Agent"])
    }

    @Test func orphansSkipInstalledHelpersAndApple() throws {
        let sb = try Sandbox()
        let lib = try library(sb)
        try sb.file("Library/Containers/com.gone.App/Data/x")                        // orphan
        try sb.file("Library/Saved Application State/org.gone.Editor.savedState/w")   // orphan
        try sb.file("Library/Preferences/com.present.App.plist", bytes: 100)          // installed
        try sb.file("Library/Preferences/com.present.App.LoginHelper.plist", bytes: 100) // helper of installed
        try sb.file("Library/Caches/com.apple.Safari/x")                              // Apple — skipped
        try sb.file("Library/Caches/Homebrew/x")                                      // not a bundle id
        try sb.file("Library/Preferences/.GlobalPreferences.plist", bytes: 100)

        let installed: Set<String> = ["com.present.App"]
        let orphans = LeftoverFinder(library: lib).orphans(isInstalled: { LeftoverFinder.isInstalled($0, installed: installed) })
        #expect(Set(orphans.map(\.bundleID)) == ["com.gone.App", "org.gone.Editor"])
        #expect(orphans.first { $0.bundleID == "com.gone.App" }?.category == "Container")
    }

    @Test func bundleIDShapeAndNames() {
        #expect(LeftoverFinder.looksLikeBundleID("com.spotify.client"))
        #expect(!LeftoverFinder.looksLikeBundleID("Homebrew"))
        #expect(!LeftoverFinder.looksLikeBundleID("com.spotify"))
        #expect(!LeftoverFinder.looksLikeBundleID("Google.Chrome.Thing"))
        #expect(OrphanLeftover(url: URL(fileURLWithPath: "/x"), category: "", bundleID: "com.spotify.client", size: 0)
            .probableAppName == "Spotify")
        #expect(OrphanLeftover(url: URL(fileURLWithPath: "/x"), category: "", bundleID: "com.tinyspeck.slackmacgap", size: 0)
            .probableAppName == "Slackmacgap")
        #expect(OrphanLeftover(url: URL(fileURLWithPath: "/x"), category: "", bundleID: "ui.wifiman.com", size: 0)
            .probableAppName == "Wifiman")
        #expect(LeftoverFinder.isSystemIdentifier("org.swift.swiftpm"))
    }

    @Test func systemAppsExcluded() {
        #expect(AppInventory.isSystemApp(url: URL(fileURLWithPath: "/System/Applications/Mail.app"), bundleID: "com.apple.mail"))
        #expect(AppInventory.isSystemApp(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari"))
        #expect(!AppInventory.isSystemApp(url: URL(fileURLWithPath: "/Applications/Xcode.app"), bundleID: "com.apple.dt.Xcode"))
        #expect(!AppInventory.isSystemApp(url: URL(fileURLWithPath: "/Applications/Slack.app"), bundleID: "com.tinyspeck.slackmacgap"))
    }
}
