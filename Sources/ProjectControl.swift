import Foundation

enum ProjectStatus: String, CaseIterable, Codable {
    case inquiry = "Anfrage", offered = "Angebot", accepted = "Angenommen", active = "Laufend", invoiced = "Abgerechnet", closed = "Abgeschlossen"

    func label(in locale: Locale) -> String {
        let entry: (key: String, english: String)
        switch self {
        case .inquiry: entry = ("inquiry", "Inquiry")
        case .offered: entry = ("offered", "Proposal")
        case .accepted: entry = ("accepted", "Accepted")
        case .active: entry = ("active", "In progress")
        case .invoiced: entry = ("invoiced", "Invoiced")
        case .closed: entry = ("closed", "Closed")
        }
        let fallback = locale.language.languageCode?.identifier == "de" ? rawValue : entry.english
        return AppLanguage.text("project.status." + entry.key, fallback: fallback, locale: locale)
    }
}

struct CostBudget: Codable {
    struct PhaseBudget: Identifiable, Codable {
        let phase: Phase
        let sales: Decimal
        var id: UUID { phase.id }
    }
    let phases: [PhaseBudget]
    var externalPlans: [ProjectExternalCost]?
    init(_ estimate: Estimate) {
        externalPlans = (estimate.externalCosts ?? []).filter { $0.planned != nil }
        let sales = estimate.calculate().phases
        phases = estimate.billablePhases.map { PhaseBudget(phase: $0, sales: sales[$0.id] ?? 0) }
    }
    init(phases: [PhaseBudget]) { self.phases = phases }
}

struct SupplierBooking: Codable {
    var supplier = ""
    var reference = ""
    var amount: Decimal = 0
    var phaseID: UUID?
    var lineID: UUID?
    var invoiceDate: Date?
    var externalCostID: UUID?
    var billAtCost: Bool?
}

struct ProjectFile: Identifiable, Codable {
    enum Kind: String, Codable { case sent = "Sent invoice", supplier = "Supplier invoice", proposal = "Sent proposal" }
    var id = UUID()
    let kind: Kind
    let name: String
    let data: Data
    var accepted: Date?
    var booking: SupplierBooking?
    var proposalNet: Decimal?
    var markedUnsent: Bool?
}

struct TimeRecord: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var phaseID: UUID?
    var lineID: UUID?
    var days: Decimal = 1
    var rate: Decimal = 0
}

struct ProjectExternalCost: Identifiable, Codable, Equatable {
    var id = UUID()
    var title = ""
    var phaseID: UUID?
    var planned: Decimal?
    var booked: Decimal?
    var date = Date()
    var reimbursable = false
}

struct CostDifference: Identifiable {
    let id: UUID
    let name: String
    let revenue: Decimal
    let supplier: Decimal
    let internalCost: Decimal
    let db1: Decimal
    let db2: Decimal
}

struct CostComparison {
    var differences: [CostDifference] = []

    mutating func explain(_ id: UUID, _ name: String, external: Decimal = 0, internalCost: Decimal = 0, sales: Decimal = 0) {
        let db1 = sales - external
        guard sales != 0 || external != 0 || internalCost != 0 else { return }
        differences.append(CostDifference(id: id, name: name, revenue: sales, supplier: external, internalCost: internalCost, db1: db1, db2: db1 - internalCost))
    }

    var planned = Totals()
    var actual = Totals()
    var forecast = Totals()
}

extension Entry {
    var externalCost: Bool { pricing == .crew || pricing == .expense }
}

