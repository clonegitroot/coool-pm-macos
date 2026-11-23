import Foundation
import PDFKit

func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
}

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let key = LibraryKey.generate()
VaultSession.shared.unlock(key)
let db = try ProjectDatabase(url: directory.appendingPathComponent("fixture.sqlite"), vaultKey: key)
let date = Date()
var estimate = Estimate()
estimate.title = "Fictional test production"
estimate.phases = [Phase(name: "Production", entries: [Entry(name: "Service", pricing: .fee, quantity: 1, rate: 500)])]
let phaseID = estimate.phases[0].id
estimate.purchaseOrder = "PO<&-123"
let plan = ProjectExternalCost(title: "Private location allowance", phaseID: phaseID, planned: 80)
estimate.externalCosts = [plan]
estimate.manualBudget = CostBudget(estimate)
let reimbursed = ProjectExternalCost(title: "Archive footage", phaseID: phaseID, booked: 40, date: date, reimbursable: true)
estimate.externalCosts?[0].booked = 95
estimate.externalCosts?.append(reimbursed)
let costs = estimate.costs(for: nil)
check(costs.planned.external == 80 && costs.forecast.external == 135, "Forecast uses the booked value in place of its estimate")
check(costs.actual.external == 135 && costs.forecast.sales == 540 && costs.forecast.db1 == 405, "Reimbursement and absorbed costs")
check(costs.differences.reduce(0) { $0 + $1.db1 } == costs.forecast.db1 - costs.planned.db1, "DB1 drill-down reconciles")
check(costs.differences.reduce(0) { $0 + $1.db2 } == costs.forecast.db2 - costs.planned.db2, "DB2 drill-down reconciles")
check(estimate.costs(for: UUID()).forecast.external == 0, "Phase filter")
// Import a bill for a previously planned and manually booked expense.
var linked = estimate
let source = ProjectFile(kind: .supplier, name: "fictional-receipt.txt", data: Data())
linked.files = [source]
try linked.book(SupplierBooking(supplier: "Studio Supplies", reference: "TEST-3", amount: 105,
                                phaseID: phaseID, invoiceDate: date, externalCostID: plan.id, billAtCost: true), fileID: source.id)
let linkedComparison = linked.costs(for: nil)
check(linkedComparison.actual.external == 145 && linkedComparison.forecast.external == 145 &&
      linkedComparison.planned.external == 80, "Source attachment replaces the manually booked actual and private estimate")
check(linkedComparison.differences.reduce(0) { $0 + $1.db1 } == linkedComparison.forecast.db1 - linkedComparison.planned.db1, "Linked cost variance reconciles")
check(linked.openReimbursements.first(where: { $0.id == plan.id })?.amount == 105, "Linked reimbursement uses supplier bill amount")
let currentYear = Calendar.current.component(.year, from: date)
check(BusinessReport(projects: [Project(id: UUID(), estimate: linked)], year: currentYear).totals.supplierCosts == 145,
      "Business reporting counts each source bill once")
let direct = ProjectFile(kind: .supplier, name: "fictional-direct.txt", data: Data())
linked.files?.append(direct)
try linked.book(SupplierBooking(supplier: "Test Vendor", reference: "TEST-4", amount: 25, invoiceDate: date, billAtCost: true), fileID: direct.id)
check(linked.openReimbursements.contains { $0.id == direct.id && $0.amount == 25 }, "Standalone supplier bill can be passed through")
check(linked.costs(for: nil).actual.external == 170, "Standalone and linked costs coexist")
check(linked.invoiceReconciliationNet == 670, "Reconciliation includes independent and supplier-linked reimbursements")
let fees = ClientDocument.fees(for: estimate)
check(fees.reduce(0) { $0 + $1.amount } == 500, "Private budget excluded from proposal")
let proposal = ClientDocument().contents(project: estimate.title, recipient: nil, fees: fees).blocks.map(\.text).joined()
check(!proposal.contains(plan.title) && !proposal.contains(reimbursed.title), "Private cost descriptions stay out of the proposal")
let project = try db.save(Project(id: UUID(), estimate: estimate))
let milestoneID = UUID()
let items = estimate.openReimbursements
var party = InvoiceParty(name: "Fictional Test Studio", address: "Sample Street 1\n00000 Test City",
                         contact: "Test Desk", email: "test@example.invalid", iban: "DE36000000000000000000")
var electronic = ElectronicParty(party)
electronic.sellerIdentifier = "TEST"
electronic.taxNumber = "TEST"
electronic.phone = "+4900000000"
party.electronicDefaults = electronic
let invoice = IssuedInvoice(number: "TEST-001", issueDate: date, dueDate: date, title: "Test instalment",
                            projectName: estimate.title, sender: party, recipient: party, servicePeriod: "Sample month",
                            paymentTerms: "14 days", net: 290, vatRate: 19, vat: 55.10, milestoneID: milestoneID,
                            buyerReference: "TEST-ROUTE", purchaseOrder: estimate.purchaseOrder, reimbursedCosts: items)
