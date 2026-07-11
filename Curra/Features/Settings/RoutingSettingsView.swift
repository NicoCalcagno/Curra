import SwiftUI

struct RoutingSettingsView: View {
    @State private var apiKey = ORSClient.shared.apiKey

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $apiKey)
            } header: {
                Text("OpenRouteService")
            } footer: {
                Text("Used to build routes and generate loops. Create a free account at openrouteservice.org, request a token, and paste it here. It is stored only on this device.")
            }
        }
        .navigationTitle("Routing")
        .onChange(of: apiKey) { _, newValue in
            ORSClient.shared.apiKey = newValue
        }
    }
}
