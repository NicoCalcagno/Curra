import XCTest
@testable import Curra

final class PlanEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        return calendar
    }()

    private var load: TrainingLoad {
        TrainingLoad(
            weeklyKilometers: 25,
            runCount7d: 3,
            daysSinceLastRun: 1,
            typicalEasyPaceSecPerKm: 360,
            estimated5KPaceSecPerKm: 300,
            longestRecentRunKm: 12,
            lastRunWasQuality: false
        )
    }

    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))! // a Monday
    }

    // MARK: - Volume progression

    func testVolumesNeverGrowMoreThanTenPercent() {
        let volumes = PlanEngine.weeklyVolumes(startKm: 20, peakKm: 55, weeks: 12)
        XCTAssertEqual(volumes.count, 12)

        var base = volumes[0]
        for (index, volume) in volumes.enumerated().dropFirst() {
            let isCutback = (index + 1) % 4 == 0 && index != volumes.count - 1
            let isTaper = index == volumes.count - 1
            if !isCutback && !isTaper {
                XCTAssertLessThanOrEqual(volume, base * 1.1 + 0.001, "week \(index)")
                base = volume
            }
        }
    }

    func testVolumesRespectPeak() {
        let volumes = PlanEngine.weeklyVolumes(startKm: 30, peakKm: 32, weeks: 10)
        XCTAssertTrue(volumes.allSatisfy { $0 <= 32.001 })
    }

    func testCutbackWeeksAreReduced() {
        let volumes = PlanEngine.weeklyVolumes(startKm: 20, peakKm: 55, weeks: 12)
        // Weeks 4 and 8 (indices 3, 7) are cutbacks: lower than the week before.
        XCTAssertLessThan(volumes[3], volumes[2])
        XCTAssertLessThan(volumes[7], volumes[6])
        // The week after a cutback resumes from the pre-cutback base.
        XCTAssertGreaterThan(volumes[4], volumes[3])
    }

    func testFinalWeekTapers() {
        let volumes = PlanEngine.weeklyVolumes(startKm: 20, peakKm: 55, weeks: 12)
        XCTAssertLessThan(volumes[11], volumes[10])
    }

    // MARK: - Generation

    func testGeneratesFullScheduleForEachRace() {
        for raceType in RaceType.allCases {
            let template = PlanTemplate.template(for: raceType)
            let specs = PlanEngine.generate(
                template: template,
                startDate: monday,
                load: load,
                calendar: calendar
            )
            XCTAssertEqual(specs.count, template.weekCount * template.sessions.count, "\(raceType)")

            // All dates inside the plan span, chronologically consistent per week.
            let sorted = specs.sorted { $0.date < $1.date }
            XCTAssertEqual(sorted.first?.date.timeIntervalSince(monday) ?? -1, 86_400 + 7 * 3600, accuracy: 3700 * 2, "first session on Tuesday morning")
        }
    }

    func testSessionsLandOnTemplateWeekdays() {
        let template = PlanTemplate.template(for: .tenK)
        let specs = PlanEngine.generate(template: template, startDate: monday, load: load, calendar: calendar)

        let expectedWeekdays = Set(template.sessions.map { offset -> Int in
            let date = calendar.date(byAdding: .day, value: offset.dayOffset, to: monday)!
            return calendar.component(.weekday, from: date)
        })
        for spec in specs {
            XCTAssertTrue(expectedWeekdays.contains(calendar.component(.weekday, from: spec.date)))
        }
    }

    func testFirstWeekAnchorsToCurrentLoadNotTemplatePeak() {
        let template = PlanTemplate.template(for: .half) // peak 55
        let specs = PlanEngine.generate(template: template, startDate: monday, load: load, calendar: calendar)

        let firstWeek = specs.filter { $0.date < monday.addingTimeInterval(7 * 86_400) }
        let weekKm = firstWeek.reduce(0.0) {
            $0 + $1.blueprint.estimatedDistanceMeters(referencePaceSecPerKm: 360) / 1000
        }
        // Anchored near the athlete's 25 km/week, far below the 55 km peak.
        XCTAssertLessThan(weekKm, 35)
        XCTAssertGreaterThan(weekKm, 15)
    }

    func testLongRunIsTheBiggestSessionOfTheWeek() {
        let template = PlanTemplate.template(for: .tenK)
        let specs = PlanEngine.generate(template: template, startDate: monday, load: load, calendar: calendar)
        let firstWeek = Array(specs.prefix(template.sessions.count))

        let distances = firstWeek.map {
            $0.blueprint.estimatedDistanceMeters(referencePaceSecPerKm: 360)
        }
        let longIndex = template.sessions.firstIndex { $0.kind == .long }!
        XCTAssertEqual(distances.max(), distances[longIndex])
    }

    func testQualitySessionsRotateAcrossWeeks() {
        let template = PlanTemplate.template(for: .fiveK)
        let specs = PlanEngine.generate(template: template, startDate: monday, load: load, calendar: calendar)
        let qualityNames = specs
            .filter { $0.blueprint.mode == .build }
            .map(\.blueprint.name)
        XCTAssertGreaterThan(Set(qualityNames).count, 1, "quality sessions vary across weeks")
    }

    // MARK: - Scaling (adaptation)

    func testScaledBlueprintReducesGoalsAndRounds() {
        let blueprint = PlanEngine.blueprint(
            for: .easy,
            kilometers: 10,
            weekIndex: 0,
            weekKm: 30,
            load: load
        )
        let scaled = PlanEngine.scaled(blueprint, factor: 0.85)

        guard case .distanceMeters(let meters) = scaled.blocks[0].steps[0].goal else {
            return XCTFail("expected distance goal")
        }
        XCTAssertEqual(meters, 8_500)
        XCTAssertEqual(meters.truncatingRemainder(dividingBy: 100), 0)
    }

    func testScaledLeavesOpenGoalsUntouched() {
        let open = WorkoutBlueprint(
            name: "X",
            mode: .explore,
            warmup: nil,
            blocks: [BlockBlueprint(
                steps: [StepBlueprint(purpose: .work, goal: .open, alert: nil, label: "open")],
                iterations: 1
            )],
            cooldown: nil
        )
        XCTAssertEqual(PlanEngine.scaled(open, factor: 0.85), open)
    }
}
