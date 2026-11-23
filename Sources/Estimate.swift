import Foundation

struct DocumentDraft: Codable {
    var invoiceNames: [String: String]?
    var letter = ""
    var period = ""
    var payment = ""
    var terms = ""
}

enum Pricing: String, Codable, CaseIterable {
    case producer = "Own · progressive", override = "Own · fixed rate", crew = "Crew", fee = "Fixed fee", expense = "Expense"
    case team = "Internal crew", equipment = "Owned equipment"

    var titleKey: String { self == .crew ? "External crew" : rawValue }
    var supportsDayLength: Bool {
        self == .producer || self == .override || self == .crew || self == .team
    }
    var tracksInternalTime: Bool { self == .producer || self == .override || self == .team }
}

/// Decode historical named schedules, then carry their actual tiers in all new saves and backups.
struct Schedule: Codable, Equatable {
    let tiers: [RateTier]
    private var legacyName: String?
    static let legacyDigestKey = CodingUserInfoKey(rawValue: "cooolpm.digest.legacySchedule")!
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.tiers == rhs.tiers }

    init(tiers: [RateTier]) { self.tiers = tiers }

    static let unconfigured = Self(tiers: [RateTier(lastDay: nil, rate: 0)])
    static let standard = Self(tiers: [RateTier(lastDay: 4, rate: 900), RateTier(lastDay: 20, rate: 800),
                                       RateTier(lastDay: nil, rate: 750)])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let name = try? value.decode(String.self) {
            switch name {
            case "Unconfigured": self = .unconfigured
            case "Standard 2026": self = .standard
            case "Extended booking": self.init(tiers: [RateTier(lastDay: 10, rate: 850), RateTier(lastDay: nil, rate: 700)])
            default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unrecognized legacy day-rate schedule.")
            }
            legacyName = name
        } else {
            let tiers = try value.decode([RateTier].self)
            guard RateTier.valid(tiers) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid day-rate tiers.")
            }
            self.init(tiers: tiers)
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        if let legacyName, encoder.userInfo[Self.legacyDigestKey] as? Bool == true {
            try value.encode(legacyName)
        } else {
            try value.encode(tiers)
        }
    }

    func fee(through days: Decimal) -> Decimal {
        RateTier.fee(tiers: tiers, through: days)
    }
}

struct RateTier: Codable, Equatable {
    var lastDay: Int?
    var rate: Decimal

    static func valid(_ tiers: [RateTier]) -> Bool {
        guard let last = tiers.last, last.lastDay == nil else { return false }
        var previous = 0
        for tier in tiers.dropLast() {
            guard let day = tier.lastDay, day > previous, day < Int.max else { return false }
            previous = day
        }
        return tiers.allSatisfy { $0.rate >= 0 && $0.rate == cents($0.rate) }
    }

    static func fee(tiers: [RateTier], through days: Decimal) -> Decimal {
        var start = Decimal.zero
        var amount = Decimal.zero
        for tier in tiers {
            let end = tier.lastDay.map { min(days, Decimal($0)) } ?? days
            amount += max(0, end - start) * tier.rate
            if let lastDay = tier.lastDay { start = Decimal(lastDay) }
        }
        return amount
    }
}

enum PhaseOption: String, Codable, CaseIterable {
    case pending, accepted, declined

    var title: String {
        switch self {
        case .pending: return "Optional"
        case .accepted: return "Option accepted"
        case .declined: return "Option declined"
        }
    }
}

struct Entry: Identifiable, Codable {
    var id = UUID()
    var name = ""
    var pricing = Pricing.producer
    var quantity: Decimal = 1
    var hoursPerDay: Decimal?
    var effectiveHoursPerDay: Decimal { hoursPerDay ?? 8 }
    var rate: Decimal = 0
    var cost: Decimal = 0
    var pricingPresetID: UUID?
    var pricingLabel: String?

    func pricingTitle(in locale: Locale) -> String {
        pricingLabel ?? AppLanguage.text(pricing.titleKey, fallback: pricing.titleKey, locale: locale)
    }
}

struct Phase: Identifiable, Codable {
    var id = UUID()
    var name = "Production"
    var entries = [Entry()]
    var scopes: [String: String]?
    var deliverables: [String: String]?
    var startDate: Date?
    var endDate: Date?
    var option: PhaseOption?

    func displayName(in locale: Locale) -> String {
        guard Estimate.standardPhases.contains(name) else { return name }
        return AppLanguage.text(name, fallback: name, locale: locale)
    }

