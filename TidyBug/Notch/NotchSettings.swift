import SwiftUI

/// Settings → General → Notch.
struct NotchSettingsSection: View {
    @AppStorage("notchEnabled") private var enabled = NotchSupport.hasNotch
    @AppStorage("notchMetrics") private var metrics = "cpuMem"
    @AppStorage("notchExpandOnHover") private var expandOnHover = true

    var body: some View {
        Section {
            Toggle(NotchSupport.hasNotch ? "Show live CPU and memory around the notch"
                                         : "Show a live CPU and memory pill under the menu bar",
                   isOn: $enabled)
            Picker("Show", selection: $metrics) {
                Text("CPU + Memory").tag("cpuMem")
                Text("CPU + Memory + Network").tag("cpuMemNet")
            }
            .disabled(!enabled)
            Toggle("Expand on hover", isOn: $expandOnHover)
                .disabled(!enabled)
        } header: {
            Text("Notch")
        } footer: {
            Text("Stays visible when the TidyBug window is closed and hides in full-screen apps. Samples once a second.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
