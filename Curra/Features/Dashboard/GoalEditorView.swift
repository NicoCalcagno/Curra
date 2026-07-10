import SwiftData
import SwiftUI

struct GoalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GoalMaintenanceService.self) private var maintenance

    @State private var metric: GoalMetric = .distance
    @State private var period: GoalPeriodUnit = .weekly
    @State private var targetText = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Metric", selection: $metric) {
                    ForEach(GoalMetric.allCases, id: \.self) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                Picker("Period", selection: $period) {
                    ForEach(GoalPeriodUnit.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                HStack {
                    TextField("Target", text: $targetText)
                        .keyboardType(.decimalPad)
                    Text(metric.unitLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(targetInBaseUnit == nil)
                }
            }
        }
    }

    /// User input is in display units (km, hours); storage is meters/seconds/count.
    private var targetInBaseUnit: Double? {
        guard let value = Double(targetText.replacingOccurrences(of: ",", with: ".")),
              value > 0
        else { return nil }
        switch metric {
        case .distance: return value * 1000
        case .duration: return value * 3600
        case .runCount, .elevationGain: return value
        }
    }

    private func save() {
        guard let target = targetInBaseUnit else { return }
        modelContext.insert(Goal(metric: metric, period: period, targetValue: target))
        try? modelContext.save()
        maintenance.refresh()
        dismiss()
    }
}