    var includedInFee: Bool { option == nil || option == .accepted }
}

struct ChangeOrder: Identifiable, Codable {
    enum Status: String, Codable {
        case pending = "Pending", approved = "Approved", declined = "Declined"
    }

    var id = UUID()
    var createdAt = Date()
    var decidedAt: Date?
    var status = Status.pending
    let sourcePhaseID: UUID?
    let title: String
    let notes: String
    let phase: Phase
    let net: Decimal
}

struct Totals {
    var sales: Decimal = 0
    var external: Decimal = 0
    var internalCost: Decimal = 0
    var db1: Decimal { sales - external }
    var db2: Decimal { db1 - internalCost }
}

struct CalculationInputs: Codable {
    let phases: [Phase]
    let schedule: Schedule
    let customTiers: [RateTier]?
    let appliedDayRateName: String?
    let countOverrides: Bool
    let projectRebatePercent: Decimal?
    let clientRebatePercent: Decimal?

    var rateTiers: [RateTier] {
        guard let customTiers, RateTier.valid(customTiers) else { return schedule.tiers }
        return customTiers
    }

    var rebatePercent: Decimal {
        let value = projectRebatePercent ?? clientRebatePercent ?? 0
        return (0...100).contains(value) ? value : 0
    }
}

struct Estimate: Codable {
    var featureOverrides: UsageFeatureOverrides?
    var projectNumber: String?
    var provisionalProjectNumber: Bool?
    static let untitledTitle = "Untitled production"
    var title = Self.untitledTitle

