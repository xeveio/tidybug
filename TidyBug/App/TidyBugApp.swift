import SwiftUI
import TidyBugCore

@main
struct TidyBugApp: App {
    @State private var model = AppModel.shared
    @AppStorage("showFreeInMenuBar") private var showFreeInMenuBar = true

    init() {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-mascot"), i + 1 < args.count {
            MascotSnapshot.render(to: args[i + 1])
            exit(0)
        }
        if args.contains("--demo") { DemoMode.install(stageCollector: args.contains("--demo-collector")) }
        #endif
        SystemSetup.configure()
        _ = Updater.shared // starts Sparkle's scheduled update checks
    }

    var body: some Scene {
        Window("TidyBug", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Smart Scan") { model.pane = .smartClean; model.startSmartScan() }
                    .keyboardShortcut("r")
                Button("Scan Space Map") { model.pane = .diskMap; model.scanDiskMap() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
            }
            CommandGroup(replacing: .help) {
                Button("How to Use TidyBug") { model.showTour = true }
                Button("Reveal Operations Log") { Finder.reveal(OperationLog.shared.url) }
            }
            CommandMenu("Go") {
                ForEach(Array(Pane.dock.enumerated()), id: \.element) { index, pane in
                    Button(pane.title) { model.pane = pane }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button("History") { model.pane = .history }.keyboardShortcut("y")
            }
        }

        MenuBarExtra {
            MenuBarView().environment(model)
        } label: {
            if showFreeInMenuBar {
                Label(model.volume.available.formattedBytes, systemImage: "ladybug.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "ladybug.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}
