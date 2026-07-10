import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section("Data sources") {
                    NavigationLink("Strava") {
                        StravaConnectView()
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Curra")
                    LabeledContent(
                        "Privacy",
                        value: "All data stays on this device"
                    )
                }
            }
            .navigationTitle("Settings")
        }
    }
}
