import SwiftUI

struct StravaConnectView: View {
    @Environment(ActivitySyncCoordinator.self) private var sync

    @State private var clientID = StravaAuthService.shared.clientID
    @State private var clientSecret = StravaAuthService.shared.clientSecret
    @State private var isConnected = StravaAuthService.shared.isConnected
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                    .keyboardType(.numberPad)
                SecureField("Client Secret", text: $clientSecret)
            } header: {
                Text("API application")
            } footer: {
                Text("Create an API application at strava.com/settings/api and paste its credentials here. They are stored only on this device.")
            }

            Section {
                if isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Button {
                        Task { await sync.runStravaFullImport() }
                    } label: {
                        if sync.isSyncing, let count = sync.stravaImportedCount {
                            Text("Importing… \(count) activities")
                        } else {
                            Text("Import full history")
                        }
                    }
                    .disabled(sync.isSyncing)

                    Button("Sync recent runs") {
                        Task { await sync.runStravaIncrementalSync() }
                    }
                    .disabled(sync.isSyncing)

                    Button("Disconnect", role: .destructive) {
                        StravaAuthService.shared.disconnect()
                        isConnected = false
                    }
                } else {
                    Button("Connect Strava") {
                        connect()
                    }
                    .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Strava")
        .onChange(of: clientID) { _, newValue in
            StravaAuthService.shared.clientID = newValue
        }
        .onChange(of: clientSecret) { _, newValue in
            StravaAuthService.shared.clientSecret = newValue
        }
    }

    private func connect() {
        errorMessage = nil
        Task {
            do {
                try await StravaAuthService.shared.connect()
                isConnected = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
