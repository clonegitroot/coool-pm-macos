import SwiftUI
import UniformTypeIdentifiers

@main
struct Studio: App {
    @StateObject private var access = LibraryAccess()
    @NSApplicationDelegateAdaptor(BackupQuitDelegate.self) private var backupQuitDelegate
    @AppStorage("appLanguage") private var language = AppLanguage.system
    @AppStorage("appAppearance") private var appearance = AppAppearance.system
    private var accent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(red: 0.31, green: 0.77, blue: 0.66, alpha: 1)
            }
            return NSColor(red: 0.08, green: 0.47, blue: 0.39, alpha: 1)
        })
    }
    var body: some Scene {
        Window("Coool PM", id: "library") {
            VaultGate(access: access) { LibraryView(beginFreshSetup: access.beginFreshSetup) }.environment(\.locale, language.locale).tint(accent).accentColor(accent)
                .preferredColorScheme(appearance.scheme)
                #if canImport(Sparkle)
                .task { _ = AppUpdates.shared }
                #endif
        }
            .defaultSize(width: 1230, height: 720)
            .commands {
                BusinessSettingsCommands(locale: language.locale)
                ProjectSaveCommands(locale: language.locale)
                BackupCommands(locale: language.locale)
                LibraryCommands(locale: language.locale)
                HelpCommands(locale: language.locale)
                #if canImport(Sparkle)
                AppUpdateCommands()
                #endif
            }
        Window(AppLanguage.text("Coool PM Help", fallback: "Coool PM Help", locale: language.locale), id: HelpWindow.id) {
            HelpView().environment(\.locale, language.locale).tint(accent)
                .preferredColorScheme(appearance.scheme)
        }
        .defaultSize(width: 1040, height: 740)
        .windowResizability(.contentMinSize)
        Window(AppLanguage.text("Coool PM Settings", fallback: "Coool PM Settings", locale: language.locale), id: BusinessSettingsWindow.id) {
            VaultGate(access: access) { BusinessSettings() }.environment(\.locale, language.locale).tint(accent).accentColor(accent)
                .preferredColorScheme(appearance.scheme)
        }
        .defaultSize(width: 1100, height: 710)
        .windowResizability(.contentMinSize)
    }
}

private extension AppAppearance {
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

func euros(_ amount: Decimal) -> String {
    amount.formatted(.currency(code: "EUR"))
}

enum ProjectTab: String, CaseIterable {
    case overview = "Overview"
    case estimate = "Estimate"
    case controlling = "Controlling"
    case documents = "Documents"
    case billing = "Billing"
}

struct SheetView: View {
    static let horizontalInset: CGFloat = 20
    @Environment(\.usageFeatures) private var features
    @Environment(\.locale) private var locale
    @Binding var estimate: Estimate
    let clients: [Client]
    let assignProjectNumber: () -> Void
    let saveDocuments: (Estimate) throws -> Void
    let recordInvoice: (String?, (String, Estimate) throws -> IssuedInvoice) throws -> Void
    var referenceProjects: [Project] = []
    @State private var structuredInvoice: IssuedInvoice?
    @State private var tab = ProjectTab.overview
    @State private var expandedPhases: Set<UUID> = []
    @AppStorage("localAIEnabled") private var localAIEnabled = false
    @State private var showingAI = false
    @State private var showingExport = false
    @State private var editingBilling = false

    private var projectMenu: ProjectMenuActions {
        ProjectMenuActions(showTab: { tab = $0 }, controlling: features.costControlling,
                           createDocument: { showingExport = true },
                           localAI: localAIEnabled ? { showingAI = true } : nil)
    }

    private var invoiceClient: Client? {
        clients.first { $0.id == (estimate.invoiceClientID ?? estimate.clientID) }?
            .recipient(attentionTo: estimate.invoiceContactID)
    }

