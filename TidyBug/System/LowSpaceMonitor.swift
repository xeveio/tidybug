import AppKit
import TidyBugCore
import UserNotifications

enum LowSpaceNotification {
    static let category = "LOW_SPACE"
    static let cleanAction = "CLEAN_SAFE_JUNK"
    static let requestID = "low-space"
}

/// Watches free space (every 10 minutes and on wake) and posts at most one
/// notification a day when it drops below the user's threshold.
@MainActor
final class LowSpaceMonitor: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LowSpaceMonitor()

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    var enabled: Bool { UserDefaults.standard.object(forKey: "lowSpaceAlerts") as? Bool ?? true }

    var thresholdBytes: Int64 {
        let gb = UserDefaults.standard.integer(forKey: "lowSpaceThresholdGB")
        return Int64(gb > 0 ? gb : 20) * 1_000_000_000
    }

    func start() {
        guard timer == nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let clean = UNNotificationAction(identifier: LowSpaceNotification.cleanAction, title: "Clean safe junk", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: LowSpaceNotification.category, actions: [clean], intentIdentifiers: []),
        ])

        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in LowSpaceMonitor.shared.check() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in LowSpaceMonitor.shared.check() }
        }
        check()
    }

    func check() {
        guard enabled else { return }
        let volume = VolumeInfo.current()
        guard volume.total > 0, volume.available < thresholdBytes else { return }
        let last = UserDefaults.standard.object(forKey: "lastLowSpaceAlert") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }

        Task {
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            UserDefaults.standard.set(Date(), forKey: "lastLowSpaceAlert")

            let content = UNMutableNotificationContent()
            content.title = "Your Mac is running low on space"
            content.body = "Only \(volume.available.formattedBytes) left. Tidy can sweep away regenerable caches in one click."
            content.categoryIdentifier = LowSpaceNotification.category
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: LowSpaceNotification.requestID,
                                                        content: content, trigger: nil))
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        if action == LowSpaceNotification.cleanAction {
            await AppModel.shared.cleanSafeJunk()
        } else if action == UNNotificationDefaultActionIdentifier {
            await MainActor.run {
                AppModel.shared.pane = .smartClean
                NSApp.activate()
            }
        }
    }
}
