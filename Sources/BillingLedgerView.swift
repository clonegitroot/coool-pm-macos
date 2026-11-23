import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook

struct InvoiceLedgerView: View {
    @Environment(\.usageFeatures) private var features
    @Binding var estimate: Estimate
    let createInvoice: () -> Void
    let recordInvoice: (IssuedInvoice) throws -> Void
    let issueCorrection: (IssuedInvoice, String, Date) throws -> Void
    let exportStructured: (IssuedInvoice) -> Void
    var invoiceRecipient: Client?

    @Environment(\.locale) private var locale
    @State private var editor: Editor?
    @State private var undoCandidate: IssuedInvoice?
    @State private var error: String?
    @State private var previewURL: URL?

    private enum Editor: Identifiable {
        case external
        case payment(IssuedInvoice)
        case correction(IssuedInvoice)

        var id: String {
            switch self {
            case .external: return "external"
            case .payment(let invoice): return "payment-" + invoice.id.uuidString
            case .correction(let invoice): return "correction-" + invoice.id.uuidString
            }
        }
    }

    private var invoices: [IssuedInvoice] { estimate.issuedInvoices ?? [] }
    private var sourceFiles: [ProjectFile] { estimate.invoiceIntake }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Create invoice…", systemImage: "square.and.pencil", action: createInvoice)
                Button("Record sent invoice…", systemImage: "tray.and.arrow.down") { editor = .external }
                    .disabled(sourceFiles.isEmpty)
                    .help(Text(sourceFiles.isEmpty ? "Import a sent invoice below." : "Add a sent invoice to the ledger."))
            }
            GroupBox("Billing reconciliation") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                    totalRow(estimate.approvedNet == nil ? "Estimate (net)" : "Approved (net)", estimate.invoiceReconciliationNet)
                    totalRow("Issued (net)", estimate.invoiceNetTotal)
                    let remaining = estimate.invoiceReconciliationNet - estimate.invoiceNetTotal
                    totalRow(remaining < 0 ? "Overbilled (net)" : "Remaining to invoice (net)", abs(remaining))
                    totalRow("Payments received (gross)", estimate.invoicePaymentsTotal)
                    let balance = estimate.invoiceOutstandingGross
                    totalRow(balance < 0 ? "Net credit balance (gross)" : "Net outstanding balance (gross)", abs(balance))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Issued invoices") {
                VStack(alignment: .leading, spacing: 12) {
                    if invoices.isEmpty {
                        Text("Issue an invoice or record one you’ve already sent.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(invoices.reversed()) { invoice in
                        invoiceRow(invoice)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            if let voided = estimate.voidedInvoices, !voided.isEmpty {
                DisclosureGroup("Voided before sending") {
                    ForEach(voided.reversed()) { item in
                        LabeledContent(item.invoice.number, value: shortDate(item.date) + " · " + money(item.invoice.gross))
                    }
                }
            }
            ProjectFilesView(estimate: $estimate, area: .billing, createDocument: createInvoice)
        }
        .sheet(item: $editor) { next in
            Group {
                switch next {
                case .external:
                    SentInvoiceEditor(project: estimate.title, recipientName: invoiceRecipient?.name ?? estimate.client,
                                      billingClient: invoiceRecipient, projectOrder: estimate.purchaseOrder ?? "",
                                      openCosts: estimate.openReimbursements, exportedIDs: Set((estimate.documents ?? []).map(\.id)),
                                      files: sourceFiles, milestones: estimate.billing?.stages ?? []) { invoice in
                        var record = invoice
                        if let draft = estimate.documents?.first(where: { $0.id == record.sourceFileID }) {
                            record.reimbursedCosts = draft.reimbursedCosts
                            record.purchaseOrder = draft.purchaseOrder
                        }
                        try estimate.validateInvoice(record)
                        try recordInvoice(record)
                    }
                case .payment(let invoice):
                    InvoicePaymentEditor(invoice: invoice) { payment in
                        try estimate.recordPayment(payment, for: invoice.id)
                    }
                case .correction(let invoice):
                    InvoiceCorrectionEditor(invoice: invoice) { reason, date in
                        try issueCorrection(invoice, reason, date)
                    }
                }
            }.environment(\.locale, locale)
        }
        .confirmationDialog("Undo invoice creation?", isPresented: Binding(get: { undoCandidate != nil }, set: { if !$0 { undoCandidate = nil } }), presenting: undoCandidate) { invoice in
            Button("Undo creation", role: .destructive) { perform { try estimate.undoIssue(invoice.id) } }
        } message: { invoice in
            Text("The unsent invoice is removed from billing. Its number stays reserved.")
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { previous, current in
            if let previous, previous != current { try? FileManager.default.removeItem(at: previous.deletingLastPathComponent()) }
        }
        .alert("Invoice action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func totalRow(_ title: LocalizedStringKey, _ amount: Decimal) -> some View {
        GridRow {
            Text(title)
            Text(money(amount)).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }

    private func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "EUR").locale(locale))
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
    }

    private func invoiceRow(_ invoice: IssuedInvoice) -> some View {
        let reverse = invoices.first { $0.correctionOf == invoice.id }
        let balance = estimate.invoiceBalance(for: invoice.id)
        let cancelled = reverse != nil
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let original = invoices.first(where: { $0.id == invoice.correctionOf }) {
                    Text("Reverses invoice \(original.number)")
                }
                if let reverse { Text("Reversed by \(reverse.number)") }
                if let reason = invoice.correctionReason { Text(reason).foregroundStyle(.secondary) }
                if let reason = invoice.adjustmentReason { Text(reason).foregroundStyle(.secondary) }
                if let due = invoice.dueDate { Text("Due \(shortDate(due))") }
                if let sent = invoice.sentOn { Text("Sent \(shortDate(sent))") }
                if let accepted = invoice.acceptedOn { Text("Accepted \(shortDate(accepted))") }
                if invoice.correctionOf == nil {
                    Text(balance < 0 ? "Credit balance \(money(-balance))" : "Outstanding \(money(balance))").bold()
                }
                ForEach(invoice.payments) { payment in
                    HStack {
                        Text(payment.date, style: .date)
                        Text(payment.amount < 0 ? "Refund" : "Payment")
                        if !payment.note.isEmpty { Text(payment.note).foregroundStyle(.secondary) }
                        Spacer()
                        Text(money(payment.amount)).monospacedDigit()
                    }.font(.callout)
                }
                HStack {
                    if invoice.correctionOf == nil {
                        Button("Record payment…") { editor = .payment(invoice) }
                        if !cancelled {
                            Button("Correct invoice…") { editor = .correction(invoice) }
                                .disabled(!invoice.hasFullParties)
                                .help(Text(invoice.hasFullParties ? "Record a full reversal." : "The recipient and issuer details are required."))
                        }
                    }
                    Menu("Actions") {
                        if estimate.canUndoIssue(invoice) {
                            Button("Undo invoice creation…", role: .destructive) { undoCandidate = invoice }
                        }
                        if invoice.payments.last?.quickSettlement == true {
                            Button("Undo mark paid") { estimate.undoMarkInvoicePaid(invoice.id) }
                        }

                        if invoice.sentOn == nil {
                            Button("Mark sent") { update(invoice.id) { $0.sentOn = .now } }
                        }
                        if invoice.acceptedOn == nil {
                            Button("Mark accepted") {
                                update(invoice.id) {
                                    $0.acceptedOn = .now
                                    if $0.sentOn == nil { $0.sentOn = .now }
                                }
                            }
                        } else {
                            Button("Undo acceptance") { update(invoice.id) { $0.acceptedOn = nil } }
                        }
                        if features.advancedBilling && invoice.hasFullParties {
                            Button("XRechnung…") { exportStructured(invoice) }
                        }
                    }.fixedSize()
                }
            }.padding(.vertical, 6)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(invoice.number + " · " + invoiceTitle(invoice)).font(.headline)
                    Text(invoice.issueDate, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(state(for: invoice, balance: balance, reversed: reverse != nil)).font(.caption.weight(.medium))
                    .foregroundStyle(balance == 0 && !cancelled && invoice.correctionOf == nil ? Color.accentColor : Color.secondary)
                if estimate.canMarkInvoicePaid(invoice.id) {
                    Button("Mark paid", systemImage: "checkmark.circle") {
                        perform { try estimate.markInvoicePaid(invoice.id) }
                    }.buttonStyle(.bordered)
                        .help(Text("Record the outstanding balance as received today."))
                }
                if !invoice.files.isEmpty {
                    Menu {
                        ForEach(invoice.files) { artifact in
                            Menu(artifact.filename) {
                                Button("Quick Look") { perform { try preview(artifact) } }
                                Button("Save copy…") { perform { try saveCopy(artifact) } }
                            }
                        }
                    } label: {
                        Label("Invoice files", systemImage: "paperclip")
                    }.labelStyle(.iconOnly).menuIndicator(.hidden).fixedSize()
                }
                Text(money(invoice.gross)).monospacedDigit().frame(minWidth: 95, alignment: .trailing)
            }
        }
    }

    private func state(for invoice: IssuedInvoice, balance: Decimal, reversed: Bool) -> LocalizedStringKey {
        if invoice.correctionOf != nil { return "Correction" }
        if balance < 0 { return "Credit balance" }
        if reversed { return "Reversed" }
        if balance == 0 { return "Paid" }
        if let due = invoice.dueDate, due < Calendar.current.startOfDay(for: .now) { return "Overdue" }
        if invoice.paid > 0 { return "Part paid" }
        if invoice.acceptedOn != nil { return "Accepted" }
        if invoice.sentOn != nil { return "Sent" }
        return "Issued"
    }

    private func invoiceTitle(_ invoice: IssuedInvoice) -> String {
        guard invoice.sourceFileID != nil, invoice.title == "Invoice" else { return invoice.title }
        return AppLanguage.text("Invoice", fallback: "Invoice", locale: locale)
    }

    private func update(_ id: UUID, apply: (inout IssuedInvoice) -> Void) {
        guard let index = estimate.issuedInvoices?.firstIndex(where: { $0.id == id }) else { return }
        if var documents = estimate.issuedInvoices {
            apply(&documents[index])
            estimate.issuedInvoices = documents
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }

    private func safeFilename(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return [".", "..", "/", ""].contains(last) ? "Invoice" : last
    }

    private func preview(_ artifact: InvoiceArtifact) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(safeFilename(artifact.filename))
        do {
            try artifact.data.write(to: url, options: .atomic)
            previewURL = url
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func saveCopy(_ artifact: InvoiceArtifact) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(artifact.filename)
        if let type = UTType(filenameExtension: (artifact.filename as NSString).pathExtension) { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let url = panel.url { try artifact.data.write(to: url, options: .atomic) }
    }
}

private struct SentInvoiceEditor: View {
    let project: String
    let recipientName: String
    let billingClient: Client?
    let projectOrder: String
    let openCosts: [InvoiceCostItem]
    let exportedIDs: Set<UUID>
    let files: [ProjectFile]
    let milestones: [BillingMilestone]
    let save: (IssuedInvoice) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var fileID: UUID?
    @State private var milestoneID: UUID?
    @State private var reference = ""
    @State private var purchaseOrder = ""
    @State private var includedCosts = Set<UUID>()
    @State private var issueDate = Date()
    @State private var dueDate = Date()
    @State private var sentDate = Date()
    @State private var seller = InvoiceParty(name: "", address: "")
    @State private var buyer = InvoiceParty(name: "", address: "")
    @State private var hasDueDate = false
    @State private var net: Decimal = 0
    @State private var vatRate = Decimal(BusinessProfile.load().vat)
    @State private var actualVAT: Decimal?
    @State private var period = ""
    @State private var explanation = ""
    @State private var error: String?

    private var selectedFile: ProjectFile? {
        files.first { $0.id == fileID }
    }

    private var calculatedVAT: Decimal { cents(net * vatRate / 100) }

    private var check: LocalizedStringKey? {
        if selectedFile == nil { return "Choose the sent invoice file." }
        if reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter the invoice number shown on the file."
        }
        if net <= 0 || net != cents(net) { return "Enter a positive net amount in euros and cents." }
        if !(0...100).contains(vatRate) { return "Enter a VAT rate between 0% and 100%." }
        if let actualVAT, actualVAT < 0 || actualVAT != cents(actualVAT) {
            return "Enter the VAT amount shown on the file in euros and cents."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Record a sent invoice").font(.title2.bold())
                Text("Copy the details from the invoice you already sent.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22).padding(.vertical, 17)
            Divider()
            Form {
                Section("Invoice details") {
                    filePicker
                    TextField("Invoice number", text: $reference)
                    if let fileID, !exportedIDs.contains(fileID) {
                        TextField("Purchase order", text: $purchaseOrder)
                    }
                    DatePicker("Issue date", selection: $issueDate, displayedComponents: .date)
                    DatePicker("Date sent", selection: $sentDate, in: earliestDate..., displayedComponents: .date)
                    TextField("Service period", text: $period)
                }
                Section("Amounts") {
                    TextField("Net amount (EUR)", value: $net, format: .number.locale(locale))
                    TextField("VAT rate (%)", value: $vatRate, format: .number.locale(locale))
                    TextField("VAT amount on invoice (EUR)", value: $actualVAT, format: .number.locale(locale))
                        .help("Leave blank to use the calculated VAT. Enter the amount from the original invoice if it differs.")
                    LabeledContent("Calculated VAT", value: calculatedVAT.formatted(.currency(code: "EUR").locale(locale)))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let fileID, !exportedIDs.contains(fileID), !openCosts.isEmpty {
                    Section("Costs already included in the invoice total") {
                        ForEach(openCosts) { cost in
                            Toggle(isOn: Binding(get: { includedCosts.contains(cost.id) }, set: { selected in
                                if selected { includedCosts.insert(cost.id) }
                                else { includedCosts.remove(cost.id) }
                            })) {
                                LabeledContent(cost.title, value: cost.amount.formatted(.currency(code: "EUR").locale(locale)))
                            }
                        }
                    }
                }
                Section("Payment details") {
                    Toggle("Include due date", isOn: $hasDueDate)
                        .help("Record the due date on the original invoice. Coool PM uses it to flag overdue payments.")
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, in: earliestDate..., displayedComponents: .date)
                    }
                    if !milestones.isEmpty {
                        Picker("Milestone", selection: $milestoneID) {
                            Text("None").tag(UUID?.none)
                            ForEach(milestones) { stage in
                                Text(stage.title(german: locale.language.languageCode?.identifier == "de")).tag(Optional(stage.id))
                            }
                        }.help("Link the invoice to its planned instalment so Billing tracks the remaining amount.")
                    }
                    TextField("Adjustment reason (optional)", text: $explanation)
                        .help("Explain any difference from the planned invoice amount.")
                }
                Section {
                    DisclosureGroup("Party details for corrections and XRechnung") {
                        Text("Use the names and addresses as they appear on the original invoice.")
                            .font(.callout).foregroundStyle(.secondary)
                        TextField("Issuer name", text: $seller.name)
                        TextField("Issuer address", text: $seller.address, axis: .vertical).lineLimit(2...4)
                        TextField("Recipient name", text: $buyer.name)
                        TextField("Recipient address", text: $buyer.address, axis: .vertical).lineLimit(2...4)
                    }
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout) }
                HStack(spacing: 12) {
                    if let check {
                        Text(check).foregroundStyle(.secondary).font(.callout)
                    }
                    Spacer(minLength: 12)
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Record invoice", action: submit)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(check != nil)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 620, height: 620)
        .onAppear {
            purchaseOrder = projectOrder
            fileID = files.first?.id
            let profile = BusinessProfile.load()
            seller.taxNumber = profile.taxNumber
            seller.vatID = profile.vatID
            seller.iban = profile.electronicInvoice?.iban
            seller.electronicDefaults = profile.electronicInvoice?.seller
            buyer = InvoiceParty(name: recipientName, address: billingClient?.address ?? "",
                                 contact: billingClient?.contact ?? "", email: billingClient?.email,
                                 electronicDefaults: billingClient?.electronicInvoice?.buyer)
        }
        .onChange(of: issueDate) { _, _ in
            sentDate = max(sentDate, earliestDate)
            dueDate = max(dueDate, earliestDate)
        }
    }

    private var earliestDate: Date { Calendar.current.startOfDay(for: issueDate) }

    private var filePicker: some View {
        LabeledContent("Invoice file") {
            Menu {
                ForEach(files) { file in
                    Button {
                        fileID = file.id
                    } label: {
                        if file.id == fileID { Label(file.name, systemImage: "checkmark") }
                        else { Text(file.name) }
                    }
                }
            } label: {
                if let file = selectedFile {
                    Text(file.name).lineLimit(2).truncationMode(.middle)
                } else {
                    Text("Choose a file")
                }
            }
            .frame(maxWidth: 345, alignment: .trailing)
            .help(selectedFile?.name ?? "")
            .accessibilityLabel("Invoice file")
        }
    }

    private func submit() {
        guard check == nil, let file = selectedFile else { return }
        let name = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = purchaseOrder.trimmingCharacters(in: .whitespacesAndNewlines)
        let costs = exportedIDs.contains(file.id) ? [] : openCosts.filter { includedCosts.contains($0.id) }
        let receipt = IssuedInvoice(number: name, issueDate: issueDate, dueDate: hasDueDate ? dueDate : nil,
                                    title: "Invoice", projectName: project, sender: seller.name.isEmpty ? nil : seller,
                                    recipient: buyer.name.isEmpty ? nil : buyer, servicePeriod: period,
                                    paymentTerms: "", net: net, vatRate: vatRate, vat: actualVAT ?? calculatedVAT,
                                    milestoneID: milestoneID, adjustmentReason: reason.isEmpty ? nil : reason, sourceFileID: file.id,
                                    files: [InvoiceArtifact(filename: file.name, data: file.data)], sentOn: sentDate, acceptedOn: file.accepted,
                                    buyerReference: billingClient?.electronicInvoice?.buyerReference,
                                    purchaseOrder: order.isEmpty ? nil : order, reimbursedCosts: costs)
        do { try save(receipt); dismiss() } catch { self.error = error.localizedDescription }
    }
}

private struct InvoicePaymentEditor: View {
    let invoice: IssuedInvoice
    let save: (InvoicePayment) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var payment = InvoicePayment()
    @State private var refund = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record payment · \(invoice.number)").font(.title2.bold())
            Form {
                Picker("Transaction", selection: $refund) {
                    Text("Payment received").tag(false)
                    Text("Refund sent").tag(true)
                }
                DatePicker("Date", selection: $payment.date, in: Calendar.current.startOfDay(for: invoice.issueDate)..., displayedComponents: .date)
                TextField("Gross amount (EUR)", value: $payment.amount, format: .number.locale(locale))
                TextField("Note", text: $payment.note)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Record") {
                    var entry = payment
                    if refund { entry.amount = -entry.amount }
                    do { try save(entry); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(payment.amount <= 0)
            }
        }.padding(22).frame(width: 450)
        .onAppear { payment.date = max(.now, invoice.issueDate) }
    }
}

private struct InvoiceCorrectionEditor: View {
    let invoice: IssuedInvoice
    let issue: (String, Date) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var reason = ""
    @State private var date = Date()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Correct invoice \(invoice.number)").font(.title2.bold())
            Text("Issue a linked correction for \((-invoice.gross).formatted(.currency(code: "EUR").locale(locale))).")
            Form {
                DatePicker("Issue date", selection: $date, in: Calendar.current.startOfDay(for: invoice.issueDate)..., displayedComponents: .date)
                TextField("Reason", text: $reason)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Issue correction") {
                    do { try issue(reason.trimmingCharacters(in: .whitespacesAndNewlines), date); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 450)
        .onAppear { date = max(.now, invoice.issueDate) }
    }
}
