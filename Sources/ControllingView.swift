import SwiftUI

struct ControllingView: View {
    @Environment(\.usageFeatures) private var features
    @Binding var estimate: Estimate
    @Environment(\.locale) private var locale
    @State private var selectedPhaseID: UUID?
    @State private var timeDraft: TimeRecord?
    @State private var costDraft: CostLineDraft?

    private var selectedPhase: Phase? {
        estimate.controlPhases.first { $0.id == selectedPhaseID }
    }

    private var displayedPhases: [Phase] {
        selectedPhase.map { [$0] } ?? estimate.controlPhases
    }

    private var timeRecords: [TimeRecord] {
        (estimate.timeRecords ?? [])
            .filter { selectedPhaseID == nil || $0.phaseID == selectedPhaseID }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if features.costControlling {
                HStack {
                    Text("Controlling").font(.title2.bold())
                    Spacer()
                    Picker("Production phase", selection: $selectedPhaseID) {
                        Text("Entire project").tag(Optional<UUID>.none)
                        ForEach(estimate.controlPhases) { phase in Text(phase.displayName(in: locale)).tag(Optional(phase.id)) }
                    }
                    .fixedSize()
                }

                baseline
                if estimate.acceptedImportedProposal != nil {
                    Text("The imported proposal supplies the total fee. Phase amounts come from your estimate or saved baseline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ControllingSummary(comparison: estimate.costs(for: selectedPhaseID), baseline: baselineTitle)
                ExternalCostsView(estimate: $estimate, phaseID: selectedPhaseID)
                costLines
                timeLog
            } else {
                ExternalCostsView(estimate: $estimate)
            }
        }
        .sheet(item: $timeDraft) { draft in
            TimeRecordEditor(record: draft, phases: estimate.controlPhases, save: saveTime)
                .environment(\.locale, locale)
        }
        .sheet(item: $costDraft) { draft in
            CostLineEditor(draft: draft, save: saveCostLine)
                .environment(\.locale, locale)
        }
        .onChange(of: estimate.controlPhases.map(\.id)) { _, ids in
            if let selectedPhaseID, !ids.contains(selectedPhaseID) { self.selectedPhaseID = nil }
        }
    }

    private var baselineTitle: String {
        if estimate.budget == nil { return "Current estimate" }
        return estimate.documents?.contains(where: { $0.id == estimate.acceptedProposalID && $0.costBudget != nil }) == true
            ? "Accepted budget"
            : "Saved baseline"
    }

    private var baseline: some View {
        HStack {
            if estimate.budget == nil {
                Text(estimate.acceptedProposalID == nil
                     ? "The comparison uses the current estimate until you accept a proposal or save a baseline."
                     : "This proposal was saved before cost snapshots. You can save the current estimate as a baseline.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save current estimate as baseline") { estimate.manualBudget = CostBudget(estimate) }
            } else {
                Text(LocalizedStringKey(baselineTitle)).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var costLines: some View {
        GroupBox("Planned costs") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(displayedPhases) { phase in
                    if !phase.entries.isEmpty {
                        Text(phase.displayName(in: locale)).font(.headline)
                        ForEach(phase.entries) { line in
                            let expected = estimate.commitments?[line.id]
                            let closed = estimate.completedCostLines?.contains(line.id) == true
                            let planned = cents(line.cost * line.quantity)
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.name.isEmpty ? line.pricingTitle(in: locale) : line.name)
                                    Text(closed ? "Complete" : (line.externalCost ? "Supplier cost" : "Internal cost"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text((expected ?? planned).formatted(.currency(code: "EUR"))).monospacedDigit()
                                Button("Edit cost…") {
                                    costDraft = CostLineDraft(id: line.id, title: line.name.isEmpty ? line.pricingTitle(in: locale) : line.name,
                                                              planned: planned, external: line.externalCost,
                                                              commitment: expected ?? planned, complete: closed)
                                }
                            }
                        }
                    }
                }
                if displayedPhases.allSatisfy({ $0.entries.isEmpty }) {
                    Text("No planned costs in this selection.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var timeLog: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if timeRecords.isEmpty {
                    Text("No time recorded in this selection.").foregroundStyle(.secondary)
                }
                ForEach(timeRecords) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            Text(timeLabel(record)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(record.days.formatted() + " d").monospacedDigit()
                        Text(cents(record.days * record.rate).formatted(.currency(code: "EUR")))
                            .monospacedDigit().frame(minWidth: 105, alignment: .trailing)
                        Button("Edit…") { timeDraft = record }
                        Button("Remove", systemImage: "minus.circle", role: .destructive) {
                            estimate.timeRecords?.removeAll { $0.id == record.id }
                        }
                        .labelStyle(.iconOnly)
                        .help("Remove time entry")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            HStack {
                Text("Own time")
                Spacer()
                Button("Record time…", systemImage: "plus") {
                    let phase = selectedPhase ?? estimate.controlPhases.first
                    let line = phase?.entries.first { $0.pricing.tracksInternalTime }
                    timeDraft = TimeRecord(phaseID: phase?.id, lineID: line?.id, rate: line?.cost ?? 0)
                }
            }
        }
    }

    private func timeLabel(_ record: TimeRecord) -> String {
        guard let phase = estimate.controlPhases.first(where: { $0.id == record.phaseID }) else {
            return AppLanguage.text("Project-wide", fallback: "Project-wide", locale: locale)
        }
        guard let name = phase.entries.first(where: { $0.id == record.lineID })?.name, !name.isEmpty else {
            return phase.displayName(in: locale)
        }
        return phase.displayName(in: locale) + " · " + name
    }

    private func saveTime(_ record: TimeRecord) {
        var records = estimate.timeRecords ?? []
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        estimate.timeRecords = records
    }

    private func saveCostLine(_ draft: CostLineDraft) {
        var updated = estimate
        if draft.external {
            var commitments = updated.commitments ?? [:]
            commitments[draft.id] = draft.commitment == draft.planned ? nil : draft.commitment
            updated.commitments = commitments
        }
        var completed = updated.completedCostLines ?? []
        if draft.complete { completed.insert(draft.id) }
        else { completed.remove(draft.id) }
        updated.completedCostLines = completed
        estimate = updated
    }
}

private struct ControllingSummary: View {
    let comparison: CostComparison
    let baseline: String

    var body: some View {
        GroupBox {
            Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Net amounts").gridColumnAlignment(.leading)
                    Text(LocalizedStringKey(baseline))
                    Text("Forecast")
                    Text("Actual to date")
                    Text("Forecast vs plan")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                row("Project fee basis", \.sales)
                row("Supplier costs", \.external)
                row("Internal costs", \.internalCost)
                row("DB1", \.db1).fontWeight(.semibold)
                row("DB2", \.db2).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        DisclosureGroup("Explain forecast differences") {
            if comparison.differences.isEmpty {
                Text("Forecast matches the plan.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        Text("Source").gridColumnAlignment(.leading)
                        Text("Revenue"); Text("Supplier costs"); Text("Internal costs")
                        Text("DB1"); Text("DB2")
                    }.font(.caption).foregroundStyle(.secondary)
                    ForEach(comparison.differences) { row in
                        GridRow {
                            Text(row.name)
                            Text(euros(row.revenue))
                            Text(euros(row.supplier))
                            Text(euros(row.internalCost))
                            Text(euros(row.db1))
                            Text(euros(row.db2))
                        }
                    }
                }.monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
        Text("Actual DB1 and DB2 compare recorded costs with the project fee basis. Forecast also includes expected costs still to come.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func row(_ label: String, _ key: KeyPath<Totals, Decimal>) -> some View {
        GridRow {
            Text(LocalizedStringKey(label))
            Text(comparison.planned[keyPath: key].formatted(.currency(code: "EUR")))
            Text(comparison.forecast[keyPath: key].formatted(.currency(code: "EUR")))
            Text(comparison.actual[keyPath: key].formatted(.currency(code: "EUR")))
            Text((comparison.forecast[keyPath: key] - comparison.planned[keyPath: key]).formatted(.currency(code: "EUR")))
        }
        .monospacedDigit()
    }
}

private struct CostLineDraft: Identifiable {
    let id: UUID
    let title: String
    let planned: Decimal
    let external: Bool
    var commitment: Decimal
    var complete: Bool
}

private struct CostLineEditor: View {
    @State var draft: CostLineDraft
    let save: (CostLineDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.title).font(.title2.bold())
            Form {
                LabeledContent("Planned cost", value: draft.planned.formatted(.currency(code: "EUR")))
                if draft.external {
                    TextField("Expected total (net EUR)", value: $draft.commitment, format: .number)
                    Text("Include amounts already billed in the expected total.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Cost complete", isOn: $draft.complete)
                    .help("Exclude any remaining estimate for this line from the forecast. Recorded costs stay in the totals.")
                Text("A complete item uses only recorded costs in the forecast.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    save(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.commitment < 0 || draft.commitment != cents(draft.commitment))
            }
        }
        .padding(20)
        .frame(width: 425)
    }
}

private struct TimeRecordEditor: View {
    @State var record: TimeRecord
    let phases: [Phase]
    let save: (TimeRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    private var timeLines: [Entry] {
        phases.first(where: { $0.id == record.phaseID })?.entries.filter {
            $0.pricing.tracksInternalTime
        } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Own time").font(.title2.bold())
            Form {
                DatePicker("Date", selection: $record.date, displayedComponents: .date)
                Picker("Production phase", selection: $record.phaseID) {
                    Text("Project-wide").tag(Optional<UUID>.none)
                    ForEach(phases) { phase in Text(phase.displayName(in: locale)).tag(Optional(phase.id)) }
                }
                .onChange(of: record.phaseID) { record.lineID = nil }
                Picker("Estimated time line", selection: $record.lineID) {
                    Text("Unplanned time").tag(Optional<UUID>.none)
                    ForEach(timeLines) { line in
                        Text(line.name.isEmpty ? line.pricingTitle(in: locale) : line.name).tag(Optional(line.id))
                    }
                }
                .onChange(of: record.lineID) {
                    if let line = timeLines.first(where: { $0.id == record.lineID }) { record.rate = line.cost }
                }
                TextField("Actual days", value: $record.days, format: .number)
                TextField("Internal cost per day (EUR)", value: $record.rate, format: .number)
                LabeledContent("Cost", value: cents(record.days * record.rate).formatted(.currency(code: "EUR")))
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    save(record)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(record.days <= 0 || record.rate < 0)
            }
        }
        .padding(20)
        .frame(width: 425)
    }
}