    private func clientPicker(_ label: LocalizedStringKey, _ selection: Binding<UUID?>, fallback: LocalizedStringKey) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).frame(width: ProjectScopeFields.labelWidth, alignment: .trailing)
            Picker(label, selection: selection) {
                Text(fallback).tag(nil as UUID?)
                ForEach(clients.filter { $0.archivedAt == nil || $0.id == selection.wrappedValue }) { client in
                    Text("\(client.name) · \(client.number)").tag(Optional(client.id))
                }
            }.labelsHidden().frame(width: 326, alignment: .leading)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    TextField("Project name", text: Binding(
                        get: { estimate.title == Estimate.untitledTitle ? "" : estimate.title },
                        set: { estimate.title = $0 }
                    ), prompt: Text("Untitled production"))
                    .font(.largeTitle.bold()).textFieldStyle(.plain)
                    Picker("Project status", selection: Binding(get: { estimate.currentStatus }, set: { estimate.status = $0 })) {
                        ForEach(ProjectStatus.allCases, id: \.self) { Text($0.label(in: locale)) }
                    }.fixedSize()
                }
                HStack {
                    Picker("Project view", selection: $tab) {
                        ForEach(ProjectTab.allCases.filter { $0 != .controlling || features.costControlling }, id: \.self) { Text(LocalizedStringKey($0.rawValue)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer()
                    if localAIEnabled {
                        Button("Local AI…", systemImage: "sparkles") { showingAI = true }
                    }
                    if tab == .billing { Button("Payment terms…") { editingBilling = true } }
                    if tab == .overview || tab == .estimate { Button("Create document…", systemImage: "doc.badge.plus") { showingExport = true } }
                }
                .frame(height: 28)
            }
            .padding(.horizontal, Self.horizontalInset).padding(.top, 22).padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Group {
                switch tab {
                case .overview:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ProjectOverview(estimate: estimate, showEstimate: { tab = .estimate },
                                            showControlling: { tab = .controlling }, showDocuments: { tab = .documents },
                                            showBilling: { tab = .billing }, assignProjectNumber: assignProjectNumber)
                            if !features.costControlling {
                                ExternalCostsView(estimate: $estimate)
                            }
                            ProjectScopeFields(estimate: $estimate)
                            GroupBox("Project contacts") { projectContacts.padding(8) }
                        }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
                    }
                case .estimate: estimateContent
                case .controlling:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            workflowHeader("Project costs and profitability",
                                           detail: "Plan and book internal costs and track the project margin.",
                                           action: "Open supplier documents") { tab = .documents }
                            ControllingView(estimate: $estimate)
                        }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
                    }
                case .billing:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            workflowHeader("Client invoices and payments",
                                           detail: "Issue client invoices, record payments and review open balances.",
                                           action: "Open proposals and supplier documents") { tab = .documents }
                            InvoiceLedgerView(estimate: $estimate, createInvoice: { showingExport = true },
                                              recordInvoice: { invoice in
                                try recordInvoice(invoice.number) { _, _ in invoice }
                            }, issueCorrection: issueCorrection, exportStructured: { structuredInvoice = $0 },
                                              invoiceRecipient: invoiceClient)
                        }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
                    }
                case .documents:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            workflowHeader("Proposals and supplier documents",
                                           detail: "Create and approve proposals and attach invoices from suppliers.",
                                           action: "Open client invoices") { tab = .billing }
                            ProjectFilesView(estimate: $estimate, saveDocuments: saveDocuments, createDocument: { showingExport = true })
                        }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
                    }
                }
            }
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .focusedSceneValue(\.projectMenu, projectMenu)
        .onChange(of: features.costControlling) { _, enabled in
            if !enabled && tab == .controlling { tab = .overview }
        }
        .onChange(of: localAIEnabled) { _, enabled in
            if !enabled { showingAI = false }
        }
        .sheet(isPresented: $showingAI) {
            AIProjectAssistant(estimate: $estimate, referenceProjects: referenceProjects)
                .environment(\.locale, locale).environment(\.usageFeatures, features)
        }
        .sheet(isPresented: $editingBilling) {
            BillingEditor(schedule: estimate.billing ?? BillingSchedule(), net: estimate.issuedInstalment?.billingBasis ?? estimate.firstInstalment?.billingNet ?? estimate.currentBillableNet,
                          locked: estimate.issuedInstalment != nil || estimate.firstInstalment != nil,
                          defaultDays: ClientDocument().paymentDays(client: invoiceClient) ?? BusinessProfile.load().defaultPaymentDays ?? 30) { estimate.billing = $0 }
                .environment(\.locale, locale)
                .environment(\.usageFeatures, features)
        }
        .sheet(item: $structuredInvoice) { invoice in
            XRechnungEditor(invoice: invoice, precedingNumber: estimate.issuedInvoices?.first { $0.id == invoice.correctionOf }?.number,
                            buyerDefaults: invoiceClient?.name == invoice.recipient?.name ? invoiceClient?.electronicInvoice : nil) { artifact, report in
                if let index = estimate.issuedInvoices?.firstIndex(where: { $0.id == invoice.id }) {
                    var invoices = estimate.issuedInvoices ?? []
                    let names = Set([artifact.filename, report.filename])
                    invoices[index].files.removeAll { names.contains($0.filename) }
                    invoices[index].files += [artifact, report]
                    estimate.issuedInvoices = invoices
                }
            }.environment(\.locale, locale).environment(\.usageFeatures, features)
        }
        .sheet(isPresented: $showingExport) {
            DocumentPanel(estimate: $estimate, clients: clients, saveDocuments: saveDocuments,
                          recordInvoice: recordInvoice, startWithInvoice: tab == .billing, fixedKind: tab == .billing || tab == .documents)
                .environment(\.locale, locale)
                .environment(\.usageFeatures, features)
        }
    }

    private func workflowHeader(_ title: LocalizedStringKey, detail: LocalizedStringKey,
                                action: LocalizedStringKey, navigate: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                workflowTitle(title, detail: detail)
                Spacer()
                Button(action, systemImage: "arrow.right", action: navigate)
            }
            VStack(alignment: .leading, spacing: 8) {
                workflowTitle(title, detail: detail)
                Button(action, systemImage: "arrow.right", action: navigate)
            }
        }
    }

    private func workflowTitle(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold())
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private func issueCorrection(_ original: IssuedInvoice, reason: String, date: Date) throws {
        try recordInvoice(nil) { number, _ in
            var document = ClientDocument(invoice: true)
            document.invoiceName = "Stornorechnung"
            document.reference = number
            document.correctionReference = original.number
            document.purchaseOrder = original.purchaseOrder
            document.reimbursedCosts = (original.reimbursedCosts ?? []).map(\.reversed)
            document.scope = reason
            document.date = date
            document.sender = original.sender?.name ?? ""
            document.contactDetails = original.sender?.address ?? ""
            document.taxNumber = original.sender?.taxNumber ?? ""
            document.vatID = original.sender?.vatID ?? ""
            document.servicePeriod = original.servicePeriod
            document.vat = original.vatRate
            document.taxAmountOverride = -original.vat
            document.exemptionReason = original.vatExemptionReason ?? ""
            let client = original.recipient.map { Client(number: "", name: $0.name, contact: $0.contact, address: $0.address) }
            let pdf = try document.contents(project: original.projectName, recipient: client, fees: [PhaseFee(name: "", amount: -original.net, items: [])]).pdfData()
            let file = InvoiceArtifact(filename: "Storno-" + number + ".pdf", data: pdf)
            return IssuedInvoice(number: number, issueDate: date, dueDate: nil, title: document.title,
                                 projectName: original.projectName, sender: original.sender, recipient: original.recipient,
                                 servicePeriod: original.servicePeriod, paymentTerms: "", net: -original.net, vatRate: original.vatRate,
                                 vat: -original.vat, milestoneID: original.milestoneID, vatExemptionReason: original.vatExemptionReason, correctionOf: original.id,
                                 correctionReason: reason, files: [file], buyerReference: original.buyerReference,
                                 purchaseOrder: original.purchaseOrder, reimbursedCosts: document.reimbursedCosts)
        }
    }

    private var projectContacts: some View {
        Grid(alignment: .leading, horizontalSpacing: ProjectScopeFields.columnSpacing, verticalSpacing: 8) {
            clientPicker("Client / agency", Binding(get: { estimate.clientID }, set: { id in
                let client = clients.first { $0.id == id }
                var updated = estimate
                if updated.clientID != id {
                    updated.folderID = nil
                    updated.proposalContactID = nil
                    if updated.invoiceClientID == nil { updated.invoiceContactID = nil }
                }
                updated.clientID = id
                updated.client = client?.name ?? ""
                updated.clientNumber = client?.number ?? ""
                if !updated.calculationLocked { updated.clientRebatePercent = client?.rebatePercent }
                estimate = updated
            }), fallback: "Select client")
            clientPicker("End client", $estimate.endClientID, fallback: "Unassigned")
            clientPicker("Invoice recipient", Binding(get: { estimate.invoiceClientID }, set: { id in
                var updated = estimate
                updated.invoiceClientID = id
                updated.invoiceContactID = nil
                estimate = updated
            }), fallback: "Same as client / agency")
            contactPicker("Proposal contact", clientID: estimate.clientID, selection: $estimate.proposalContactID)
            contactPicker("Invoice contact", clientID: estimate.invoiceClientID ?? estimate.clientID, selection: $estimate.invoiceContactID)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contactPicker(_ label: LocalizedStringKey, clientID: UUID?, selection: Binding<UUID?>) -> some View {
        if let client = clients.first(where: { $0.id == clientID }), !client.activeContacts.isEmpty {
            GridRow {
                Text(label).frame(width: ProjectScopeFields.labelWidth, alignment: .trailing)
                Picker(label, selection: selection) {
                    Text("Primary contact").tag(UUID?.none)
                    ForEach(client.activeContacts) { contact in Text(contact.displayName).tag(Optional(contact.id)) }
                }.labelsHidden().frame(width: 326, alignment: .leading)
            }
        }
    }

    private func expansion(_ phaseID: UUID) -> Binding<Bool> {
        Binding(get: { expandedPhases.contains(phaseID) }, set: { expanded in
            if expanded { expandedPhases.insert(phaseID) }
            else { expandedPhases.remove(phaseID) }
        })
    }

    @ViewBuilder
    private var estimateContent: some View {
        if estimate.calculationLocked {
            lockedCalculation
        } else {
            editableCalculation
        }
    }

    private var lockedCalculation: some View {
        let result = estimate.calculate()
        let phaseBudgets = estimate.budget?.phases ?? estimate.billablePhases.map {
            CostBudget.PhaseBudget(phase: $0, sales: result.phases[$0.id] ?? 0)
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Calculation locked", systemImage: "lock.fill").font(.headline)
                        Text("The approved proposal fixes the base fee and scope. Use change orders for any adjustments.")
                            .foregroundStyle(.secondary)
                        LabeledContent("Approved base fee", value: euros(estimate.approvedBaseNet ?? result.totals.sales))
                        if result.rebate > 0 {
                            LabeledContent("Rebate applied", value: euros(result.rebate))
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(phaseBudgets) { budget in
                    GroupBox {
                        DisclosureGroup(isExpanded: expansion(budget.id)) {
                            VStack(alignment: .leading, spacing: 9) {
                                if budget.phase.entries.isEmpty { Text("No line items").foregroundStyle(.secondary) }
                                ForEach(budget.phase.entries) { entry in
                                    HStack(spacing: 16) {
                                        if entry.name.isEmpty { Text(entry.pricingTitle(in: locale)) }
                                        else { Text(entry.name) }
                                        Spacer()
                                        Text(entry.quantity.formatted(.number.locale(locale))).monospacedDigit()
                                    }
                                }
                            }.padding(.top, 12)
                        } label: {
                            LabeledContent(budget.phase.displayName(in: locale), value: euros(budget.sales)).fontWeight(.medium)
                        }.padding(8)
                    }
                }
                ChangeOrdersView(estimate: $estimate)
            }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
        }
    }

    private var editableCalculation: some View {
        let result = estimate.calculate()
        let withOptions = estimate.calculate(includingPendingOptions: true)
        let planningCosts = (estimate.externalCosts ?? []).compactMap(\.planned).reduce(0, +)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox {
                    HStack {
                        metric("Net estimate", result.totals.sales)
                        if result.rebate > 0 { metric("Rebate applied", result.rebate) }
                        if features.costControlling {
                            metric("Third-party costs", result.totals.external + planningCosts)
                            metric("DB1", result.totals.db1 - planningCosts)
                            metric("Own costs", result.totals.internalCost)
                            metric("DB2", result.totals.db2 - planningCosts)
                        }
                    }.padding(10)
                }
                PricingEditor(estimate: $estimate)
                if features.costControlling { ExternalCostsView(estimate: $estimate) }
                Form {
                    RebatePercentField("Project rebate (%)", percent: $estimate.projectRebatePercent)
                        .help("Overrides the client rebate for this project. Enter 0 to waive it, or leave blank to use the client default.")
                    if let percent = estimate.clientRebatePercent, percent > 0 {
                        LabeledContent("Client default rebate", value: (percent / 100).formatted(.percent.locale(locale)))
                    }
                }.formStyle(.columns)
                if !estimate.pendingOptionPhases.isEmpty {
                    LabeledContent("Net estimate including options", value: euros(estimate.calculate(includingPendingOptions: true).totals.sales))
                }
                Button("Generate standard phases", systemImage: "list.bullet.rectangle") {
                    estimate.generateStandardPhases()
                }
                .disabled(estimate.hasStandardPhases)
                ForEach($estimate.phases) { $phase in
                    GroupBox {
                        DisclosureGroup(isExpanded: expansion(phase.id)) {
                            VStack(alignment: .leading, spacing: 12) {
                                TextField("Phase name", text: Binding(
                                    get: { phase.displayName(in: locale) },
                                    set: { if $0 != phase.displayName(in: locale) { phase.name = $0 } }
                                )).font(.headline)
                                EstimatePhaseOptionsView(phase: $phase, approvedThroughChange: estimate.approvedChanges.contains { $0.sourcePhaseID == phase.id }, canSetOption: true)
                                Divider()
                                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                                    GridRow {
                                        ForEach(["Role / item", "Pricing", "Days / qty", "Hours / day", "Sell / unit"] + (features.costControlling ? ["Cost / unit"] : []) + ["Net fee", ""], id: \.self) { Text(LocalizedStringKey($0)).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    ForEach($phase.entries) { $line in
                                        GridRow {
                                            TextField("Role or item", text: $line.name).frame(minWidth: 120)
                                            ProjectPricingPicker(entry: $line).frame(width: 155)
                                            amount("Quantity", $line.quantity)
                                            if line.pricing.supportsDayLength {
                                                TextField("Hours per day", value: Binding(get: { line.effectiveHoursPerDay }, set: { line.hoursPerDay = min(24, max(0.25, $0)) }), format: .number)
                                                    .frame(width: 58).accessibilityLabel("Hours per day")
                                            } else { Text("–").foregroundStyle(.secondary) }
                                            if line.pricing == .producer { Text("Tiered").foregroundStyle(.secondary) }
                                            else { amount("Selling rate", $line.rate) }
                                            if features.costControlling { amount("Unit cost", $line.cost) }
                                            Text(euros((phase.option == .pending ? withOptions : result).lines[line.id] ?? 0)).monospacedDigit().frame(minWidth: 78, alignment: .trailing)
                                            Button { phase.entries.removeAll { $0.id == line.id } } label: {
                                                Image(systemName: "minus.circle")
                                            }.buttonStyle(.borderless).accessibilityLabel("Remove item")
                                                .disabled(estimate.hasActivity(on: line.id))
                                        }
                                    }
                                }
                                HStack {
                                    Button("Add item", systemImage: "plus") { phase.entries.append(Entry()) }
                                    Spacer()
                                    if phase.entries.isEmpty && !estimate.hasActivity(in: phase.id) {
                                        Button("Remove empty phase") { estimate.phases.removeAll { $0.id == phase.id } }
                                    }
                                }
                            }.padding(.top, 10)
                        } label: {
                            HStack {
                                if phase.name.isEmpty { Text("Untitled phase").font(.headline) }
                                else { Text(phase.displayName(in: locale)).font(.headline) }
                                Spacer()
                                if let option = phase.option {
                                    Text(LocalizedStringKey(option.title)).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(euros((phase.option == .pending ? withOptions : result).phases[phase.id] ?? 0))
                                    .monospacedDigit().fontWeight(.medium)
                            }
                        }.padding(8)
                    }
                }
                Button("Add phase", systemImage: "plus.rectangle.on.rectangle") {
                    let phase = Phase(name: "New phase")
                    estimate.phases.append(phase)
                    expandedPhases.insert(phase.id)
                }
                ChangeOrdersView(estimate: $estimate)
            }.padding(.horizontal, Self.horizontalInset).padding(.vertical, 28)
        }.frame(minWidth: 900, minHeight: 480)
    }

    private func metric(_ label: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
            Text(euros(value)).font(.title3.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amount(_ label: String, _ binding: Binding<Decimal>) -> some View {
        TextField(LocalizedStringKey(label), value: Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = max(0, $0) }), format: .number)
            .frame(width: 75).accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}
