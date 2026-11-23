import Foundation

struct BusinessReport {
    struct Totals: Equatable {
        var netInvoiced: Decimal = 0
        var cashReceived: Decimal = 0
        var supplierCosts: Decimal = 0
        var internalCosts: Decimal = 0
        var db1: Decimal { netInvoiced - supplierCosts }
        var db2: Decimal { db1 - internalCosts }

        mutating func add(_ value: Self) {
            netInvoiced += value.netInvoiced
            cashReceived += value.cashReceived
            supplierCosts += value.supplierCosts
            internalCosts += value.internalCosts
        }
    }

    struct Row: Identifiable {
        let id: UUID
        let name: String
        let totals: Totals
        let undatedSupplierCount: Int
    }

    let year: Int
    let month: Int?
    let validPeriod: Bool
    let rows: [Row]
    let totals: Totals
    let undatedSupplierCount: Int
    var period: String { month.map { BusinessMonthlyGoals.key(year: year, month: $0) } ?? String(year) }

    init(projects: [Project], year: Int, month: Int? = nil, calendar: Calendar = .current) {
        self.year = year
        self.month = month
        guard (1...9999).contains(year), month.map({ (1...12).contains($0) }) ?? true,
              let start = calendar.date(from: DateComponents(year: year, month: month ?? 1, day: 1)),
              let interval = calendar.dateInterval(of: month == nil ? .year : .month, for: start) else {
            validPeriod = false
            rows = []
            totals = Totals()
            undatedSupplierCount = 0
            return
        }
        validPeriod = true

        func includes(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

        var reportTotals = Totals()
        var undatedCount = 0
        rows = projects.compactMap { project in
            let estimate = project.estimate
            var totals = Totals()
            var hasActivity = false
            var undated = 0

            for invoice in estimate.issuedInvoices ?? [] {
                if includes(invoice.issueDate) {
                    hasActivity = true
                    totals.netInvoiced += invoice.net
                }
                for payment in invoice.payments where includes(payment.date) {
                    hasActivity = true
                    totals.cashReceived += payment.amount
                }
            }
            for file in estimate.files ?? [] where file.kind == .supplier {
                guard let booking = file.booking else { continue }
                guard let invoiceDate = booking.invoiceDate else {
                    undated += 1
                    continue
                }
                if includes(invoiceDate) {
                    hasActivity = true
                    totals.supplierCosts += booking.amount
                }
            }
            let linked = estimate.linkedExternalCostIDs
            for cost in estimate.externalCosts ?? [] where !linked.contains(cost.id) && includes(cost.date) {
                if let amount = cost.booked {
                    hasActivity = true
                    totals.supplierCosts += amount
                }
            }
            for record in estimate.timeRecords ?? [] where includes(record.date) {
                hasActivity = true
                totals.internalCosts += cents(record.days * record.rate)
            }

            reportTotals.add(totals)
            undatedCount += undated
            guard hasActivity || undated > 0 else { return nil }
            return Row(id: project.id, name: estimate.title, totals: totals, undatedSupplierCount: undated)
        }
        totals = reportTotals
        undatedSupplierCount = undatedCount
    }

    func csv(locale: Locale) -> Data {
        let headings = [
            "Period", "Project", "Net invoiced (EUR)", "Cash received incl. VAT (EUR)",
            "Supplier costs net (EUR)", "Recorded time costs (EUR)", "DB1 (EUR)", "DB2 (EUR)",
            "Undated supplier invoices (all periods)"
        ].map { AppLanguage.text($0, fallback: $0, locale: locale) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        func amount(_ value: Decimal) -> String {
            formatter.string(from: NSDecimalNumber(decimal: value)) ?? String(describing: value)
        }
        func record(_ name: String, _ values: Totals, _ undated: Int) -> [String] {
            [
                period, name, amount(values.netInvoiced), amount(values.cashReceived),
                amount(values.supplierCosts), amount(values.internalCosts), amount(values.db1), amount(values.db2), String(undated)
            ]
        }
        func escape(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func sanitizeTitle(_ title: String) -> String {
            let ignored = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
            guard let first = title.unicodeScalars.first(where: { !ignored.contains($0) }),
                  "=+-@＝＋－＠".unicodeScalars.contains(first) else {
                return title
            }
            return "'" + title
        }

        let sorted = rows.sorted { lhs, rhs in
            let order = lhs.name.compare(rhs.name, options: [.caseInsensitive, .numeric], locale: locale)
            return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
        }
        let body = sorted.map { record(sanitizeTitle($0.name), $0.totals, $0.undatedSupplierCount) }
        let total = record(AppLanguage.text("Total", fallback: "Total", locale: locale), totals, undatedSupplierCount)
        let lines = ([headings] + body + [total]).map { $0.map(escape).joined(separator: ";") }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }
}

struct BusinessMonthlyGoals: Codable {
    static let storageKey = "businessMonthlyGoals"
    private var amounts: [String: Decimal] = [:]

    init(data: Data = Data()) {
        if let saved = try? JSONDecoder().decode(Self.self, from: data) { self = saved }
    }

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    mutating func setMonthlyGoal(_ value: Decimal?, forYear year: Int) {
        for month in 1...12 { self[year, month] = value }
    }

    static func key(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    subscript(year: Int, month: Int) -> Decimal? {
        get { amounts[Self.key(year: year, month: month)].flatMap { $0 > 0 ? $0 : nil } }
        set { amounts[Self.key(year: year, month: month)] = newValue }
    }
}
