import SwiftUI

struct ProjectPricingPicker: View {
    @Environment(\.usageFeatures) private var features
    private enum Choice: Hashable {
        case builtIn(Pricing)
        case preset(UUID)
    }

    @Binding var entry: Entry
    @Environment(\.locale) private var locale
    @ProtectedSetting(PricingCatalog.storageKey) private var savedCatalog = Data()

    private var catalog: PricingCatalog { PricingCatalog(data: savedCatalog) }

    var body: some View {
        let catalog = catalog
        Picker("Pricing", selection: selection) {
            ForEach(Pricing.allCases.filter { allows($0) || (entry.pricingPresetID == nil && $0 == entry.pricing) }, id: \.self) { basis in
                Text(catalog.name(for: basis, locale: locale)).tag(Choice.builtIn(basis))
            }
            ForEach(catalog.presets.filter { allows($0.basis) || $0.id == entry.pricingPresetID }) { preset in
                Text(preset.name).tag(Choice.preset(preset.id))
            }
            if let id = entry.pricingPresetID, !catalog.presets.contains(where: { $0.id == id }) {
                Text(entry.pricingTitle(in: locale)).tag(Choice.preset(id))
            }
        }
        .labelsHidden()
        .help("Pricing determines the rate, how costs are counted, and whether the line gets a rebate.")
    }

    private func allows(_ pricing: Pricing) -> Bool {
        features.teamPlanning || (pricing != .crew && pricing != .team)
    }

    private var selection: Binding<Choice> {
        Binding(get: {
            entry.pricingPresetID.map(Choice.preset) ?? .builtIn(entry.pricing)
        }, set: { choice in
            var updated = entry
            switch choice {
            case .builtIn(let basis):
                updated.pricing = basis
                updated.pricingPresetID = nil
                updated.pricingLabel = nil
            case .preset(let id):
                guard let preset = catalog.presets.first(where: { $0.id == id }) else { return }
                updated.pricing = preset.basis
                updated.pricingPresetID = id
                updated.pricingLabel = preset.name
            }
            entry = updated
        })
    }
}

struct PricingEditor: View {
    @Binding var estimate: Estimate
    @Environment(\.locale) private var locale
    @ProtectedSetting(DayRateLibrary.storageKey) private var libraryData = Data()
    @State private var editingTiers = false
    @State private var savingSchedule: DayRateSchedule?

    private var library: DayRateLibrary { DayRateLibrary(data: libraryData) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My day rates")
                Menu {
                    if !library.schedules.isEmpty {
                        Section("Saved rate schedules") {
                            ForEach(library.sortedSchedules) { saved in
                                Button(saved.name) { estimate.applyDayRates(saved) }
                            }
                        }
                    }
                    Button("Edit project rates…") { editingTiers = true }
                    Button("Save as rate schedule…") {
                        savingSchedule = DayRateSchedule(tiers: estimate.rateTiers)
                    }
                } label: {
                    if let name = estimate.appliedDayRateName { Text(name) }
                    else if estimate.customTiers == nil && estimate.schedule == .unconfigured { Text("Set project rates…") }
                    else { Text("Custom") }
                }.fixedSize()
                Spacer()
                Toggle("Count my fixed-rate days toward tiers", isOn: $estimate.countOverrides)
                    .help("Fixed-rate days keep their own price and can move your later progressive days into a lower tier.")
            }
            RateTierSummary(tiers: estimate.rateTiers)
        }
        .sheet(isPresented: $editingTiers) {
            RateTierEditor(tiers: estimate.rateTiers) { tiers in
                var updated = estimate
                updated.customTiers = tiers
                updated.appliedDayRateName = nil
                estimate = updated
            }.environment(\.locale, locale)
        }
        .sheet(item: $savingSchedule) { draft in
            RateTierEditor(name: draft.name, tiers: draft.tiers, saveNamed: { name, tiers in
                var latest = library
                var schedule = draft
                schedule.name = name
                schedule.tiers = tiers
                try latest.save(schedule)
                libraryData = try latest.encoded()
                estimate.applyDayRates(schedule)
            }).environment(\.locale, locale)
        }
    }
}

