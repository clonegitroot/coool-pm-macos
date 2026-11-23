import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct DocumentPanel: View {
    @Environment(\.usageFeatures) private var features
    @Binding var estimate: Estimate
    let clients: [Client]
    let saveDocuments: (Estimate) throws -> Void
    let recordInvoice: (String?, (String, Estimate) throws -> IssuedInvoice) throws -> Void
    var startWithInvoice = false
    var fixedKind = false
    @AppStorage("documentLanguage") private var defaultLanguage = AppLanguage.german
    @State private var showText = false
    @State private var showOptions = false
    @State private var excludedCosts = Set<UUID>()
    @State private var remainingBalance = false
    @State private var adjustment: Decimal?
    @State private var adjustmentReason = ""
    @State private var showIssueConfirmation = false
    @State private var options = ClientDocument()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @State private var selectedStage: UUID?
    @State private var overrideDate: Date?
    @State private var pdf = false
    @State private var preview: PDFDocument?
    @State private var previewOpen = false
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(fixedKind ? (startWithInvoice ? "Create invoice" : "Create proposal") : "Create document")
                    .font(.title2.bold())
                Spacer()
                if !fixedKind {
                    Picker("Document", selection: $options.invoice) {
                        Text("Proposal").tag(false)
                        Text("Invoice").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
            }.padding(20)
            Divider()
            Form {
                readiness
                essentials
                DisclosureGroup("Document text", isExpanded: $showText) { documentText }
                DisclosureGroup("Export and billing options", isExpanded: $showOptions) { exportOptions }
            }.formStyle(.grouped)
            if !error.isEmpty {
                Text(error).foregroundStyle(.red).padding(.horizontal, 20).padding(.vertical, 8)
            }
            Divider()
            actions.padding(20)
        }.frame(width: 620, height: 620)
        .sheet(isPresented: $previewOpen) {
            VStack { SettingsPreview(document: preview); Button("Done") { previewOpen = false } }.padding().frame(width: 630, height: 700)
                .environment(\.locale, locale)
        }
        .confirmationDialog("Issue this invoice?", isPresented: $showIssueConfirmation) {
            Button("Issue invoice", action: issue)
        } message: {
            Text("Coool PM will record the invoice number, amounts, and document in Billing.")
        }
        .onChange(of: stage?.id) { _, _ in adjustment = nil; adjustmentReason = "" }
        .onChange(of: options.invoice) { _, _ in adjustment = nil; adjustmentReason = "" }
        .onAppear {
            options.invoice = startWithInvoice
            options.german = defaultLanguage == .german
            let profile = BusinessProfile.load()
            options.vat = Decimal(profile.vat)
            options.detailed = profile.detailed
            options.exemptionReason = profile.defaultExemptionReason ?? ""
        }
    }

    private var essentials: some View {
        Section {
            Picker("Language", selection: $options.german) {
                Text("Deutsch").tag(true)
                Text("English").tag(false)
            }
            if let company = recipientCompany {
                LabeledContent("Recipient", value: company.name)
                if !company.activeContacts.isEmpty {
                    Picker("Attention to", selection: contactSelection) {
                        Text("Primary contact").tag(UUID?.none)
                        ForEach(company.activeContacts) { person in
                            Text(person.displayName).tag(Optional(person.id))
                        }
                    }
                }
            } else {
                LabeledContent("Recipient", value: String(localized: "Missing", locale: locale))
                    .foregroundStyle(.red)
            }
            if options.invoice {
                if let plan = billingPlan, !plan.stages.isEmpty {
                    Picker("Invoice milestone", selection: Binding(get: { stage?.id }, set: { remainingBalance = $0 == nil; selectedStage = $0 })) {
                        Text("Remaining balance").tag(UUID?.none)
                        ForEach(plan.stages) { item in
                            Text(item.title(german: options.german) + " · " + item.shareLabel(locale: configured.locale)).tag(Optional(item.id))
                        }
                    }
                }
                if !estimate.openReimbursements.isEmpty {
                    DisclosureGroup("Reimbursable costs") {
                        ForEach(estimate.openReimbursements) { item in
                            Toggle(item.title + " · " + euros(item.amount), isOn: Binding(
                                get: { !excludedCosts.contains(item.id) },
                                set: { include in
                                    if include { excludedCosts.remove(item.id) } else { excludedCosts.insert(item.id) }
                                }))
                        }
                    }
                }
            }
            RichField("Service period", text: draft(\.period), height: 42)
            TextField("Document number", text: reference, prompt: options.invoice ? Text("Assigned when issued") : nil)
            DatePicker("Document date", selection: Binding(get: { overrideDate ?? .now }, set: { overrideDate = $0 }), displayedComponents: .date)
            if overrideDate != nil { Button("Use today") { overrideDate = nil } }
            TextField("VAT (%)", value: $options.vat, format: .number.locale(locale))
                .help("Use 0 for an invoice with no VAT and enter the exemption reason below.")
            if options.invoice && options.vat == 0 {
                TextField("VAT exemption reason", text: $options.exemptionReason)
            }
            if options.invoice, let filename = accepted?.filename ?? estimate.acceptedImportedProposal?.name {
                LabeledContent("Fee basis", value: filename).lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("Net amount", value: netAmount.formatted(.currency(code: "EUR").locale(locale)))
                .monospacedDigit()
        } header: {
            Text("Document details")
        }
    }

    @ViewBuilder private var readiness: some View {
        let checks = options.invoice ? invoiceChecks : proposalChecks
        if !checks.isEmpty {
            Section {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    Label(check, systemImage: "exclamationmark.circle.fill").font(.callout)
                        .foregroundStyle(options.invoice ? Color.red : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if options.invoice && validVAT {
                    Text("You can still export a draft.").font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text(options.invoice ? "Required before issuing" : "Review before export").fontWeight(.semibold)
            }
        }
        if options.invoice {
            let notes = invoiceExportNotes
            if !notes.isEmpty {
                Section("Review before export") {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if let hint = pdfTemplateHint {
            Section {
                Label(hint, systemImage: "doc.badge.gearshape").font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var documentText: some View {
        RichField(options.invoice ? "Invoice introduction" : "Cover letter", text: draft(\.letter))
        if !options.invoice {
            RichField("Optional project terms", text: draft(\.terms))
            if !WordTemplate(document: options).installed {
                if estimate.calculationLocked {
                    Text("The approved proposal’s phase text is locked.").font(.callout).foregroundStyle(.secondary)
                    ForEach(estimate.calculationBasis.phases) { phase in
                        DisclosureGroup(phase.displayName(in: locale)) {
                            lockedText("Included services", phase.scopes?[language])
                            lockedText("Deliverables", phase.deliverables?[language])
                        }
                    }
                } else {
                    ForEach($estimate.phases) { $phase in
                        DisclosureGroup(phase.displayName(in: locale)) {
                            RichField("Included services", text: localized($phase.scopes))
                            RichField("Deliverables", text: localized($phase.deliverables))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func lockedText(_ title: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent {
                Text(InlineText.runs(value).map(\.text).joined()).textSelection(.enabled)
            } label: {
                Text(title)
            }
        }
    }

    @ViewBuilder private var exportOptions: some View {
        if WordTemplate(document: options).installed {
            Text(pdf ? "Using imported DOCX template · PDF rendered by Pages" : "Using imported DOCX template")
                .foregroundStyle(.secondary)
        } else if !options.invoice {
            Picker("Proposal layout", selection: $options.detailed) {
                Text("Compact scope").tag(false)
                Text("Detailed scope and phase fees").tag(true)
            }
        }
        Picker("Format", selection: $pdf) {
            Text("Editable Word (.docx)").tag(false)
            Text("PDF").tag(true)
        }
        if options.invoice {
            TextField("Invoice title", text: invoiceName, prompt: Text(configured.defaultInvoiceName))
        }
        RichField("Payment terms", text: draft(\.payment), height: 50)
        if options.invoice && features.advancedBilling {
            DisclosureGroup("Adjust invoice amount") {
                TextField("Net amount (EUR)", value: $adjustment, format: .number.locale(locale))
                TextField("Adjustment reason", text: $adjustmentReason)
            }
        } else {
            Toggle("Include role and item names", isOn: $options.showItems)
                .help("List the named roles and items under each phase. Internal cost amounts stay private.")
        }
        LabeledContent("Filename", value: naming(for: configured).filename).textSelection(.enabled)
        Button("Business & template settings…") { dismiss(); openWindow(id: BusinessSettingsWindow.id) }
    }

    private var actions: some View {
        HStack {
            Button("Close") { dismiss() }
            Spacer()
            Button("Preview…", action: showPreview).disabled(pdfTemplateHint != nil)
            if options.invoice {
                Menu {
                    Button("Export draft as PDF…") { pdf = true; export() }.disabled(pdfTemplateHint != nil)
                    Button("Export draft as Word…") { pdf = false; export() }
                } label: { Label("Export draft", systemImage: "square.and.arrow.up") }
                .disabled(!validVAT)
                Button("Issue invoice…") { showIssueConfirmation = true }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!invoiceChecks.isEmpty || pdf && pdfTemplateHint != nil)
            } else {
                Menu {
                    Button("Export PDF…") { pdf = true; export() }.disabled(pdfTemplateHint != nil)
                    Button("Export Word…") { pdf = false; export() }
                } label: { Label("Export proposal", systemImage: "square.and.arrow.up") }
                .disabled(!validVAT)
            }
        }
    }

    private var netAmount: Decimal { fees.reduce(0) { $0 + $1.amount } }
    private var validVAT: Bool { (0...100).contains(options.vat) }

    private var pdfTemplateHint: LocalizedStringKey? {
        if WordTemplate(document: options).installed,
           !["com.apple.Pages", "com.apple.iWork.Pages"].contains(where: {
               NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
           }) {
            return "PDF export with the imported template requires Pages. Choose Word to export without Pages."
        }
        return nil
    }

    private var identityChecks: [LocalizedStringKey] {
        let profile = BusinessProfile.load()
        var missing: [LocalizedStringKey] = []
        if blank(profile.name) { missing.append("Add a business name in Settings → Business.") }
        if blank(plain(profile.contact)) { missing.append("Add your business address in Settings → Business.") }
        if let recipient {
            if blank(recipient.address) { missing.append("Add the recipient’s billing address in the client directory.") }
        } else {
            missing.append("Assign a client or invoice recipient on the project overview.")
        }
        if !validVAT { missing.append("Enter a VAT rate between 0% and 100%.") }
        return missing
    }

    private var proposalChecks: [LocalizedStringKey] {
        var missing = identityChecks
        if !estimate.hasProjectTitle {
            missing.append("Name the project in the project header.")
        }
        if blank(reference.wrappedValue) {
            missing.append("Add a proposal number to replace the number placeholder.")
        }
        if netAmount == 0 {
            missing.append("The proposal fee is €0. Check the project calculation before sending.")
        }
        let document = configured
        if blank(plain(document.servicePeriod)) {
            missing.append("Enter the service period.")
        }
        if blank(plain(document.paymentText(recipient))) {
            missing.append("Add payment terms in Export and billing options.")
        }
        if !WordTemplate(document: document).installed {
            let scope = fees.filter {
                blank(plain($0.scopes?[language] ?? "")) && (!options.showItems || $0.items.isEmpty)
            }.map(\.name)
            if !scope.isEmpty {
                let names = scope.joined(separator: ", ")
                missing.append(estimate.calculationLocked
                    ? "Included services are missing from the approved phases \(names)."
                    : "Add included services in Document text for \(names).")
            }
            if options.detailed {
                let deliverables = fees.filter { blank(plain($0.deliverables?[language] ?? "")) }.map(\.name)
                if !deliverables.isEmpty {
                    let names = deliverables.joined(separator: ", ")
                    missing.append(estimate.calculationLocked
                        ? "Deliverables are missing from the approved phases \(names)."
                        : "Add deliverables in Document text for \(names).")
                }
            }
        }
        return missing
    }

    private var invoiceChecks: [LocalizedStringKey] {
        let document = configured
        let net = netAmount
        let service = serviceFees.reduce(Decimal.zero) { $0 + $1.amount }
        var missing = identityChecks
        if blank(plain(document.servicePeriod)) { missing.append("Enter the service period.") }
        if net <= 0 || net != cents(net) || service < 0 {
            missing.append("Choose an amount still due, or enter a positive net amount in euros and cents.")
        }
        if document.vat == 0 && blank(document.exemptionReason) {
            missing.append("Add a VAT exemption reason.")
        }
        if let plan = billingPlan, !plan.valid(net: billingNet) {
            missing.append("Correct the project’s instalments in Payment terms so they match the agreed fee.")
        }
        if blank(adjustmentReason) {
            if adjustment != nil || (service > estimate.currentBillableNet - estimate.effectiveInvoicedTotal(for: nil) && service > 0) {
                missing.append("Enter an adjustment reason in Export and billing options.")
            } else if let stage, let stageNet = billingPlan?.amounts(net: billingNet)[stage.id],
                      service > stageNet - estimate.effectiveInvoicedTotal(for: stage.id) && service > 0 {
                missing.append("Choose a milestone with enough remaining balance, or enter an adjustment reason.")
            }
        }
        return missing
    }

    private var invoiceExportNotes: [LocalizedStringKey] {
        let document = configured
        var notes: [LocalizedStringKey] = []
        if blank(document.taxNumber) && blank(document.vatID) {
            notes.append("No tax number or VAT ID is set. Check Settings → Business.")
        }
        if blank(plain(document.bankDetails)) {
            notes.append("Add bank details in Settings → Business if payment is by bank transfer.")
        }
        if blank(plain(document.paymentText(recipient))) {
            notes.append("Add payment terms in Export and billing options.")
        }
        return notes
    }

    private func plain(_ value: String) -> String { InlineText.runs(value).map(\.text).joined() }

    private func blank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func showPreview() {
        do {
            let data = try output(configured, pdf: true)
            guard let pdf = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            preview = pdf
            previewOpen = true
            error = ""
        } catch { self.error = error.localizedDescription }
    }

    private var accepted: ExportedDocument? {
        estimate.documents?.first { $0.id == estimate.acceptedProposalID }
    }
    private var recipientCompany: Client? {
        let id = options.invoice ? estimate.invoiceClientID ?? estimate.clientID : estimate.clientID
        return clients.first { $0.id == id }
    }
    private var contactSelection: Binding<UUID?> {
        let invoice = options.invoice
        return Binding(get: {
            let selected = invoice ? estimate.invoiceContactID : estimate.proposalContactID
            return recipientCompany?.activeContacts.first { $0.id == selected }?.id
        }, set: { id in
            if invoice { estimate.invoiceContactID = id }
            else { estimate.proposalContactID = id }
        })
    }
    private var recipient: Client? {
        recipientCompany?.recipient(attentionTo: contactSelection.wrappedValue)
    }
    private func destination(_ filename: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        if let type = UTType(filenameExtension: (filename as NSString).pathExtension) { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private var language: String { options.german ? "de" : "en" }
    private var draftKey: String { (options.invoice ? "invoice-" : "proposal-") + language }
    private func draft(_ field: WritableKeyPath<DocumentDraft, String>) -> Binding<String> {
        Binding(get: { estimate.documentDrafts?[draftKey]?[keyPath: field] ?? "" }, set: { value in
            var drafts = estimate.documentDrafts ?? [:]
            drafts[draftKey, default: DocumentDraft()][keyPath: field] = value
            estimate.documentDrafts = drafts
        })
    }
    private func localized(_ data: Binding<[String: String]?>) -> Binding<String> {
        Binding(get: { data.wrappedValue?[language] ?? "" }, set: { value in
            var texts = data.wrappedValue ?? [:]; texts[language] = value; data.wrappedValue = texts
        })
    }
    private var billingPlan: BillingSchedule? {
        if options.invoice { return estimate.issuedInstalment?.billingSchedule ?? estimate.firstInstalment?.billingPlan ?? accepted?.billingPlan ?? estimate.billing }
        return estimate.billing
    }
    private var stage: BillingMilestone? {
        guard options.invoice, !remainingBalance, let stages = billingPlan?.stages else { return nil }
        let amounts = billingPlan?.amounts(net: billingNet) ?? [:]
        return stages.first { $0.id == selectedStage } ?? stages.first { item in
            (amounts[item.id] ?? 0) > estimate.effectiveInvoicedTotal(for: item.id)
        }
    }
    private var billingNet: Decimal {
        estimate.issuedInstalment?.billingBasis ?? estimate.firstInstalment?.billingNet ?? estimate.approvedBaseNet ?? estimate.calculate().totals.sales
    }
    private var invoiceName: Binding<String> {
        let key = stage?.id.uuidString ?? "full"
        return Binding(get: { estimate.documentDrafts?[draftKey]?.invoiceNames?[key] ?? "" }, set: { name in
            var drafts = estimate.documentDrafts ?? [:]
            var record = drafts[draftKey] ?? DocumentDraft()
            var names = record.invoiceNames ?? [:]
            names[key] = name
            record.invoiceNames = names
            drafts[draftKey] = record
            estimate.documentDrafts = drafts
        })
    }
    private var reference: Binding<String> {
        let key = options.invoice ? stage?.id.uuidString ?? "invoice" : "proposal"
        return Binding(get: { estimate.documentNumbers?[key] ?? "" }, set: { value in
            var references = estimate.documentNumbers ?? [:]
            references[key] = value
            estimate.documentNumbers = references
        })
    }
    private func naming(for document: ClientDocument) -> ExportNaming {
        ExportNaming(date: document.date, invoice: document.invoice, reference: reference.wrappedValue,
                     project: estimate.title, invoiceName: document.invoiceName, milestone: stage,
                     schedule: billingPlan, history: estimate.documents ?? [], pdf: pdf,
                     previousVersion: estimate.discardedExportVersions?[estimate.seriesKey(invoice: document.invoice, milestoneID: stage?.id)] ?? 0)
    }
    private var configured: ClientDocument {
        var document = options
        document.purchaseOrder = estimate.purchaseOrder
        document.reimbursedCosts = selectedCosts
        document.reference = reference.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        document.date = overrideDate ?? .now
        let draft = estimate.documentDrafts?[draftKey] ?? DocumentDraft()
        document.scope = draft.letter
        document.servicePeriod = draft.period
        document.billingPlan = billingPlan
        document.milestone = stage
        document.invoiceName = invoiceName.wrappedValue
        document.payment = draft.payment.isEmpty ? billingPlan?.deadline(german: options.german) ?? "" : draft.payment
        document.termsText = draft.terms
        if !options.invoice { document.includedRebate = estimate.calculate().rebate }
        let withOptions = estimate.calculate(includingPendingOptions: true)
        document.optionalFees = estimate.pendingOptionPhases.map {
            PhaseFee(name: $0.name, amount: withOptions.phases[$0.id] ?? 0, items: [], scopes: $0.scopes)
        }
        BusinessProfile.load().apply(to: &document)
        document.rateTerms = options.invoice && estimate.acceptedProposalID != nil ? accepted?.rateTerms : RateTerms(estimate)
        if document.reference.isEmpty { document.reference = document.label("[Nummer]", "[Number]") }
        return document
    }
    private var selectedCosts: [InvoiceCostItem] {
        options.invoice ? estimate.openReimbursements.filter { !excludedCosts.contains($0.id) } : []
    }

    private var fees: [PhaseFee] {
        serviceFees + selectedCosts.map { PhaseFee(name: $0.title, amount: $0.amount, items: []) }
    }

    private var serviceFees: [PhaseFee] {
        if !options.invoice { return ClientDocument.fees(for: estimate) }
        let changeFees = estimate.approvedChanges.map { PhaseFee(name: $0.title, amount: $0.net, items: []) }
        let label: String
        let original: Decimal
        if let stage, let amount = billingPlan?.amounts(net: billingNet)[stage.id] {
            label = stage.title(german: options.german) + " (" + stage.shareLabel(locale: configured.locale) + ")"
            original = amount - estimate.effectiveInvoicedTotal(for: stage.id)
        } else {
            label = estimate.title
            original = max(0, estimate.currentBillableNet - estimate.effectiveInvoicedTotal(for: nil))
            if estimate.issuedInvoices?.isEmpty != false && adjustment == nil && !remainingBalance && estimate.acceptedImportedProposal == nil {
                return (accepted?.phaseFees ?? ClientDocument.fees(for: estimate)) + changeFees
            }
        }
        return [PhaseFee(name: label, amount: adjustment ?? original, items: [])]
    }

    private func issue() {
        do {
            guard invoiceChecks.isEmpty, let recipient else { return }
            let net = netAmount
            let requestedNumber = reference.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            var document = configured
            let projectName = estimate.title
            let profile = BusinessProfile.load()
            let reason = adjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines)
            try recordInvoice(requestedNumber.isEmpty ? nil : requestedNumber) { number, latest in
                let service = net - selectedCosts.reduce(0) { $0 + $1.amount }
                let before = latest.effectiveInvoicedTotal(for: nil)
                if service > 0 && service > latest.currentBillableNet - before && reason.isEmpty {
                    throw LibraryError(description: "This invoice exceeds the remaining net amount. Enter an adjustment reason to proceed.")
                }
                if let stage, let stageNet = billingPlan?.amounts(net: billingNet)[stage.id],
                   service > 0 && service > stageNet - latest.effectiveInvoicedTotal(for: stage.id) && reason.isEmpty {
                    throw LibraryError(description: "This milestone has already been billed or the invoice exceeds its remaining amount.")
                }
                document.reference = number
                let original = outputLocaleFilename(number, date: document.date, pdf: pdf)
                let rendered = try output(document, pdf: pdf)
                let banking = plain(profile.bank).components(separatedBy: .newlines)
                let bankLine = banking.first { $0.uppercased().hasPrefix("IBAN:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
                let structuredIBAN = profile.electronicInvoice?.iban.trimmingCharacters(in: .whitespacesAndNewlines)
                let iban = structuredIBAN.flatMap { $0.isEmpty ? nil : $0 } ?? bankLine
                let bic = banking.first { $0.uppercased().hasPrefix("BIC:") }.map { String($0.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
                let email = plain(profile.contact).components(separatedBy: .newlines).first(where: { $0.contains("@") }).map { $0.components(separatedBy: " ").last ?? $0 }
                let sender = InvoiceParty(name: profile.name, address: plain(profile.contact), taxNumber: profile.taxNumber, vatID: profile.vatID, email: email, iban: iban, bic: bic,
                                          electronicDefaults: profile.electronicInvoice?.seller)
                let buyer = InvoiceParty(name: recipient.name, address: recipient.address, contact: recipient.contact, email: recipient.email,
                                         electronicDefaults: recipient.electronicInvoice?.buyer)
                let due = document.paymentDays(client: recipient).flatMap { Calendar.current.date(byAdding: .day, value: $0, to: document.date) }
                return IssuedInvoice(number: number, issueDate: document.date, dueDate: due, title: document.title,
                    projectName: projectName, sender: sender, recipient: buyer, servicePeriod: document.servicePeriod,
                    paymentTerms: document.paymentText(recipient), net: net, vatRate: document.vat,
                    vat: cents(net * document.vat / 100), milestoneID: stage?.id,
                    billingSchedule: stage == nil ? nil : billingPlan, billingBasis: stage == nil ? nil : billingNet, vatExemptionReason: document.exemptionReason.isEmpty ? nil : document.exemptionReason,
                    adjustmentReason: reason.isEmpty ? nil : reason, files: [InvoiceArtifact(filename: original, data: rendered)],
                    buyerReference: recipient.electronicInvoice?.buyerReference, purchaseOrder: document.purchaseOrder, reimbursedCosts: selectedCosts)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func outputLocaleFilename(_ number: String, date: Date, pdf: Bool) -> String {
        ExportNaming(date: date, invoice: true, reference: number, project: estimate.title, invoiceName: "",
                     milestone: stage, schedule: billingPlan, history: [], pdf: pdf).filename
    }
    private func output(_ document: ClientDocument, pdf: Bool) throws -> Data {
        let template = WordTemplate(document: document)
        if template.installed {
            let filled = try template.render(source: template.url, project: estimate.title, client: recipient, fees: fees)
            return try pdf ? template.pdf(from: filled) : filled
        }
        return try document.encode(document.contents(project: estimate.title, recipient: recipient, fees: fees), pdf: pdf)
    }
    private func export() {
        let document = configured
        let exportName = naming(for: document)
        guard let url = destination(exportName.filename) else { return }
        do {
            let data = try output(document, pdf: pdf)
            try data.write(to: url, options: .atomic)
            let record = ExportedDocument(filename: url.lastPathComponent, data: data, date: document.date, proposal: !options.invoice,
                                          net: netAmount, phaseFees: fees, rateTerms: document.rateTerms, billingPlan: billingPlan,
                                          billingNet: stage == nil ? nil : billingNet, milestoneID: stage?.id,
                                          exportVersion: exportName.version, costBudget: options.invoice ? nil : CostBudget(estimate),
                                          calculationInputs: options.invoice ? nil : estimate.calculationBasis,
                                          reimbursedCosts: selectedCosts, purchaseOrder: document.purchaseOrder)
            var updated = estimate
            if stage != nil, updated.firstInstalment == nil { updated.billing = billingPlan }
            updated.documents = (updated.documents ?? []) + [record]
            try saveDocuments(updated)
            error = ""
        } catch { self.error = error.localizedDescription }
    }
}