extension Estimate {
    var budget: CostBudget? {
        if let saved = documents?.first(where: { $0.id == acceptedProposalID })?.costBudget { return saved }
        return manualBudget
    }
    var controlPhases: [Phase] {
        var rows = budget?.phases.map(\.phase) ?? []
        // Keep links made in earlier versions where an accepted calculation could still be edited.
        let recordedDraftLines: [Phase] = calculationLocked ? phases.compactMap { phase in
            var recorded = phase
            recorded.entries = phase.entries.filter { hasActivity(on: $0.id) }
            return recorded.entries.isEmpty && !hasActivity(in: phase.id) ? nil : recorded
        } : []
        for phase in billablePhases + approvedChanges.map(\.phase) + recordedDraftLines {
            if let index = rows.firstIndex(where: { $0.id == phase.id }) {
                let plannedIDs = Set(rows[index].entries.map(\.id))
                rows[index].entries += phase.entries.filter { !plannedIDs.contains($0.id) }
            } else {
                rows.append(phase)
            }
        }
        return rows
    }
    func hasActivity(in phaseID: UUID) -> Bool {
        (externalCosts ?? []).contains { $0.phaseID == phaseID } ||
        (files ?? []).contains { $0.booking?.phaseID == phaseID } ||
        (timeRecords ?? []).contains { $0.phaseID == phaseID } ||
        (budget?.phases ?? []).contains { $0.id == phaseID }
    }
    func hasActivity(on lineID: UUID) -> Bool {
        (files ?? []).contains { $0.booking?.lineID == lineID } ||
        (timeRecords ?? []).contains { $0.lineID == lineID } ||
        commitments?[lineID] != nil || completedCostLines?.contains(lineID) == true
    }
    var approvedBaseNet: Decimal? {
        documents?.first { $0.id == acceptedProposalID && $0.proposal }?.net ?? acceptedImportedProposal?.proposalNet
    }
    var approvedNet: Decimal? {
        approvedBaseNet.map { $0 + approvedChanges.reduce(0) { $0 + $1.net } }
    }
    var currentBillableNet: Decimal {
        approvedNet ?? (calculate().totals.sales + approvedChanges.reduce(0) { $0 + $1.net })
    }
    var acceptedImportedProposal: ProjectFile? {
        files?.first { $0.id == acceptedProposalID && $0.kind == .proposal }
    }
    var currentStatus: ProjectStatus {
        if let status { return status }
        if acceptedProposalID != nil { return .accepted }
        return documents?.contains { $0.proposal } == true || files?.contains { $0.kind == .proposal } == true ? .offered : .inquiry
    }
    mutating func acceptImportedProposal(_ id: UUID, net: Decimal) throws {
        guard !calculationLocked else { throw LibraryError(description: "A proposal has already been approved. Use a change order for adjustments.") }
        guard let index = files?.firstIndex(where: { $0.id == id && $0.kind == .proposal }),
              net >= 0, net == cents(net) else {
            throw LibraryError(description: "Enter a net fee with up to two decimal places.")
        }
        if currentStatus == .inquiry || currentStatus == .offered { status = .accepted }
        lockedCalculationInputs = calculationInputs
        manualBudget = nil
        files?[index].proposalNet = net
        files?[index].markedUnsent = nil
        acceptedProposalID = id
    }
    mutating func acceptProposal(_ id: UUID) {
        guard !calculationLocked, let index = documents?.firstIndex(where: { $0.id == id && $0.proposal }) else { return }
        if currentStatus == .inquiry || currentStatus == .offered { status = .accepted }
        lockedCalculationInputs = documents?[index].calculationInputs ?? calculationInputs
        manualBudget = nil
        acceptedProposalID = id
        if documents?[index].sentOn == nil { documents?[index].sentOn = .now }
    }
    mutating func setProposalSent(_ id: UUID, isSent: Bool, at date: Date = .now) {
        guard acceptedProposalID != id else { return }
        if let index = documents?.firstIndex(where: { $0.id == id && $0.proposal }) {
            documents?[index].sentOn = isSent ? date : nil
        } else if let index = files?.firstIndex(where: { $0.id == id && $0.kind == .proposal }) {
            files?[index].markedUnsent = isSent ? nil : true
        }
    }
    var linkedExternalCostIDs: Set<UUID> {
        Set((files ?? []).compactMap { $0.booking?.externalCostID })
    }

    // A linked supplier invoice supplies the actual amount for its private estimate.
    var effectiveExternalCosts: [ProjectExternalCost] {
        let bookings = (files ?? []).compactMap(\.booking)
        return (externalCosts ?? []).map { raw in
            guard let source = bookings.first(where: { $0.externalCostID == raw.id }) else { return raw }
            var cost = raw
            cost.booked = source.amount
            cost.reimbursable = source.billAtCost == true
            if let date = source.invoiceDate { cost.date = date }
            return cost
        }
    }