    var hasProjectTitle: Bool {
        title != Self.untitledTitle && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func displayTitle(in locale: Locale) -> String {
        hasProjectTitle ? title : AppLanguage.text(Self.untitledTitle, fallback: Self.untitledTitle, locale: locale)
    }
    var client = ""
    var clientNumber = ""
    var clientID: UUID?
    var endClientID: UUID?
    var invoiceClientID: UUID?
    var proposalContactID: UUID?
    var invoiceContactID: UUID?
    var folderID: UUID?
    var archivedAt: Date?
    var projectRebatePercent: Decimal?
    var clientRebatePercent: Decimal?
    var documents: [ExportedDocument]?
    var issuedInvoices: [IssuedInvoice]?
    var voidedInvoices: [VoidedInvoice]?
    var discardedExportVersions: [String: Int]?
    var changeOrders: [ChangeOrder]?
    var approvedChanges: [ChangeOrder] { (changeOrders ?? []).filter { $0.status == .approved } }
    var status: ProjectStatus?
    var files: [ProjectFile]?
    var purchaseOrder: String?
    var plannedStart: Date?
    var plannedEnd: Date?
    var externalCosts: [ProjectExternalCost]?
    var manualBudget: CostBudget?
    var timeRecords: [TimeRecord]?
    var commitments: [UUID: Decimal]?
    var completedCostLines: Set<UUID>?
    var acceptedProposalID: UUID?
    var lockedCalculationInputs: CalculationInputs?
    var billing: BillingSchedule?
    var issuedInstalment: IssuedInvoice? { issuedInvoices?.first { $0.milestoneID != nil && $0.correctionOf == nil } }
    var firstInstalment: ExportedDocument? { documents?.first { $0.milestoneID != nil } }
    var documentNumbers: [String: String]?
    var documentDrafts: [String: DocumentDraft]?
    var schedule = Schedule.unconfigured
    var customTiers: [RateTier]?
    var appliedDayRateName: String?
    var calculationLocked: Bool { acceptedProposalID != nil }
    var calculationInputs: CalculationInputs {
        CalculationInputs(phases: phases, schedule: schedule, customTiers: customTiers,
                          appliedDayRateName: appliedDayRateName, countOverrides: countOverrides,
                          projectRebatePercent: projectRebatePercent, clientRebatePercent: clientRebatePercent)
    }
    var calculationBasis: CalculationInputs {
        guard calculationLocked else { return calculationInputs }
        return documents?.first(where: { $0.proposal && $0.id == acceptedProposalID })?.calculationInputs
            ?? lockedCalculationInputs ?? calculationInputs
    }
    func duplicateCalculation(titled title: String) -> Estimate {
        let basis = calculationBasis
        var copy = Estimate()
        copy.title = title
        copy.featureOverrides = featureOverrides
        copy.schedule = basis.schedule
        copy.customTiers = basis.customTiers
        copy.appliedDayRateName = basis.appliedDayRateName
        copy.countOverrides = basis.countOverrides
        copy.projectRebatePercent = basis.projectRebatePercent
        copy.phases = basis.phases.map { original in
            var phase = original
            phase.id = UUID()
            phase.startDate = nil
            phase.endDate = nil
            phase.entries = original.entries.map { original in
                var entry = original
                entry.id = UUID()
                return entry
            }
            return phase
        }
        return copy
    }

    var rateTiers: [RateTier] { calculationBasis.rateTiers }

    mutating func preserveApprovedCalculation(from previous: Estimate) {
        guard previous.calculationLocked else { return }
        acceptedProposalID = previous.acceptedProposalID
        lockedCalculationInputs = previous.lockedCalculationInputs ?? previous.calculationBasis
        phases = previous.phases
        schedule = previous.schedule
        customTiers = previous.customTiers
        appliedDayRateName = previous.appliedDayRateName
        countOverrides = previous.countOverrides
        projectRebatePercent = previous.projectRebatePercent
        clientRebatePercent = previous.clientRebatePercent
    }

    private var phasesWithoutApprovedChanges: [Phase] {
        let approvedSources = Set(approvedChanges.compactMap(\.sourcePhaseID))
        return calculationBasis.phases.filter { !approvedSources.contains($0.id) }
    }
    var billablePhases: [Phase] { phasesWithoutApprovedChanges.filter(\.includedInFee) }
    var pendingOptionPhases: [Phase] { phasesWithoutApprovedChanges.filter { $0.option == .pending } }

    mutating func decideChange(id: UUID, status: ChangeOrder.Status, on date: Date = .now) {
        guard status != .pending, let index = changeOrders?.firstIndex(where: { $0.id == id }),
              changeOrders?[index].status == .pending else { return }
        changeOrders?[index].status = status
        changeOrders?[index].decidedAt = date
    }
    var countOverrides = false
    var phases = [Phase()]

    fileprivate static let standardPhases = ["Pre-Production", "Production", "Post-Production", "Data-Handling"]

    private func standardIndex(_ name: String) -> Int? {
        let key = name.lowercased().filter { $0.isLetter }
        return Self.standardPhases.firstIndex { $0.lowercased().filter { $0.isLetter } == key }
    }

    var hasStandardPhases: Bool {
        Set(phases.compactMap { standardIndex($0.name) }).count == Self.standardPhases.count
    }

    mutating func generateStandardPhases() {
        for (index, name) in Self.standardPhases.enumerated() {
            guard !phases.contains(where: { standardIndex($0.name) == index }) else { continue }
            let next = phases.firstIndex { (standardIndex($0.name) ?? -1) > index }
            phases.insert(Phase(name: name, entries: []), at: next ?? phases.endIndex)
        }
    }

    struct Calculation {
        var lines: [UUID: Decimal] = [:]
        var phases: [UUID: Decimal] = [:]
        var totals = Totals()
        var rebate: Decimal = 0
    }

    func calculate(includingPendingOptions: Bool = false) -> Calculation {
        var result = Calculation()
        var days: Decimal = 0
        let activePhases = billablePhases + (includingPendingOptions ? pendingOptionPhases : [])
        let basis = calculationBasis
        let tiers = basis.rateTiers
        var eligibleSales: Decimal = 0
        let rebateFraction = basis.rebatePercent / 100
        for phase in activePhases {
            for line in phase.entries {
                let units = line.quantity
                let sales: Decimal
                if line.pricing == .producer {
                    sales = RateTier.fee(tiers: tiers, through: days + units) - RateTier.fee(tiers: tiers, through: days)
                    days += units
                } else {
                    sales = units * line.rate
                    if line.pricing == .override && basis.countOverrides { days += units }
                }
                let rounded = cents(sales)
                var net = rounded
                if !line.externalCost, rebateFraction > 0 {
                    eligibleSales += rounded
                    let cumulativeRebate = cents(eligibleSales * rebateFraction)
                    net -= cumulativeRebate - result.rebate
                    result.rebate = cumulativeRebate
                }
                result.lines[line.id] = net
                result.phases[phase.id, default: 0] += net
                result.totals.sales += net
                let cost = cents(units * line.cost)
                if line.externalCost { result.totals.external += cost }
                else { result.totals.internalCost += cost }
            }
        }
        return result
    }
}

func cents(_ value: Decimal) -> Decimal {
    var input = value
    var output = Decimal()
    NSDecimalRound(&output, &input, 2, .plain)
    return output
}
