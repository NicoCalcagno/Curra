import SwiftData
import SwiftUI

@main
struct CurraApp: App {
    private let container: ModelContainer
    @State private var syncCoordinator: ActivitySyncCoordinator
    @State private var goalMaintenance: GoalMaintenanceService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let schema = Schema([
            Activity.self,
            Goal.self,
            GoalPeriodRecord.self,
            Route.self,
            TrainingPlan.self,
            PlannedWorkout.self
        ])
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
            self.container = container
            _syncCoordinator = State(
                initialValue: ActivitySyncCoordinator(modelContext: container.mainContext)
            )
            _goalMaintenance = State(
                initialValue: GoalMaintenanceService(modelContext: container.mainContext)
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(syncCoordinator)
                .environment(goalMaintenance)
                .task {
                    syncCoordinator.onDataChanged = { [goalMaintenance] in
                        goalMaintenance.refresh()
                    }
                    goalMaintenance.refresh()
                    await syncCoordinator.start()
                }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                goalMaintenance.refresh()
            }
        }
    }
}
