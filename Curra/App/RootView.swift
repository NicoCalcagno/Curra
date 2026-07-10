import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ActivityListView()
                .tabItem { Label("Activities", systemImage: "figure.run") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