struct RateTierSummary: View {
    let tiers: [RateTier]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                if tiers.count == 1, let flat = tiers.first {
                    Text("Flat rate · \(euros(flat.rate)) per day")
                } else {
                    ForEach(tiers.indices, id: \.self) { index in
                        let start = index == 0 ? 1 : (tiers[index - 1].lastDay ?? 0) + 1
                        let label = tiers[index].lastDay.map { "\(start)–\($0)" } ?? "\(start)+"
                        Text("Days \(label) · \(euros(tiers[index].rate))")
                    }
                }
            }
        }.scrollIndicators(.hidden).font(.callout).foregroundStyle(.secondary)
    }
}

struct RateTierEditor: View {
    @State private var name: String
    @State private var tiers: [RateTier]
    @State private var error: String?
    let named: Bool
    let save: (String, [RateTier]) throws -> Void

    init(tiers: [RateTier], save: @escaping ([RateTier]) -> Void) {
        _name = State(initialValue: "")
        _tiers = State(initialValue: tiers)
        self.named = false
        self.save = { _, tiers in save(tiers) }
    }

    init(name: String, tiers: [RateTier], saveNamed: @escaping (String, [RateTier]) throws -> Void) {
        _name = State(initialValue: name)
        _tiers = State(initialValue: tiers)
        self.named = true
        self.save = saveNamed
    }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(named ? "Rate schedule" : "Producer day rates").font(.title2.bold())
            if named { TextField("Schedule name", text: $name) }
            Text("Enter the final day of each tier. The last tier applies to all later days.")
                .foregroundStyle(.secondary)

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Last day").gridColumnAlignment(.leading)
                        Text("Rate per day (EUR)")
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(tiers.indices, id: \.self) { index in
                        GridRow {
                            if index < tiers.count - 1 {
                                TextField("Last day", value: Binding(get: { tiers[index].lastDay ?? 1 }, set: { tiers[index].lastDay = $0 }), format: .number)
                                    .labelsHidden()
                            } else {
                                Text("No limit").foregroundStyle(.secondary)
                            }
                            TextField("Rate per day (EUR)", value: $tiers[index].rate, format: .number).labelsHidden()
                            if index < tiers.count - 1 {
                                Button("Remove tier", systemImage: "minus.circle", role: .destructive) {
                                    tiers.remove(at: index)
                                }
                                .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(minHeight: 130, maxHeight: 230)

            Button("Add tier", systemImage: "plus") {
                guard let final = tiers.last else { return }
                let lastDay = tiers.dropLast().last?.lastDay ?? 0
                guard lastDay < Int.max - 1 else { return }
                tiers.insert(RateTier(lastDay: lastDay + 1, rate: final.rate), at: tiers.count - 1)
            }
            if !RateTier.valid(tiers) {
                Text("Enter increasing day limits and nonnegative rates with up to two decimal places.")
                    .foregroundStyle(.secondary)
            }

            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save rates") {
                    do {
                        try save(name.trimmingCharacters(in: .whitespacesAndNewlines), tiers)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!RateTier.valid(tiers) || (named && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(22)
        .frame(width: 450)
    }
}

struct EstimatePhaseOptionsView: View {
    @Binding var phase: Phase
    var approvedThroughChange = false
    var canSetOption = true

    var body: some View {
        HStack(spacing: 15) {
            if approvedThroughChange {
                Text("Approved change order").font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("Scope", selection: $phase.option) {
                    Text("Included").tag(Optional<PhaseOption>.none)
                    ForEach(PhaseOption.allCases, id: \.self) {
                        Text(LocalizedStringKey($0.title)).tag(Optional($0))
                    }
                }.fixedSize().disabled(!canSetOption)
            }

            if phase.startDate != nil {
                DatePicker("Start", selection: start, displayedComponents: .date).fixedSize()
                DatePicker("End", selection: end, in: (phase.startDate ?? .now)..., displayedComponents: .date).fixedSize()
                Button("Clear phase dates", systemImage: "xmark.circle") {
                    var updated = phase
                    updated.startDate = nil
                    updated.endDate = nil
                    phase = updated
                }
                .labelStyle(.iconOnly)
            } else {
                Button("Add dates", systemImage: "calendar.badge.plus") {
                    let today = Calendar.current.startOfDay(for: .now)
                    var updated = phase
                    updated.startDate = today
                    updated.endDate = today
                    phase = updated
                }
            }
        }
    }

    private var start: Binding<Date> {
        Binding {
            phase.startDate ?? .now
        } set: { date in
            var updated = phase
            updated.startDate = date
            updated.endDate = max(date, updated.endDate ?? date)
            phase = updated
        }
    }

    private var end: Binding<Date> {
        Binding(get: { phase.endDate ?? phase.startDate ?? .now }, set: { phase.endDate = $0 })
    }
}

struct ChangeOrdersView: View {
    @Environment(\.usageFeatures) private var features
    @Environment(\.locale) private var locale
    @Binding var estimate: Estimate
    @State private var creating = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if (estimate.changeOrders ?? []).isEmpty {
                    Text("No change orders").foregroundStyle(.secondary)
                }
                ForEach(estimate.changeOrders ?? []) { change in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(change.title).font(.headline)
                            Text(change.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            if !change.notes.isEmpty {
                                Text(change.notes).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(euros(change.net)).monospacedDigit()
                        Text(LocalizedStringKey(change.status.rawValue))
                            .foregroundStyle(.secondary)
                        if let decided = change.decidedAt {
                            Text(decided.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if change.status == .pending {
                            Button("Approve") { estimate.decideChange(id: change.id, status: .approved) }
                            Button("Decline") { estimate.decideChange(id: change.id, status: .declined) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: {
            HStack {
                Text("Change orders")
                Spacer()
                Button("Add change order…", systemImage: "plus") { creating = true }
            }
        }
        .sheet(isPresented: $creating) {
            ChangeOrderEditor(options: availableOptions, optionFees: estimate.calculate(includingPendingOptions: true).phases) { order in
                estimate.changeOrders = (estimate.changeOrders ?? []) + [order]
            }.environment(\.locale, locale).environment(\.usageFeatures, features)
        }
    }

    private var availableOptions: [Phase] {
        let assigned = Set((estimate.changeOrders ?? []).filter { $0.status != .declined }.compactMap(\.sourcePhaseID))
        return estimate.pendingOptionPhases.filter { !assigned.contains($0.id) }
    }
}

private struct ChangeOrderEditor: View {
    @Environment(\.usageFeatures) private var features
    @Environment(\.locale) private var locale
    let options: [Phase]
    let optionFees: [UUID: Decimal]
    let save: (ChangeOrder) -> Void
    @State private var source: UUID?
    @State private var title = ""
    @State private var notes = ""
    @State private var fee: Decimal = 0
    @State private var internalCost: Decimal = 0
    @State private var vendorCost: Decimal = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New change order").font(.title2.bold())
            Form {
                Picker("Starting point", selection: $source) {
                    Text("New work").tag(Optional<UUID>.none)
                    ForEach(options) { phase in
                        Text(phase.displayName(in: locale)).tag(Optional(phase.id))
                    }
                }
                .onChange(of: source) {
                    if let option = options.first(where: { $0.id == source }) {
                        title = option.name
                        fee = optionFees[option.id] ?? 0
                    }
                }
                TextField("Title", text: $title)
                TextField("Scope or approval reference", text: $notes, axis: .vertical).lineLimit(3...5)
                TextField("Additional net fee (EUR)", value: $fee, format: .number)
                if source == nil && features.costControlling {
                    TextField("Planned internal cost (EUR)", value: $internalCost, format: .number)
                    TextField("Planned supplier cost (EUR)", value: $vendorCost, format: .number)
                }
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save change order") {
                    save(makeOrder())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          [fee, internalCost, vendorCost].contains { $0 < 0 || $0 != cents($0) })
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private func makeOrder() -> ChangeOrder {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var phase: Phase
        if let option = options.first(where: { $0.id == source }) {
            phase = option
            phase.id = UUID()
            phase.name = name
            phase.option = nil
            phase.entries = option.entries.map { line in
                var copy = line
                copy.id = UUID()
                return copy
            }
        } else {
            var entries: [Entry] = []
            if internalCost > 0 { entries.append(Entry(name: "Internal work", pricing: .producer, cost: internalCost)) }
            if vendorCost > 0 { entries.append(Entry(name: "Supplier work", pricing: .expense, cost: vendorCost)) }
            phase = Phase(name: name, entries: entries)
        }
        return ChangeOrder(sourcePhaseID: source, title: name, notes: notes, phase: phase, net: fee)
    }
}
