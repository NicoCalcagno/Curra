import SwiftUI

/// Pushed from the Dashboard's gear button (lives inside its NavigationStack).
struct SettingsView: View {
    var body: some View {
        Form {
            Section("Data sources") {
                NavigationLink("Strava") {
                    StravaConnectView()
                }
            }

            Section("Routing") {
                NavigationLink("OpenRouteService") {
                    RoutingSettingsView()
                }
            }

            Section("Maps") {
                NavigationLink("Offline maps") {
                    OfflineMapsSettingsView()
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
