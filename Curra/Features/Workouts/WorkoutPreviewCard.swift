import SwiftUI

/// Renders a blueprint's structure and estimates before sending it to the Watch.
struct WorkoutPreviewCard: View {
    let blueprint: WorkoutBlueprint
    let referencePace: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(blueprint.name)
                .font(.headline)

            estimates

            VStack(alignment: .leading, spacing: 6) {
                if let warmup = blueprint.warmup {
                    stepRow(warmup, prefix: nil)
                }
                ForEach(Array(blueprint.blocks.enumerated()), id: \.offset) { _, block in
                    ForEach(Array(block.steps.enumerated()), id: \.offset) { _, step in
                        stepRow(step, prefix: block.iterations > 1 ? "\(block.iterations)×" : nil)
                    }
                }
                if let cooldown = blueprint.cooldown {
                    stepRow(cooldown, prefix: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var estimates: some View {
        let duration = blueprint.estimatedDurationSeconds(referencePaceSecPerKm: referencePace)
        let distance = blueprint.estimatedDistanceMeters(referencePaceSecPerKm: referencePace)

        return HStack(spacing: 16) {
            if duration > 0 {
                Label("≈ \(RunFormatters.duration(duration))", systemImage: "clock")
            }
            if distance > 0 {
                Label("≈ \(RunFormatters.distance(distance))", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func stepRow(_ step: StepBlueprint, prefix: String?) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(step.purpose == .work ? Color.orange : Color.blue.opacity(0.6))
                .frame(width: 8, height: 8)
            if let prefix {
                Text(prefix)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Text(step.label)
                .font(.subheadline)
            Spacer()
            if let alertLabel = alertLabel(step.alert) {
                Text(alertLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alertLabel(_ alert: StepAlert?) -> String? {
        switch alert {
        case nil:
            nil
        case .heartRateZone(let zone):
            "HR z\(zone)"
        case .paceRange(let minPace, let maxPace):
            "\(RunFormatters.pace(secondsPerKm: minPace))–\(RunFormatters.pace(secondsPerKm: maxPace))"
        }
    }
}
