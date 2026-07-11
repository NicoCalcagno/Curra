import Foundation
import SwiftData

/// Orchestrates the active training plan: creation from a template, adherence
/// matching, light adaptation, and the rolling sync that keeps only the next
/// 7 days scheduled on the Watch (WorkoutKit visibility window).
///
/// Runs at launch and on every app foreground. A `BGAppRefreshTask` could push
/// the window forward without opening the app; deferred — opening the app once
/// every few days is enough to keep the 7-day window filled.
@MainActor
@Observable
final class TrainingPlanService {
    private let modelContext: ModelContext
    private let scheduler: WorkoutSchedulerService

    private(set) var lastError: String?

    init(modelContext: ModelContext, scheduler: WorkoutSchedulerService = WorkoutSchedulerService()) {
        self.modelContext = modelContext
        self.scheduler = scheduler
    }

    // MARK: - Plan lifecycle

    /// Creates and activates a plan starting next Monday, anchored to current load.
    func createPlan(raceType: RaceType, now: Date = .now) {
        guard activePlan() == nil else { return }

        let template = PlanTemplate.template(for: raceType)
        let startDate = Self.nextWeekStart(after: now)
        let load = currentLoad(now: now)

        let plan = TrainingPlan(
            name: "\(raceType.displayName) plan",
            raceType: raceType,
            startDate: startDate
        )
        modelContext.insert(plan)

        for spec in PlanEngine.generate(template: template, startDate: startDate, load: load) {
            guard let data = try? spec.blueprint.encoded() else { continue }
            let planned = PlannedWorkout(scheduledDate: spec.date, blueprintData: data)
            modelContext.insert(planned)
            planned.plan = plan
        }

        do {
            try modelContext.save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelPlan(_ plan: TrainingPlan, now: Date = .now) async {
        for planned in plan.plannedWorkouts
        where planned.status == .scheduledOnWatch && planned.scheduledDate > now {
            await scheduler.removeFromWatch(planned)
            planned.status = .pending
        }
        plan.isActive = false
        try? modelContext.save()
    }

    func activePlan() -> TrainingPlan? {
        var descriptor = FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.isActive })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Refresh (foreground + after sync)

    func refresh(now: Date = .now) async {
        guard let plan = activePlan() else { return }
        let load = currentLoad(now: now)

        applyAdherence(plan: plan, load: load, now: now)
        applyAdaptationIfNeeded(plan: plan, now: now)
        await rollingSync(plan: plan, now: now)

        try? modelContext.save()
    }

    // MARK: - Adherence

    private func applyAdherence(plan: TrainingPlan, load: TrainingLoad, now: Date) {
        let activities = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []

        let snapshots = plan.plannedWorkouts.compactMap { planned -> AdherenceEngine.PlannedSnapshot? in
            guard let blueprint = try? WorkoutBlueprint.decoded(from: planned.blueprintData) else {
                return nil
            }
            return AdherenceEngine.PlannedSnapshot(
                id: planned.id,
                date: planned.scheduledDate,
                estimatedDistanceMeters: blueprint.estimatedDistanceMeters(
                    referencePaceSecPerKm: load.typicalEasyPaceSecPerKm
                ),
                status: planned.status
            )
        }
        let runs = activities.map {
            AdherenceEngine.CompletedRun(id: $0.id, date: $0.startDate, distanceMeters: $0.distanceMeters)
        }

        let byID = Dictionary(uniqueKeysWithValues: plan.plannedWorkouts.map { ($0.id, $0) })
        for change in AdherenceEngine.evaluate(planned: snapshots, activities: runs, now: now) {
            switch change {
            case .completed(let plannedID, let activityID):
                byID[plannedID]?.status = .completed
                byID[plannedID]?.matchedActivityID = activityID
            case .skipped(let plannedID):
                byID[plannedID]?.status = .skipped
            }
        }
    }

    // MARK: - Adaptation

    /// ≥2 skips in the trailing week → scale next week's pending sessions ×0.85,
    /// at most once per plan-week (tracked outside the frozen SwiftData schema).
    private func applyAdaptationIfNeeded(plan: TrainingPlan, now: Date) {
        let skippedDates = plan.plannedWorkouts
            .filter { $0.status == .skipped }
            .map(\.scheduledDate)
        guard AdherenceEngine.shouldReduceNextWeek(skippedDates: skippedDates, now: now) else {
            return
        }

        let weekStart = GoalEngine.periodInterval(for: .weekly, containing: now).end
        let marker = "plan.adapted.\(plan.id.uuidString).\(Int(weekStart.timeIntervalSince1970))"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }

        let nextWeek = DateInterval(start: weekStart, duration: 7 * 86_400)
        for planned in plan.plannedWorkouts
        where planned.status == .pending
            && planned.scheduledDate >= nextWeek.start
            && planned.scheduledDate < nextWeek.end {
            if let blueprint = try? WorkoutBlueprint.decoded(from: planned.blueprintData),
               let data = try? PlanEngine.scaled(blueprint, factor: 0.85).encoded() {
                planned.blueprintData = data
            }
        }
        UserDefaults.standard.set(true, forKey: marker)
    }

    // MARK: - Rolling sync (±7-day WorkoutKit window)

    private func rollingSync(plan: TrainingPlan, now: Date) async {
        await scheduler.refreshAuthorization()
        guard scheduler.isAuthorized else { return }

        let window = DateInterval(start: now, duration: 7 * 86_400)
        for planned in plan.plannedWorkouts.sorted(by: { $0.scheduledDate < $1.scheduledDate })
        where planned.status == .pending
            && planned.scheduledDate >= window.start
            && planned.scheduledDate < window.end {
            do {
                try await scheduler.scheduleExisting(planned)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func currentLoad(now: Date) -> TrainingLoad {
        let activities = (try? modelContext.fetch(FetchDescriptor<Activity>())) ?? []
        return TrainingLoadCalculator.load(from: activities.map(\.summary), now: now)
    }

    static func nextWeekStart(after date: Date, calendar: Calendar = .current) -> Date {
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: date)
        return currentWeek?.end ?? date
    }
}
