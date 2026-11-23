import Foundation

struct InvoiceParty: Codable, Equatable {
    var name: String
    var address: String
    var contact: String = ""
    var taxNumber: String?
    var vatID: String?
    var email: String?
    var iban: String?
    var bic: String?
    var electronicDefaults: ElectronicParty?
}

struct InvoiceArtifact: Identifiable, Codable, Equatable {
    let filename: String
    let data: Data
    var id: String { filename }
}

struct InvoicePayment: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var amount: Decimal = 0
    var note = ""
    var quickSettlement: Bool?
}

struct VoidedInvoice: Identifiable, Codable {
    let invoice: IssuedInvoice
    let date: Date
    var id: UUID { invoice.id }
}

struct InvoiceCostItem: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let amount: Decimal

    var reversed: Self { Self(id: id, title: title, amount: -amount) }
}

struct IssuedInvoice: Identifiable, Codable {
    var id = UUID()
    let number: String
    let issueDate: Date
    let dueDate: Date?
    let title: String
    let projectName: String
    let sender: InvoiceParty?
    let recipient: InvoiceParty?
    let servicePeriod: String
    let paymentTerms: String
    let net: Decimal
    let vatRate: Decimal
    let vat: Decimal
    var milestoneID: UUID?
    var billingSchedule: BillingSchedule?
    var billingBasis: Decimal?
    var vatExemptionReason: String?
    var correctionOf: UUID?
    var correctionReason: String?
    var adjustmentReason: String?
    var sourceFileID: UUID?
    var files: [InvoiceArtifact] = []
    var sentOn: Date?
    var acceptedOn: Date?
    var payments: [InvoicePayment] = []
    var buyerReference: String?
    var purchaseOrder: String?
    var reimbursedCosts: [InvoiceCostItem]?

    var serviceNet: Decimal { net - (reimbursedCosts ?? []).reduce(0) { $0 + $1.amount } }

    var positions: [(name: String, amount: Decimal)] {
        var lines: [(String, Decimal)] = []
        if serviceNet != 0 { lines.append((projectName + " · " + title, serviceNet)) }
        lines += (reimbursedCosts ?? []).map { ($0.title, $0.amount) }
        return lines
    }