    func costs(for phaseID: UUID?) -> CostComparison {
        let base = budget ?? CostBudget(self)
        let adjustments = approvedChanges.map { CostBudget.PhaseBudget(phase: $0.phase, sales: $0.net) }
        let plan = CostBudget(phases: base.phases + adjustments)
        let selected = plan.phases.filter { phaseID == nil || $0.id == phaseID }
        let plannedIDs = Set(selected.flatMap { $0.phase.entries.map(\.id) })
        let rows = controlPhases.filter { phaseID == nil || $0.id == phaseID }
        let privateIDs = Set((externalCosts ?? []).map(\.id))
        let independentFiles = (files ?? []).filter { $0.booking?.externalCostID.map(privateIDs.contains) != true }
        let invoices = independentFiles.compactMap(\.booking).filter { phaseID == nil || $0.phaseID == phaseID }
        let times = (timeRecords ?? []).filter { phaseID == nil || $0.phaseID == phaseID }
        var value = CostComparison()
        value.planned.sales = selected.reduce(0) { $0 + $1.sales }
        if phaseID == nil, acceptedImportedProposal != nil, let net = approvedNet {
            value.planned.sales = net
        }
        value.actual.sales = value.planned.sales
        value.actual.external = invoices.reduce(0) { $0 + $1.amount }
        value.actual.internalCost = times.reduce(0) { $0 + cents($1.days * $1.rate) }
        value.forecast = value.actual
        var assignedInvoices = Set<UUID>()
        var assignedTime = Set<UUID>()
        for phase in rows {
            for line in phase.entries {
                let planned = cents(line.cost * line.quantity)
                let closed = completedCostLines?.contains(line.id) == true
                if line.externalCost {
                    if plannedIDs.contains(line.id) { value.planned.external += planned }
                    let billed = invoices.filter { $0.lineID == line.id }.reduce(Decimal.zero) { $0 + $1.amount }
                    let expected = commitments?[line.id] ?? planned
                    let remaining = closed ? 0 : max(0, expected - billed)
                    value.forecast.external += remaining
                    assignedInvoices.insert(line.id)
                    value.explain(line.id, phase.name + " · " + (line.name.isEmpty ? line.pricing.rawValue : line.name),
                                  external: billed + remaining - (plannedIDs.contains(line.id) ? planned : 0))
                } else {
                    if plannedIDs.contains(line.id) { value.planned.internalCost += planned }
                    let recorded = times.filter { $0.lineID == line.id }.reduce(Decimal.zero) { $0 + cents($1.days * $1.rate) }
                    let remaining = closed ? 0 : max(0, planned - recorded)
                    value.forecast.internalCost += remaining
                    assignedTime.insert(line.id)
                    value.explain(line.id, phase.name + " · " + (line.name.isEmpty ? line.pricing.rawValue : line.name),
                                  internalCost: recorded + remaining - (plannedIDs.contains(line.id) ? planned : 0))
                }
            }
        }
        for file in independentFiles {
            guard let booking = file.booking, phaseID == nil || booking.phaseID == phaseID else { continue }
            let revenue = booking.billAtCost == true ? booking.amount : 0
            let additionalCost = booking.lineID.map(assignedInvoices.contains) == true ? 0 : booking.amount
            value.actual.sales += revenue
            value.forecast.sales += revenue
            value.explain(file.id, [booking.supplier, booking.reference].joined(separator: " · "), external: additionalCost, sales: revenue)
        }
        for time in times where time.lineID.map(assignedTime.contains) != true {
            value.explain(time.id, time.date.formatted(date: .abbreviated, time: .omitted), internalCost: cents(time.days * time.rate))
        }
        let plannedExtras = (base.externalPlans ?? []).filter { phaseID == nil || $0.phaseID == phaseID }
        let currentExtras = effectiveExternalCosts.filter { phaseID == nil || $0.phaseID == phaseID }
        for id in Set((plannedExtras + currentExtras).map(\.id)).sorted(by: { $0.uuidString < $1.uuidString }) {
            let plan = plannedExtras.first { $0.id == id }
            let current = currentExtras.first { $0.id == id }
            let planned = plan?.planned ?? 0
            let actual = current?.booked ?? 0
            let forecast = current?.booked ?? current?.planned ?? 0
            let revenue = current?.reimbursable == true ? actual : 0
            value.planned.external += planned
            value.actual.external += actual
            value.forecast.external += forecast
            value.actual.sales += revenue
            value.forecast.sales += revenue
            value.explain(id, current?.title ?? plan?.title ?? "", external: forecast - planned, sales: revenue)
        }
        return value
    }

    mutating func book(_ booking: SupplierBooking, fileID: UUID) throws {
        let vendor = booking.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = booking.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vendor.isEmpty, !number.isEmpty, booking.amount > 0, booking.amount == cents(booking.amount),
              let index = files?.firstIndex(where: { $0.id == fileID && $0.kind == .supplier }) else {
            throw LibraryError(description: "Enter a supplier, invoice number, and a positive net amount with up to two decimal places.")
        }
        let billed = invoicedCostIDs
        guard !billed.contains(files?[index].booking?.externalCostID ?? fileID),
              !billed.contains(booking.externalCostID ?? fileID) else {
            throw LibraryError(description: "This cost is on an issued invoice.")
        }
        if let id = booking.externalCostID {
            guard let cost = externalCosts?.first(where: { $0.id == id }), cost.phaseID == booking.phaseID,
                  booking.lineID == nil, !(files ?? []).contains(where: { $0.id != fileID && $0.booking?.externalCostID == id }) else {
                throw LibraryError(description: "Choose an available private cost in this phase.")
            }
        }
        if let lineID = booking.lineID {
            guard let phase = controlPhases.first(where: { $0.id == booking.phaseID }),
                  phase.entries.contains(where: { $0.id == lineID && $0.externalCost }) else {
                throw LibraryError(description: "Select an external cost line from the chosen phase.")
            }
        } else if let phaseID = booking.phaseID, !controlPhases.contains(where: { $0.id == phaseID }) {
            throw LibraryError(description: "The selected production phase is unavailable.")
        }
        for file in files ?? [] where file.id != fileID {
            if let other = file.booking, other.supplier.caseInsensitiveCompare(vendor) == .orderedSame,
               other.reference.caseInsensitiveCompare(number) == .orderedSame {
                throw LibraryError(description: "This supplier invoice is already booked to the project.")
            }
        }
        var cleaned = booking
        cleaned.supplier = vendor
        cleaned.reference = number
        files?[index].booking = cleaned
    }
}
