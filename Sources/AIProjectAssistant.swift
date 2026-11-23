import SwiftUI

struct AIProjectAssistant: View {
    @Binding var estimate: Estimate
    var referenceProjects: [Project] = []
    @ProtectedSetting(PricingCatalog.storageKey) private var savedCatalog = Data()
    @State private var selectedReferenceIDs = Set<UUID>()
    @State private var referenceSearch = ""
    @State private var rateSource = ""
    @State private var draftRateReference: Estimate?
    @Environment(\.locale) private var locale
    @Environment(\.usageFeatures) private var features
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ai = LocalAIController.shared
    @State private var brief = ""
    @State private var mode = Mode.draft
    @State private var language = "en"
    @State private var draft: AIDraft?
    @State private var selected: Set<UUID> = []
    @State private var includeLetter = true
    @State private var edit: AIDraftEdit?
    @State private var applied = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var confirming = false
    @State private var generationID = UUID()
    @State private var retrying = false

    private enum Mode: String, CaseIterable {
        case draft = "Draft from brief", review = "Review calculation"
    }
    private var catalog: PricingCatalog { PricingCatalog(data: savedCatalog) }
    private var selectedReferences: [Project] { referenceProjects.filter { selectedReferenceIDs.contains($0.id) } }
    private var rateReference: Project? {
        guard rateSource != "current" else { return nil }
        return selectedReferences.first { $0.id.uuidString == rateSource } ?? selectedReferences.first
    }
    private var canDraft: Bool {
        !estimate.calculationLocked && estimate.archivedAt == nil && estimate.issuedInvoices?.isEmpty != false &&
        [.inquiry, .offered].contains(estimate.currentStatus)
    }
    private var needsRates: Bool {
        guard let draft else { return false }
        return draft.phases.filter { selected.contains($0.id) }.flatMap(\.lines).contains { line in
            line.basis == .producer ? selectedPreview.rateTiers.allSatisfy { $0.rate == 0 } : line.rate == 0
        }
    }

    private var usesReferenceSchedule: Bool {
        draftRateReference != nil && draft?.phases.filter { selected.contains($0.id) }.flatMap(\.lines).contains { $0.basis == .producer } == true
    }
    private var selectedPreview: Estimate {
        var copy = estimate
        if !applied, let draft {
            let additions = draft.selectedPhases(selected, language: language)
            if let reference = draftRateReference, additions.flatMap(\.entries).contains(where: { $0.pricing == .producer }) {
                AIReferencePricing.applyOwnRates(from: reference, to: &copy)
            }
            copy.phases += additions
        }
        return copy
    }

    @Environment(\.openWindow) private var openWindow

