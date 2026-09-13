import Combine
import Sparkle
import SwiftUI

/// Sparkle 2 auto-updates. The feed URL and public EdDSA key live in
/// Info.plist (generated from project.yml); releases are produced by
/// scripts/release.sh or the tag-triggered GitHub workflow.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }

    var automaticallyDownloads: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue; objectWillChange.send() }
    }

    var lastCheck: Date? { updater.lastUpdateCheckDate }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return short == build ? short : "\(short) (\(build))"
    }
}

/// "Check for Updates…" for the app menu, menu bar and command palette.
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Settings section for update preferences.
struct UpdatesSettingsSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
            Toggle("Download and install updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                .disabled(!updater.automaticallyChecks)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TidyBug \(Updater.versionString)").font(.mono(12))
                    if let last = updater.lastCheck {
                        Text("Last checked \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Updates are signed and notarized, and verified with TidyBug's EdDSA key before installing.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