    var hasFullParties: Bool {
        [sender, recipient].allSatisfy { party in
            guard let party else { return false }
            return !party.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !party.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var gross: Decimal { net + vat }
    var paid: Decimal { payments.reduce(0) { $0 + $1.amount } }
    var outstanding: Decimal { gross - paid }
}

extension Estimate {
    var invoiceReconciliationNet: Decimal {
        currentBillableNet + reimbursablePositions.reduce(0) { $0 + $1.amount }
    }

    var invoiceNetTotal: Decimal {
        (issuedInvoices ?? []).reduce(0) { $0 + $1.net }
    }

    var invoiceOutstandingGross: Decimal {
        (issuedInvoices ?? []).reduce(0) { $0 + $1.outstanding }
    }

    var invoicePaymentsTotal: Decimal {
        (issuedInvoices ?? []).reduce(0) { $0 + $1.paid }
    }

    func effectiveInvoicedTotal(for milestoneID: UUID?) -> Decimal {
        (issuedInvoices ?? []).filter { invoice in
            milestoneID == nil || invoice.milestoneID == milestoneID
        }.reduce(0) { $0 + $1.serviceNet }
    }

    var invoicedCostIDs: Set<UUID> {
        let reversed = Set((issuedInvoices ?? []).compactMap(\.correctionOf))
        return Set((issuedInvoices ?? []).filter { $0.correctionOf == nil && !reversed.contains($0.id) }
            .flatMap { $0.reimbursedCosts ?? [] }.map(\.id))
    }

    var openReimbursements: [InvoiceCostItem] {
        let used = invoicedCostIDs
        return reimbursablePositions.filter { !used.contains($0.id) }
    }

    private var reimbursablePositions: [InvoiceCostItem] {
        let costs = effectiveExternalCosts
        let privateIDs = Set(costs.map(\.id))
        let items: [InvoiceCostItem] = costs.compactMap { cost in
            guard cost.reimbursable, let amount = cost.booked, amount > 0 else { return nil }
            return InvoiceCostItem(id: cost.id, title: cost.title, amount: amount)
        }
        return items + (files ?? []).compactMap { file in
            guard let booking = file.booking, booking.billAtCost == true,
                  booking.externalCostID.map(privateIDs.contains) != true else { return nil }
            return InvoiceCostItem(id: file.id, title: [booking.supplier, booking.reference].joined(separator: " · "), amount: booking.amount)
        }
    }

    func canUndoIssue(_ invoice: IssuedInvoice) -> Bool {
        invoice.sentOn == nil && invoice.acceptedOn == nil && invoice.payments.isEmpty &&
        invoice.sourceFileID == nil && invoice.correctionOf == nil &&
        !(issuedInvoices ?? []).contains { $0.correctionOf == invoice.id }
    }

    mutating func undoIssue(_ id: UUID) throws {
        guard let invoice = issuedInvoices?.first(where: { $0.id == id }), canUndoIssue(invoice) else {
            throw LibraryError(description: "This invoice has subsequent activity. Use an invoice correction.")
        }
        voidedInvoices = (voidedInvoices ?? []) + [VoidedInvoice(invoice: invoice, date: .now)]
        issuedInvoices?.removeAll { $0.id == id }
    }

    func invoiceBalance(for id: UUID) -> Decimal {
        (issuedInvoices ?? []).filter { $0.id == id || $0.correctionOf == id }
            .reduce(0) { $0 + $1.outstanding }
    }

    func canMarkInvoicePaid(_ id: UUID, on date: Date = .now) -> Bool {
        guard let invoice = issuedInvoices?.first(where: { $0.id == id }) else { return false }
        return invoice.correctionOf == nil && invoice.outstanding > 0 &&
            !(issuedInvoices ?? []).contains { $0.correctionOf == id } &&
            date >= Calendar.current.startOfDay(for: invoice.issueDate)
    }

    mutating func markInvoicePaid(_ id: UUID, on date: Date = .now) throws {
        guard canMarkInvoicePaid(id, on: date), let invoice = issuedInvoices?.first(where: { $0.id == id }) else {
            throw LibraryError(description: "This invoice has no outstanding payment to record.")
        }
        try recordPayment(InvoicePayment(date: date, amount: invoice.outstanding, quickSettlement: true), for: id)
    }

    mutating func undoMarkInvoicePaid(_ id: UUID) {
        guard let index = issuedInvoices?.firstIndex(where: { $0.id == id }),
              issuedInvoices?[index].payments.last?.quickSettlement == true else { return }
        issuedInvoices?[index].payments.removeLast()
    }

    var invoiceIntake: [ProjectFile] {
        let recorded = Set((issuedInvoices ?? []).compactMap(\.sourceFileID))
        let files = (files ?? []).filter { $0.kind == .sent }
        let exports = (documents ?? []).filter { !$0.proposal && $0.sentOn != nil }.map {
            ProjectFile(id: $0.id, kind: .sent, name: $0.filename, data: $0.data, accepted: $0.acceptedOn)
        }
        return (files + exports).filter { !recorded.contains($0.id) }
    }

    func validateInvoice(_ invoice: IssuedInvoice) throws {
        let records = issuedInvoices ?? []
        let name = invoice.number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, invoice.number == name, !records.contains(where: {
            $0.id == invoice.id || $0.number.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw LibraryError(description: "An invoice number must be present and unique.")
        }
        guard invoice.vatRate >= 0, invoice.vatRate <= 100, invoice.net != 0,
              cents(invoice.net) == invoice.net, cents(invoice.vat) == invoice.vat,
              invoice.vat == 0 || (invoice.net > 0 ? invoice.vat > 0 : invoice.vat < 0) else {
            throw LibraryError(description: "Check the net amount, VAT amount, and VAT rate.")
        }
        if let source = invoice.sourceFileID,
           records.contains(where: { $0.sourceFileID == source }) {
            throw LibraryError(description: "This invoice file already has a ledger entry.")
        }
        if let originalID = invoice.correctionOf {
            guard let original = records.first(where: { $0.id == originalID }),
                  original.correctionOf == nil,
                  invoice.net == -original.net,
                  (invoice.reimbursedCosts ?? []) == (original.reimbursedCosts ?? []).map(\.reversed),
                  invoice.vat == -original.vat,
                  invoice.vatRate == original.vatRate,
                  invoice.milestoneID == original.milestoneID,
                  Calendar.current.startOfDay(for: invoice.issueDate) >= Calendar.current.startOfDay(for: original.issueDate),
                  let reason = invoice.correctionReason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !records.contains(where: { $0.correctionOf == originalID }) else {
                throw LibraryError(description: "A correction must reverse a single issued invoice and include a reason.")
            }
        } else if let items = invoice.reimbursedCosts, !items.isEmpty {
            guard items.allSatisfy(openReimbursements.contains), Set(items.map(\.id)).count == items.count,
                  invoice.serviceNet >= 0 else {
                throw LibraryError(description: "The reimbursable costs changed. Review the invoice positions.")
            }
        } else if invoice.gross <= 0 {
            throw LibraryError(description: "Enter a positive amount for the invoice.")
        }
    }

    func validatePayment(_ payment: InvoicePayment, for id: UUID) throws {
        let records = issuedInvoices ?? []
        guard let invoice = records.first(where: { $0.id == id }), invoice.correctionOf == nil,
              payment.amount != 0, payment.amount == cents(payment.amount),
              !invoice.payments.contains(where: { $0.id == payment.id }),
              payment.date >= Calendar.current.startOfDay(for: invoice.issueDate) else {
            throw LibraryError(description: "Enter a nonzero payment to the cent and a date on or after issue.")
        }
        if payment.amount < 0, -payment.amount > invoice.paid {
            throw LibraryError(description: "The refund exceeds the amount received.")
        }
    }

    mutating func recordPayment(_ payment: InvoicePayment, for id: UUID) throws {
        try validatePayment(payment, for: id)
        guard let index = issuedInvoices?.firstIndex(where: { $0.id == id }) else { return }
        issuedInvoices?[index].payments.append(payment)
    }
}
