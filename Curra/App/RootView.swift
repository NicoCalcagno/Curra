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

            PlansView()
                .tabItem { Label("Plan", systemImage: "calendar") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