let posted = try db.issueInvoice(projectID: project.id, preferredNumber: invoice.number) { _, _ in invoice }
var ledger = posted.estimate
check(ledger.openReimbursements.isEmpty, "Once-only reimbursement")
check(ledger.effectiveInvoicedTotal(for: milestoneID) == 250, "Reimbursement does not consume a milestone")
check(ledger.invoiceReconciliationNet - ledger.invoiceNetTotal == 250, "Remaining project billing")
var duplicate = invoice
duplicate.id = UUID()
do {
    try ledger.validateInvoice(duplicate)
    preconditionFailure("Duplicate invoice accepted")
} catch {}
let total = BusinessReport(projects: [posted], year: Calendar.current.component(.year, from: date)).totals
check(total.supplierCosts == 135 && total.netInvoiced == 290, "Monthly and annual reports use booked costs")
var sent = ledger
sent.issuedInvoices?[0].sentOn = date
check(!sent.canUndoIssue(sent.issuedInvoices![0]), "Sent invoice retains its ledger entry")
try ledger.undoIssue(invoice.id)
check(ledger.voidedInvoices?.first?.invoice.number == invoice.number && ledger.invoiceNetTotal == 0 && ledger.openReimbursements == items, "Undo retains audit record and releases cost positions")
_ = try db.save(Project(id: posted.id, estimate: ledger))
check(try db.reservedInvoiceNumbers().contains(invoice.number), "Undone number remains reserved")
let corrected = IssuedInvoice(number: "TEST-002", issueDate: date, dueDate: nil, title: "Test correction",
                              projectName: estimate.title, sender: party, recipient: party, servicePeriod: "Sample month",
                              paymentTerms: "", net: -290, vatRate: 19, vat: -55.10, milestoneID: milestoneID,
                              correctionOf: invoice.id, correctionReason: "Test reversal", buyerReference: "TEST-ROUTE",
                              purchaseOrder: invoice.purchaseOrder, reimbursedCosts: items.map(\.reversed))
try sent.validateInvoice(corrected)
sent.issuedInvoices?.append(corrected)
check(sent.openReimbursements == items && sent.effectiveInvoicedTotal(for: milestoneID) == 0, "Reversal reopens reimbursable costs and milestone")
for entry in [invoice, corrected] {
    let structured = XRechnung(invoice: entry, precedingNumber: entry.correctionOf == nil ? nil : invoice.number)
    let bytes = try structured.xml()
    let xml = try XMLDocument(data: bytes)
    let lines = try xml.nodes(forXPath: "//*[local-name()='InvoiceLine' or local-name()='CreditNoteLine']")
    check(lines.count == 2, "UBL contains service and cost as individual positions")
    check(try xml.nodes(forXPath: "//*[local-name()='OrderReference']/*[local-name()='ID']").first?.stringValue == estimate.purchaseOrder, "UBL order reference")
    if XRechnungValidator.installed.available {
        _ = try XRechnungValidator.installed.validate(bytes)
        print("KoSIT accepted " + entry.number)
    }
}
var document = ClientDocument(german: false, invoice: true)
document.purchaseOrder = invoice.purchaseOrder
document.reimbursedCosts = items
let invoiceFees = invoice.positions.map { PhaseFee(name: $0.name, amount: $0.amount, items: []) }
let layout = document.contents(project: estimate.title, recipient: nil, fees: invoiceFees)
let pdf = try layout.pdfData()
let text = PDFDocument(data: pdf)?.string ?? ""
check(text.contains(reimbursed.title) && text.contains("PO<&-123") && !text.contains(plan.title), "PDF shows PO and charge with no private costs")
let template = WordTemplate(document: document)
for legacy in [false, true] {
    var oldTemplate = LetterLayout(invoice: true, footer: [])
    oldTemplate.add("{{project}}")
    oldTemplate.add("{{net}}")
    let file = directory.appendingPathComponent("sample.docx")
    try (legacy ? oldTemplate.wordData() : template.starter()).write(to: file)
    let result = try template.render(source: file, project: estimate.title, client: nil, fees: invoiceFees)
    try result.write(to: file)
    let pipe = Pipe(), unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-p", file.path, "word/document.xml"]
    unzip.standardOutput = pipe
    try unzip.run()
    let xml = try XMLDocument(data: pipe.fileHandleForReading.readDataToEndOfFile())
    unzip.waitUntilExit()
    let content = try xml.nodes(forXPath: "//*[local-name()='t']").compactMap(\.stringValue).joined(separator: " ")
    check(content.contains(reimbursed.title) && content.contains("PO<&-123"), "Custom DOCX includes PO and reimbursement with pre-existing and current templates")
}
let draft = ExportedDocument(filename: "draft_v09.docx", data: Data(), date: date, proposal: false, net: invoice.net, phaseFees: [], exportVersion: 9)
ledger.documents = [draft]
ledger.discardDraft(draft.id)
check(ledger.documents?.isEmpty == true && ledger.discardedExportVersions?["invoice"] == 9, "Draft discard preserves numbering")
print("Financial, invoice export and undo checks passed.")
