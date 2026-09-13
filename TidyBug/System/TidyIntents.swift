import AppIntents
import TidyBugCore

/// Scans (if needed) and trashes only the regenerable, safe tier.
struct CleanSafeJunkIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Safe Junk"
    static let description = IntentDescription("Scans for regenerable caches and logs, then moves them to the Trash.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let freed = await AppModel.shared.cleanSafeJunk()
        let text = freed > 0 ? "Tidy swept away \(freed.formattedBytes)." : "Nothing to sweep. Your Mac is already tidy!"
        return .result(value: freed.formattedBytes, dialog: IntentDialog(stringLiteral: text))
    }
}

/// Reports free space on the startup volume.
struct FreeSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Free Space"
    static let description = IntentDescription("Tells you how much space is free on your Mac.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let volume = VolumeInfo.current()
        AppModel.shared.refreshVolume()
        let free = volume.available.formattedBytes
        return .result(value: free,
                       dialog: IntentDialog(stringLiteral: "\(free) free of \(volume.total.formattedBytes)."))
    }
}

/// Runs a Smart Scan and reports how much could be reclaimed.
struct ScanJunkIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan for Junk"
    static let description = IntentDescription("Runs a Smart Scan and reports how much space could be reclaimed.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        await model.scanIfNeeded()
        let total = model.reclaimableTotal
        let safe = model.safeTotal
        return .result(value: total.formattedBytes,
                       dialog: IntentDialog(stringLiteral: "Tidy found \(total.formattedBytes) to review, \(safe.formattedBytes) of it safe to clean right away."))
    }
}

struct TidyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CleanSafeJunkIntent(),
                    phrases: ["Clean safe junk with \(.applicationName)", "Tidy up my Mac with \(.applicationName)"],
                    shortTitle: "Clean Safe Junk",
                    systemImageName: "sparkles")
        AppShortcut(intent: FreeSpaceIntent(),
                    phrases: ["How much space is free in \(.applicationName)", "Check free space with \(.applicationName)"],
                    shortTitle: "Free Space",
                    systemImageName: "internaldrive")
        AppShortcut(intent: ScanJunkIntent(),
                    phrases: ["Scan for junk with \(.applicationName)", "Find junk with \(.applicationName)"],
                    shortTitle: "Scan for Junk",
                    systemImageName: "magnifyingglass")
    }
}
