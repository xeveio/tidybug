import SwiftUI
import TipKit

/// App-launch hooks: tips, low-space monitoring and Shortcuts.
enum SystemSetup {
    @MainActor static func configure() {
        try? Tips.configure([.displayFrequency(.daily)])
        LowSpaceMonitor.shared.start()
        TidyShortcuts.updateAppShortcutParameters()
        // After launch finishes, so the panel is created against real screens.
        DispatchQueue.main.async { NotchController.shared.startIfEnabled() }
    }
}