    private func openAISettings() {
        UserDefaults.standard.set(true, forKey: "localAISettingsRequested")
        openWindow(id: BusinessSettingsWindow.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Local AI", systemImage: "sparkles").font(.title2.bold())
                Spacer()
                Text(ai.statusText).font(.caption).foregroundStyle(.secondary)
                Button(action: openAISettings) { Image(systemName: "gearshape") }
                    .help("Open Local AI settings")
                    .accessibilityLabel("Open Local AI settings")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if !ai.enabled {
                Text("Enable local AI and download a model in Settings → Local AI to begin.")
                    .foregroundStyle(.secondary)
                Button("Open Local AI settings", action: openAISettings)
            } else {
                controls
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .review { checks }
                        if let draft { result(draft) }
                        references
                        context
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
                if applied {
                    HStack {
                        Label("Draft applied", systemImage: "checkmark.circle").foregroundStyle(.green)
                        Spacer()
                        Button("Undo applied draft") { undo() }
                    }
                }
            }
        }
        .padding(24).frame(width: 750, height: 700)
        .onAppear {
            language = locale.language.languageCode?.identifier == "de" ? "de" : "en"
            if !canDraft { mode = .review }
        }
        .onDisappear { generationID = UUID(); task?.cancel(); if task != nil { ai.cancel() } }
        .onChange(of: mode) { _, _ in if task == nil && !applied { draft = nil; edit = nil; error = nil } }
        .onChange(of: language) { _, _ in if task == nil && !applied { draft = nil; edit = nil; error = nil } }
        .confirmationDialog("Apply this draft?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Apply selected suggestions") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let base = "Selected phases will be appended to the calculation. Selected proposal text replaces the current introduction for this language."
            let rates = "The selected reference schedule replaces the project’s own progressive day rates, including existing positions. You can undo this change."
            Text(verbatim: AppLanguage.text(base, fallback: base, locale: locale) +
                 (usesReferenceSchedule ? "\n\n" + AppLanguage.text(rates, fallback: rates, locale: locale) : ""))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("AI action", selection: $mode) {
                    Text("Draft from brief").tag(Mode.draft).disabled(!canDraft)
                    Text("Review calculation").tag(Mode.review)
                }.pickerStyle(.segmented).labelsHidden().disabled(task != nil || applied)
                Picker("Draft language", selection: $language) {
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "English").tag("en")
                }.fixedSize().disabled(task != nil || applied)
            }
            TextField(mode == .review ? "What should the review focus on? (Optional)" : "Describe the project, deliverables, dates and known constraints…", text: $brief, axis: .vertical)
                .lineLimit(3...5).textFieldStyle(.roundedBorder).disabled(task != nil)
            HStack {
                Text("Only the project context listed below is used. Drafts remain in this window until you apply them.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if task != nil {
                    ProgressView().controlSize(.small)
                    Text(retrying ? "Retrying response…" : (mode == .review ? "Reviewing calculation…" : "Drafting production plan…"))
                        .font(.caption)
                    Button("Cancel generation") { generationID = UUID(); task?.cancel(); ai.cancel(); task = nil }
                } else {
                    Button(mode == .draft ? "Generate draft" : "Review calculation", systemImage: "sparkles") { generate() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ai.isBusy || (mode == .draft && brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || brief.count > 6_000)
                }
            }
            if brief.count > 6_000 { Text("Shorten the brief to 6,000 characters.").font(.caption).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var references: some View {
        if mode == .draft {
            referencePicker
        }
    }

    private var referencePicker: some View {
        DisclosureGroup("Reference projects (optional)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose up to two older projects as examples. Only selected projects are included; they remain unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Search reference projects", text: $referenceSearch).textFieldStyle(.roundedBorder)
                if referenceProjects.isEmpty {
                    Text("No other projects available.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(referenceProjects.filter {
                                referenceSearch.isEmpty || $0.estimate.title.localizedCaseInsensitiveContains(referenceSearch) ||
                                    ($0.estimate.projectNumber ?? "").localizedCaseInsensitiveContains(referenceSearch)
                            }) { project in
                                Toggle(isOn: Binding(get: { selectedReferenceIDs.contains(project.id) }, set: { selected in
                                    if selected { selectedReferenceIDs.insert(project.id) } else { selectedReferenceIDs.remove(project.id) }
                                    draft = nil; edit = nil; error = nil
                                })) {
                                    Text(project.estimate.displayTitle(in: locale))
                                    if let number = project.estimate.projectNumber, !number.isEmpty { Text(number).font(.caption).foregroundStyle(.secondary) }
                                }.disabled(task != nil || applied || (!selectedReferenceIDs.contains(project.id) && selectedReferenceIDs.count >= 2))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 140)
                }
                ForEach(selectedReferences) { Text($0.estimate.displayTitle(in: locale)).font(.caption.weight(.medium)) }
                if !selectedReferences.isEmpty {
                    Picker("Own day-rate schedule", selection: Binding(get: { rateReference?.id.uuidString ?? "current" }, set: { value in
                        rateSource = value; draft = nil; edit = nil; draftRateReference = nil; error = nil
                    })) {
                        Text("Keep current project rates").tag("current")
                        ForEach(selectedReferences) { Text($0.estimate.displayTitle(in: locale)).tag($0.id.uuidString) }
                    }.disabled(task != nil || applied)
                    Text("The selected schedule is used for own progressive work. Saved reference line prices and costs are copied when the role and pricing method match.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Reference summaries include up to three phases and four lines per phase, short scope text, rates and quantities. Contacts, documents and terms are excluded.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 6)
        }
    }

    private var context: some View {
        DisclosureGroup("Project context used by AI") {
            VStack(alignment: .leading, spacing: 5) {
                Text(estimate.displayTitle(in: locale)).fontWeight(.medium)
                if mode == .review {
                    Text("Included phases, selected line items, calculated net amounts and billing reconciliation.")
                    if features.costControlling { Text("The review includes calculated DB1 and DB2.") }
                } else {
                    Text("Current phase names, line descriptions, quantities, selling rates, producer rate tiers and project rebate.")
                    if features.costControlling { Text("Recorded line cost rates and planned external cost allowances are included.") }
                    Text("Available pricing categories and their calculation methods are included.")
                }
                Text("Contacts, bank details, tax identifiers, attached files and unselected projects are excluded.")
                if mode == .draft && !selectedReferences.isEmpty {
                    Text("Selected reference projects contribute compact scope and calculation summaries. Historical rates are reference values, not new agreements.")
                    ForEach(selectedReferences) { Text($0.estimate.displayTitle(in: locale)).fontWeight(.medium) }
                }
                Text("Output estimates are suggestions. The app calculates totals from the reviewed quantities and rates.")
            }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
        }
    }

    private var checks: some View {
        GroupBox("Calculation checks") {
            VStack(alignment: .leading, spacing: 6) {
                let result = estimate.calculate()
                LabeledContent("Net estimate", value: euros(result.totals.sales))
                if features.costControlling {
                    LabeledContent("DB1", value: euros(result.totals.db1))
                    LabeledContent("DB2", value: euros(result.totals.db2))
                }
                if deterministicChecks.isEmpty && duplicatePositionNames.isEmpty {
                    Label("No issues found by the built-in checks.", systemImage: "checkmark.circle").font(.callout)
                }
                ForEach(Array(deterministicChecks.enumerated()), id: \.offset) { _, finding in
                    Label(LocalizedStringKey(finding), systemImage: "exclamationmark.circle").font(.callout)
                }
                ForEach(duplicatePositionNames, id: \.self) { name in
                    Label("The same position appears in several phases: \(name)", systemImage: "exclamationmark.circle").font(.callout)
                }
                Text("Amounts above come from Coool PM’s calculation engine. AI findings below are advisory.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var duplicatePositionNames: [String] {
        var phasesByName: [String: Set<UUID>] = [:]
        var displayNames: [String: String] = [:]
        for phase in estimate.billablePhases {
            for item in phase.entries {
                let label = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !label.isEmpty else { continue }
                let normalized = label.lowercased()
                phasesByName[normalized, default: []].insert(phase.id)
                displayNames[normalized] = label
            }
        }
        return phasesByName.filter { $0.value.count > 1 }.keys
            .compactMap { displayNames[$0] }.sorted()
    }

    private var deterministicChecks: [String] {
        var values = [String]()
        if estimate.billablePhases.isEmpty { values.append("The calculation has no included phases.") }
        if estimate.billablePhases.flatMap(\.entries).contains(where: { $0.pricing == .producer }) && estimate.rateTiers.allSatisfy({ $0.rate == 0 }) {
            values.append("Producer day rates are still zero.")
        }
        if estimate.billablePhases.flatMap(\.entries).contains(where: { $0.quantity == 0 || ($0.pricing != .producer && $0.rate == 0) }) {
            values.append("Some line items have zero quantity or selling rate.")
        }
        if features.costControlling && estimate.calculate().totals.db2 < 0 { values.append("The calculation has a negative DB2.") }
        if let plan = estimate.billing, !plan.valid(net: estimate.currentBillableNet) { values.append("The billing schedule does not reconcile with the project fee.") }
        return values
    }

    @ViewBuilder private func result(_ draft: AIDraft) -> some View {
        if !draft.introduction.isEmpty && mode == .draft {
            Toggle("Use proposal introduction", isOn: $includeLetter).disabled(applied)
            TextEditor(text: Binding(get: { self.draft?.introduction ?? "" }, set: { self.draft?.introduction = $0 }))
                .font(.body).frame(minHeight: 100).disabled(applied)
        }
        notes("Assumptions", draft.assumptions)
        notes("Open questions", draft.questions)
        notes("AI review findings", draft.findings)
        if mode == .review && draft.findings.isEmpty && draft.questions.isEmpty && draft.assumptions.isEmpty {
            Label("AI review complete. The model returned no additional findings.", systemImage: "checkmark.circle")
        }
        if mode == .draft {
            ForEach(draft.phases) { phase in
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(phase.name, isOn: selection(phase.id)).font(.headline)
                        if !phase.scope.isEmpty { Text(phase.scope).font(.callout) }
                        if !phase.deliverables.isEmpty { Text(phase.deliverables).font(.callout).foregroundStyle(.secondary) }
                        ForEach(phase.lines) { line in
                            lineEditor(phaseID: phase.id, line: line)
                        }
                    }.padding(8)
                }.disabled(applied)
            }
            if !draft.phases.isEmpty {
                LabeledContent("Net estimate after selected additions", value: euros(selectedPreview.calculate().totals.sales))
                if usesReferenceSchedule, let reference = draftRateReference {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text("Own day-rate schedule"); Text(verbatim: reference.title) }.font(.caption.weight(.medium))
                        ForEach(Array(reference.rateTiers.enumerated()), id: \.offset) { _, tier in
                            HStack {
                                if let last = tier.lastDay { Text("Through day \(last)") } else { Text("Following days") }
                                Spacer()
                                Text(euros(tier.rate))
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Review quantities and enter agreed fixed or unit prices. Own progressive work uses this project’s saved day-rate tiers.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if needsRates {
                Label("Some positions have no price yet. You can apply the draft and fill them in later; the total is incomplete.", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !applied {
                Button("Apply selected suggestions") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canDraft || (selected.isEmpty && (!includeLetter || draft.introduction.isEmpty)))
            }
        }
    }

    private func selection(_ id: UUID) -> Binding<Bool> {
        Binding(get: { selected.contains(id) }, set: { if $0 { selected.insert(id) } else { selected.remove(id) } })
    }

    private func lineEditor(phaseID: UUID, line: AIDraft.Line) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Role / position").font(.caption).foregroundStyle(.secondary)
            TextField("Role / position", text: Binding(get: {
                draft?.phases.first { $0.id == phaseID }?.lines.first { $0.id == line.id }?.role ?? ""
            }, set: { role in updateLine(phaseID, line.id) { $0.role = role } }))
                .textFieldStyle(.roundedBorder).help("Name the actual service or position, independently of its pricing method.")
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pricing").font(.caption).foregroundStyle(.secondary).frame(height: 30, alignment: .bottomLeading)
                    Picker("Pricing", selection: Binding(get: {
                        line.pricingPresetID.map { "preset:" + $0.uuidString.lowercased() } ?? line.basis.map(AIPricing.token) ?? line.pricing
                    }, set: { token in
                        guard let option = AIPricing.options(catalog: catalog, teamPlanning: features.teamPlanning, locale: locale).first(where: { $0.id == token }) else { return }
                        updateLine(phaseID, line.id) {
                            if $0.basis != option.basis { $0.rate = 0; $0.cost = 0; $0.referenceSource = nil; $0.referenceLineID = nil; $0.hoursPerDay = nil }
                            $0.pricing = AIPricing.token(option.basis)
                            $0.pricingPresetID = option.presetID
                            $0.pricingLabel = option.presetID == nil ? nil : option.label
                        }
                    })) {
                        ForEach(AIPricing.options(catalog: catalog, teamPlanning: features.teamPlanning, locale: locale)) {
                            Text($0.label).tag($0.id)
                        }
                    }.labelsHidden()
                        .help("Pricing determines the rate, how costs are counted, and whether the line gets a rebate.")
                }.frame(maxWidth: .infinity, alignment: .leading)
                numberField(line.basis?.supportsDayLength == true ? "Days" : "Units", phaseID: phaseID, line: line, key: \.quantity, width: 65)
                if line.basis == .producer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Own day rates").font(.caption).foregroundStyle(.secondary).frame(height: 30, alignment: .bottomLeading)
                        Text("Tiered").foregroundStyle(.secondary).frame(height: 24)
                    }.frame(width: 140, alignment: .leading)
                } else {
                    numberField(line.basis?.supportsDayLength == true ? "Selling rate / day (EUR)" : "Selling price / unit (EUR)", phaseID: phaseID, line: line, key: \.rate, width: 140)
                }
                if features.costControlling {
                    let supplier = line.basis == .crew || line.basis == .expense
                    let daily = line.basis?.supportsDayLength == true
                    numberField(supplier ? (daily ? "Supplier cost / day (EUR)" : "Supplier cost / unit (EUR)") : (daily ? "Internal cost / day (EUR)" : "Internal cost / unit (EUR)"), phaseID: phaseID, line: line, key: \.cost, width: 140)
                }
            }
            if let source = line.referenceSource {
                HStack(spacing: 4) { Text("Rates from reference:"); Text(verbatim: source) }
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }

    private func numberField(_ label: LocalizedStringKey, phaseID: UUID, line: AIDraft.Line, key: WritableKeyPath<AIDraft.Line, Decimal>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(height: 30, alignment: .bottomLeading)
            TextField(label, value: lineValue(phaseID, line.id, key), format: .number)
                .labelsHidden().textFieldStyle(.roundedBorder).accessibilityLabel(label)
        }.frame(width: width, alignment: .leading)
    }

    private func updateLine(_ phaseID: UUID, _ lineID: UUID, edit: (inout AIDraft.Line) -> Void) {
        guard let phase = draft?.phases.firstIndex(where: { $0.id == phaseID }),
              let line = draft?.phases[phase].lines.firstIndex(where: { $0.id == lineID }) else { return }
        edit(&draft!.phases[phase].lines[line])
    }

    private func lineValue(_ phaseID: UUID, _ lineID: UUID, _ key: WritableKeyPath<AIDraft.Line, Decimal>) -> Binding<Decimal> {
        Binding(get: {
            draft?.phases.first { $0.id == phaseID }?.lines.first { $0.id == lineID }?[keyPath: key] ?? 0
        }, set: { value in
            guard let phase = draft?.phases.firstIndex(where: { $0.id == phaseID }),
                  let line = draft?.phases[phase].lines.firstIndex(where: { $0.id == lineID }) else { return }
            draft?.phases[phase].lines[line][keyPath: key] = value
        })
    }

    @ViewBuilder private func notes(_ title: LocalizedStringKey, _ values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text("• " + value).textSelection(.enabled) }
            }
        }
    }

    private func generate() {
        error = nil
        draft = nil
        applied = false
        selected = []
        draftRateReference = nil
        do {
            let review = mode == .review
            let requestEstimate = estimate
            let requestLanguage = language
            let requestBrief = brief
            let requestReferences = review ? [] : selectedReferences
            let requestRateReference = review ? nil : rateReference?.estimate
            let requestCatalog = catalog
            edit = review ? nil : try AIDraftEdit(estimate: requestEstimate, language: requestLanguage)
            let prompt = try AIPrompt.make(estimate: requestEstimate, brief: requestBrief, language: requestLanguage,
                                          review: review, features: features, catalog: requestCatalog,
                                          references: requestReferences, compactReview: true)
            let outputBudget = review ? 650 : (requestReferences.isEmpty ? 1_850 : 1_550)
            retrying = false
            let requestID = UUID()
            generationID = requestID
            task = Task { @MainActor in
                defer { if generationID == requestID { task = nil } }
                do {
                    let output = try await ai.generate(prompt: prompt, maxTokens: outputBudget)
                    try Task.checkCancellation()
                    guard generationID == requestID else { return }
                    let result: AIDraft
                    do {
                        result = try AIDraft.decode(output, teamPlanning: features.teamPlanning, catalog: requestCatalog, language: requestLanguage, review: review, references: requestReferences, includeCosts: features.costControlling)
                    } catch {
                        try Task.checkCancellation()
                        retrying = true
                        let retryMode = review
                            ? "Return only the findings and questions arrays, with up to three short items each."
                            : "Keep the delivery stages and explicit positions. Shorten descriptions and use exact pricing tokens."
                        let retry = prompt + "\nThe previous attempt did not pass validation. Return one complete JSON object. " + retryMode
                        let corrected = try await ai.generate(prompt: retry, maxTokens: outputBudget)
                        try Task.checkCancellation()
                        guard generationID == requestID else { return }
                        result = try AIDraft.decode(corrected, teamPlanning: features.teamPlanning, catalog: requestCatalog, language: requestLanguage, review: review, references: requestReferences, includeCosts: features.costControlling)
                    }
                    draft = result
                    draftRateReference = requestRateReference
                    selected = Set(result.phases.map(\.id))
                } catch is CancellationError {
                    if generationID == requestID && !Task.isCancelled {
                        self.error = ai.errorMessage ?? AppLanguage.text("Local AI stopped before returning a result.",
                                                                         fallback: "Local AI stopped before returning a result.", locale: locale)
                    }
                }
                catch { if generationID == requestID { self.error = error.localizedDescription } }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func apply() {
        guard let draft, var edit else { return }
        do {
            var updated = estimate
            try edit.apply(draft, selected: selected, includeLetter: includeLetter, to: &updated, teamPlanning: features.teamPlanning, rateReference: draftRateReference)
            estimate = updated
            self.edit = edit
            applied = true
        } catch { self.error = error.localizedDescription }
    }
    private func undo() {
        guard let edit else { return }
        do {
            var updated = estimate
            try edit.undo(in: &updated)
            estimate = updated
            applied = false
            self.edit = try AIDraftEdit(estimate: updated, language: language)
        } catch { self.error = error.localizedDescription }
    }
}
