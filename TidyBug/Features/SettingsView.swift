import SwiftUI
import TidyBugCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            SafetySettings().tabItem { Label("Safety", systemImage: "shield.lefthalf.filled") }
        }
        .frame(width: 540, height: 460)
        .preferredColorScheme(.dark)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showFreeInMenuBar") private var showFreeInMenuBar = true
    @AppStorage("permanentForCaches") private var permanentForCaches = false
    @State private var launchAtLogin = false
    @AppStorage("lowSpaceAlerts") private var lowSpaceAlerts = true
    @AppStorage("lowSpaceThresholdGB") private var lowSpaceThresholdGB = 20

    var body: some View {
        Form {
            Section {
                Toggle("Notify when free space is low", isOn: $lowSpaceAlerts)
                Picker("Threshold", selection: $lowSpaceThresholdGB) {
                    ForEach([10, 20, 50, 100], id: \.self) { Text("\($0) GB").tag($0) }
                }
                .disabled(!lowSpaceAlerts)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Sent at most once a day. The notification includes a “Clean safe items” action.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Menu bar") {
                Toggle("Show free space in the menu bar", isOn: $showFreeInMenuBar)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in model.launchAtLogin = on }
            }
            Section {
                Toggle("Delete regenerable caches permanently", isOn: $permanentForCaches)
            } header: {
                Text("Cleaning")
            } footer: {
                Text("Off: all items are moved to the Trash. On: caches, logs and DerivedData are deleted immediately. Other files are always moved to the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NotchSettingsSection()
            UpdatesSettingsSection()
            Section("Permissions") {
                HStack {
                    Label(model.hasFullDiskAccess ? "Full Disk Access granted" : "Full Disk Access not granted",
                          systemImage: model.hasFullDiskAccess ? "checkmark.shield" : "exclamationmark.shield")
                        .foregroundStyle(model.hasFullDiskAccess ? Palette.success : Palette.warning)
                    Spacer()
                    Button("Open System Settings") { model.openFullDiskAccessSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = model.launchAtLogin
            model.refreshVolume()
        }
    }
}

struct SafetySettings: View {
    @Environment(AppModel.self) private var model
    @State private var list: [String] = []

    var body: some View {
        Form {
            Section {
                ForEach(list, id: \.self) { path in
                    HStack {
                        Image(systemName: "lock").foregroundStyle(.secondary)
                        Text(Finder.abbreviate(path)).font(.mono(12)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { save(list.filter { $0 != path }) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                Button {
                    if let p = Finder.chooseFolder(startingAt: NSHomeDirectory()), !list.contains(p) { save(list + [p]) }
                } label: { Label("Add Protected Folder…", systemImage: "plus") }
            } header: {
                Text("Protected folders")
            } footer: {
                Text("Nothing inside these folders is ever removed. Built-in protections always apply: ~/Documents, ~/Desktop, iCloud Drive, Photos libraries, .git directories, ~/.ssh, ~/.secrets, and signed .xcarchive / .ipa artifacts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { list = model.whitelist }
    }

    private func save(_ new: [String]) {
        withAnimation { list = new }
        model.whitelist = new
    }
}
