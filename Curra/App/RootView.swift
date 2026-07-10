import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "target") }

            ActivityListView()
                .tabItem { Label("Activities", systemImage: "figure.run") }

            InstantWorkoutView()
                .tabItem { Label("Workouts", systemImage: "stopwatch") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
