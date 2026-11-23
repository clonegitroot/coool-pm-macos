import SwiftUI

struct ProjectScopeFields: View {
    @Binding var estimate: Estimate
    static let labelWidth: CGFloat = 156
    static let columnSpacing: CGFloat = 12

    var body: some View {
        GroupBox("Project details") {
            Grid(alignment: .leading, horizontalSpacing: Self.columnSpacing, verticalSpacing: 8) {
                GridRow {
                    rowLabel("Purchase order")
                    TextField("Purchase order", text: Binding(
                        get: { estimate.purchaseOrder ?? "" },
                        set: { estimate.purchaseOrder = $0.isEmpty ? nil : $0 }
                    ))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .help("The buyer’s order reference appears on invoices.")
                }
                GridRow {
                    Color.clear.frame(width: Self.labelWidth, height: 1).accessibilityHidden(true)
                    Toggle("Planned project dates", isOn: Binding(
                        get: { estimate.plannedStart != nil },
                        set: { enabled in
                            estimate.plannedStart = enabled ? .now : nil
                            estimate.plannedEnd = estimate.plannedStart
                        }
                    ))
                }
                if let start = estimate.plannedStart {
                    GridRow {
                        rowLabel("Start")
                        HStack(spacing: 12) {
                            DatePicker("Start", selection: Binding(
                                get: { estimate.plannedStart ?? start },
                                set: { date in
                                    estimate.plannedStart = date
                                    if (estimate.plannedEnd ?? date) < date { estimate.plannedEnd = date }
                                }
                            ), displayedComponents: .date)
                            .labelsHidden()
                            DatePicker("End", selection: Binding(
                                get: { max(start, estimate.plannedEnd ?? start) },
                                set: { estimate.plannedEnd = $0 }
                            ), in: start..., displayedComponents: .date)
                        }
                    }
                }
            }.padding(8)
        }
    }

    private func rowLabel(_ title: LocalizedStringKey) -> some View {
        Text(title).frame(width: Self.labelWidth, alignment: .trailing)
    }
}

struct ExternalCostsView: View {
    @Environment(\.usageFeatures) private var features
    @Binding var estimate: Estimate
    var phaseID: UUID?
    @State private var editing: ProjectExternalCost?
    @Environment(\.locale) private var locale

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(features.costControlling ? "Plan supplier costs privately or book an expense at its actual net cost." : "Record expenses and choose whether to bill them to the client.").font(.callout).foregroundStyle(.secondary)
                ForEach(estimate.effectiveExternalCosts.filter { phaseID == nil || $0.phaseID == phaseID }) { cost in
                    let locked = estimate.invoicedCostIDs.contains(cost.id)
                    let linked = estimate.linkedExternalCostIDs.contains(cost.id)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(cost.title)
                            if linked { Text("Linked supplier invoice").font(.caption).foregroundStyle(.secondary) }
                            if locked { Text("Invoiced").font(.caption).foregroundStyle(.secondary) }
                            else if cost.reimbursable { Text("Bill at cost").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if features.costControlling, let planned = cost.planned { Text("Planned \(euros(planned))").foregroundStyle(.secondary) }
                        if let actual = cost.booked { Text("Booked \(euros(actual))").monospacedDigit() }
                        Button("Edit…") { editing = cost }.disabled(locked || linked)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text("External costs")
                Spacer()
                Button("Add cost…", systemImage: "plus") { editing = ProjectExternalCost(phaseID: phaseID) }
            }
        }
        .sheet(item: $editing) { draft in
            ExternalCostEditor(draft: draft, phases: estimate.controlPhases) { saved in
                var costs = estimate.externalCosts ?? []
                if let index = costs.firstIndex(where: { $0.id == saved.id }) { costs[index] = saved }
                else { costs.append(saved) }
                estimate.externalCosts = costs
            }.environment(\.locale, locale).environment(\.usageFeatures, features)
        }
    }
}

private struct ExternalCostEditor: View {
    @Environment(\.usageFeatures) private var features
    @Environment(\.locale) private var locale
    @State var draft: ProjectExternalCost
    let phases: [Phase]
    let save: (ProjectExternalCost) -> Void
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (draft.booked != nil || draft.planned != nil) &&
        [draft.booked, draft.planned].compactMap { $0 }.allSatisfy { $0 >= 0 && $0 == cents($0) } &&
        (!draft.reimbursable || (draft.booked ?? 0) > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("External cost").font(.title2.bold())
            Form {
                TextField("Description", text: $draft.title)
                if features.costControlling {
                Picker("Production phase", selection: $draft.phaseID) {
                    Text("Project-wide").tag(UUID?.none)
                    ForEach(phases) { Text($0.displayName(in: locale)).tag(Optional($0.id)) }
                }
                TextField("Planned net cost (EUR)", value: $draft.planned, format: .number)
                    .help("Leave blank for an unforeseen expense.")
                }
                TextField("Booked net cost (EUR)", value: $draft.booked, format: .number)
                    .help("Leave blank until the actual cost is known.")
                if draft.booked != nil {
                    DatePicker("Booking date", selection: $draft.date, displayedComponents: .date)
                    Toggle("Bill at cost", isOn: $draft.reimbursable)
                        .help("Offer this amount as a separate position on the next invoice.")
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(draft)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.onChange(of: draft.booked) { _, booked in if booked == nil { draft.reimbursable = false } }
        .padding(22).frame(width: 470)
    }
}
