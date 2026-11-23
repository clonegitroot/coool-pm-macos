import Foundation

struct BillingMilestone: Identifiable, Codable, Equatable {
    var id = UUID()
    var percent: Decimal
    var name: String
    var fixedAmount: Decimal?

    func shareLabel(locale: Locale) -> String {
        if let fixedAmount { return fixedAmount.formatted(.currency(code: "EUR").locale(locale)) }
        return percent.formatted(.number.locale(locale)) + "%"
    }
    func title(german: Bool) -> String {
        guard german else { return name }
        return ["Project start": "Projektbeginn", "Mid-project": "Projektmitte", "Delivery": "Lieferung"][name] ?? name
    }
}

struct BillingSchedule: Codable, Equatable {
    var days: Int?
    var stages = [BillingMilestone]()
    private var fixedTotal: Decimal {
        stages.compactMap(\.fixedAmount).reduce(0, +)
    }

    var valid: Bool {
        let percentages = stages.filter { $0.fixedAmount == nil }
        return (days.map { (0...3650).contains($0) } ?? true) &&
            (percentages.isEmpty || percentages.reduce(0) { $0 + $1.percent } == 100) &&
            stages.allSatisfy { stage in
                guard !stage.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                if let fixed = stage.fixedAmount { return fixed > 0 && fixed == cents(fixed) }
                return stage.percent > 0
            }
    }

    func valid(net: Decimal) -> Bool {
        guard valid else { return false }
        if stages.isEmpty { return true }
        let hasPercent = stages.contains { $0.fixedAmount == nil }
        return (hasPercent ? fixedTotal < net : fixedTotal == net)
            && amounts(net: net).values.allSatisfy { $0 > 0 }
    }

    func amounts(net: Decimal) -> [UUID: Decimal] {
        let remaining = max(0, net - fixedTotal)
        var cumulative = Decimal.zero
        var previous = Decimal.zero
        var result = [UUID: Decimal]()
        for stage in stages {
            if let fixed = stage.fixedAmount {
                result[stage.id] = fixed
            } else {
                cumulative += stage.percent
                let rounded = cents(remaining * cumulative / 100)
                result[stage.id] = rounded - previous
                previous = rounded
            }
        }
        return result
    }

    func description(german: Bool) -> String {
        let locale = Locale(identifier: german ? "de_DE" : "en_IE")
        let mixed = stages.contains { $0.fixedAmount != nil } && stages.contains { $0.fixedAmount == nil }
        return stages.map { stage in
            let qualification = mixed && stage.fixedAmount == nil ? (german ? " vom Restbetrag" : " of the balance") : ""
            return stage.shareLabel(locale: locale) + qualification + " · " + stage.title(german: german)
        }.joined(separator: "\n")
    }
    func deadline(german: Bool) -> String? {
        days.map { german ? "Zahlbar innerhalb von \($0) Tagen ab Rechnungsdatum." : "Payable within \($0) days of the invoice date." }
    }
}
