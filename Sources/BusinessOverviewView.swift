import Charts
import SwiftUI
import UniformTypeIdentifiers

struct BusinessOverviewView: View {
    let projects: [Project]
    var folder: ProjectFolder?
    var folderClient: String?
    var demo = false
    @State private var demoGoals = BusinessMonthlyGoals()

    @Environment(\.locale) private var locale
    @Environment(\.usageFeatures) private var features
    @ProtectedSetting(BusinessMonthlyGoals.storageKey) private var goalsData = Data()
    @State private var year = Calendar(identifier: .gregorian).component(.year, from: .now)
    @State private var month: Int?
    @State private var editingGoal = false
    @State private var hoveredSegment: EarningsSegment?
    @State private var exportError: String?

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = locale
        return value
    }

    private var report: BusinessReport {
        BusinessReport(projects: projects, year: year, month: month, calendar: calendar)
    }

    private var goals: BusinessMonthlyGoals { demo ? demoGoals : BusinessMonthlyGoals(data: goalsData) }

    var body: some View {
        let report = report
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary(report.totals)
                    if report.undatedSupplierCount > 0 {
                        Label("Undated supplier invoices excluded from period costs: \(report.undatedSupplierCount). Add their invoice dates in project documents.", systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let month, folder == nil, features.personalGoals {
                        monthlyGoal(month, actual: report.totals.netInvoiced)
                    } else if month == nil {
                        annualChart
                    }
                    if features.businessReporting { projectList(report.rows) }
                    Text(reportExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(26)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .sheet(isPresented: $editingGoal) {
            BusinessGoalEditor(
                period: month.map { "\(calendar.standaloneMonthSymbols[$0 - 1]) \(year)" } ?? String(year),
                value: month.flatMap { goals[year, $0] },
                wholeYear: month == nil
            ) { value in
                var updated = goals
                if let month { updated[year, month] = value }
                else { updated.setMonthlyGoal(value, forYear: year) }
                if demo { demoGoals = updated } else { goalsData = updated.data }
            }.environment(\.locale, locale)
        }
        .alert("Couldn’t export report", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var detailedMargins: Bool { features.costControlling && features.businessReporting }

    private var reportExplanation: LocalizedStringKey {
        detailedMargins
            ? "Invoices and supplier costs use invoice dates and net amounts. Cash received uses payment dates and includes VAT where charged. DB1 deducts supplier costs, and DB2 also deducts recorded time costs."
            : "Income is net invoiced revenue for the selected period. Expenses include booked supplier costs and recorded internal time costs. Profit is income less these expenses."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            if let folder {
                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.name).font(.largeTitle.bold())
                    if let folderClient {
                        Label("\(folderClient) · Folder report", systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Business overview").font(.largeTitle.bold())
            }
            HStack(spacing: 12) {
                Stepper("Year \(String(year))", value: $year, in: 1...9999)
                    .fixedSize()
                Picker("Period", selection: $month) {
                    Text("Full year").tag(nil as Int?)
                    ForEach(1...12, id: \.self) { month in
                        Text(calendar.standaloneMonthSymbols[month - 1]).tag(Optional(month))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                if detailedMargins {
                    Button("Export CSV…", systemImage: "square.and.arrow.up") { export() }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ totals: BusinessReport.Totals) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            if detailedMargins {
                metric("Net invoiced", totals.netInvoiced, icon: "doc.text")
                metric("Cash received", totals.cashReceived, icon: "eurosign.circle")
                metric("Supplier costs", totals.supplierCosts, icon: "shippingbox")
                metric("Recorded time costs", totals.internalCosts, icon: "clock")
                metric("Contribution (DB1)", totals.db1, icon: "chart.bar")
                metric("Contribution (DB2)", totals.db2, icon: "chart.bar.fill")
            } else {
                metric("Income (net invoiced)", totals.netInvoiced, icon: "doc.text")
                metric("Expenses", totals.supplierCosts + totals.internalCosts, icon: "shippingbox")
                metric("Profit", totals.db2, icon: "chart.bar.fill")
            }
        }
    }

    private func metric(_ title: LocalizedStringKey, _ amount: Decimal, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(currency(amount))
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(amount < 0 ? Color.red : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.075), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.18)) }
    }

    private func monthlyGoal(_ month: Int, actual: Decimal) -> some View {
        let goal = goals[year, month]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Monthly earnings goal").font(.headline)
                Spacer()
                Button(goal == nil ? LocalizedStringKey("Set goal…") : "Edit goal…") { editingGoal = true }
            }
            if let goal {
                let progress = NSDecimalNumber(decimal: actual / goal).doubleValue
                Text("\(currency(actual)) of \(currency(goal)) net invoiced")
                    .font(.callout.monospacedDigit())
                ProgressView(value: min(max(progress, 0), 1))
                    .accessibilityLabel("Monthly earnings goal")
            } else {
                Text("Set a net invoicing target for this month.")
                    .foregroundStyle(.secondary).font(.callout)
            }
        }
        .padding(15)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    private var annualChart: some View {
        let goals = folder == nil && features.personalGoals ? goals : BusinessMonthlyGoals()
        let calendar = calendar
        let labels = calendar.shortStandaloneMonthSymbols
        let segments = EarningsSegment.year(projects, year: year, calendar: calendar)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Monthly earnings").font(.headline)
                Spacer()
                if folder == nil && features.personalGoals {
                    Label("Goal", systemImage: "diamond.fill").foregroundStyle(.orange)
                    Button("Set monthly goal for year…") { editingGoal = true }
                }
            }
            Chart {
                ForEach(segments) { segment in
                    BarMark(x: .value("Month", labels[segment.month - 1]),
                            yStart: .value("From", segment.start), yEnd: .value("To", segment.end))
                        .foregroundStyle(segment.color)
                        .accessibilityLabel(Text("\(labels[segment.month - 1]) · \(segment.projectName)"))
                        .accessibilityValue(Text(currency(segment.amount)))
                }
                ForEach(1...12, id: \.self) { month in
                    if let goal = goals[year, month] {
                        PointMark(x: .value("Month", labels[month - 1]),
                                  y: .value("Goal", NSDecimalNumber(decimal: goal).doubleValue))
                            .foregroundStyle(.orange).symbol(.diamond)
                    }
                }
            }
            .chartXScale(domain: labels)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                        guard case .active(let pointer) = phase, let plot = proxy.plotFrame,
                              geometry[plot].contains(pointer),
                              let label: String = proxy.value(atX: pointer.x - geometry[plot].minX),
                              let index = labels.firstIndex(of: label),
                              let value: Double = proxy.value(atY: pointer.y - geometry[plot].minY)
                        else { hoveredSegment = nil; return }
                        hoveredSegment = segments.first {
                            $0.month == index + 1 && (min($0.start, $0.end)...max($0.start, $0.end)).contains(value)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(amount.formatted(.number.notation(.compactName).locale(locale)) + " €")
                        }
                    }
                }
            }
            .frame(height: 180)
            HStack(spacing: 6) {
                if let segment = hoveredSegment, segments.contains(where: { $0.id == segment.id }) {
                    Circle().fill(segment.color).frame(width: 8, height: 8)
                    Text("\(labels[segment.month - 1]) · \(segment.projectName) · \(currency(segment.amount))")
                } else {
                    Text("Hover over a bar segment to see its project and net revenue.").foregroundStyle(.secondary)
                }
            }.font(.caption).frame(height: 18)
        }
        .padding(15)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func projectList(_ rows: [BusinessReport.Row]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project breakdown").font(.headline)
            if rows.isEmpty {
                Text("There are no recorded transactions for this period.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Project").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Net invoiced").gridColumnAlignment(.trailing)
                        Text(detailedMargins ? LocalizedStringKey("Costs") : "Expenses").gridColumnAlignment(.trailing)
                        Text(detailedMargins ? LocalizedStringKey("DB2") : "Profit").gridColumnAlignment(.trailing)
                        if detailedMargins { Color.clear.frame(width: 24, height: 1) }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(rows.sorted { $0.name.compare($1.name, options: [.caseInsensitive, .numeric], locale: locale) == .orderedAscending }) { row in
                        Divider()
                        GridRow {
                            Text(row.name).lineLimit(1).help(row.name)
                            Text(currency(row.totals.netInvoiced))
                            Text(currency(row.totals.supplierCosts + row.totals.internalCosts))
                            Text(currency(row.totals.db2))
                                .foregroundStyle(row.totals.db2 < 0 ? Color.red : Color.primary)
                            if detailedMargins {
                                Button { export(projectID: row.id) } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .help("Export project CSV…")
                                .accessibilityLabel("Export project CSV…")
                            }
                        }
                        .monospacedDigit().font(.callout)
                    }
                }
            }
        }
    }

    private func currency(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "EUR").locale(locale))
    }

    private func export(projectID: UUID? = nil) {
        let selected = projects.filter { projectID == nil || $0.id == projectID }
        let report = BusinessReport(projects: selected, year: year, month: month, calendar: calendar)
        let overview = folder?.name ?? AppLanguage.text("Business overview", fallback: "Business overview", locale: locale)
        let name = projectID == nil ? overview : (selected.first?.estimate.title ?? overview)
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let safeName = name.components(separatedBy: unsafe).joined(separator: "-").prefix(150)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(report.period)_\(safeName).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.csv(locale: locale).write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct BusinessGoalEditor: View {
    let period: String
    let value: Decimal?
    let wholeYear: Bool
    let save: (Decimal?) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var amount = ""

    private var validAmount: Decimal? {
        let input = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let decimal = NSRegularExpression.escapedPattern(for: locale.decimalSeparator ?? ".")
        let grouping = NSRegularExpression.escapedPattern(for: locale.groupingSeparator ?? ",")
        let currencyPattern = "^(?:[0-9]+|[0-9]{1,3}(?:\(grouping)[0-9]{3})+)(?:\(decimal)[0-9]{1,2})?$"
        guard input.range(of: currencyPattern, options: .regularExpression) != nil,
              let amount = Decimal(string: input.replacingOccurrences(of: locale.groupingSeparator ?? ",", with: ""), locale: locale),
              amount > 0 else { return nil }
        return amount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monthly earnings goal").font(.title2.bold())
            Text(period).foregroundStyle(.secondary)
            if wholeYear {
                Text("This sets the same net invoicing goal for all twelve months, including months with an existing goal.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextField("Net earnings goal in EUR", text: $amount, prompt: Text("Amount in EUR"))
                .focused($focused)
            HStack {
                if value != nil {
                    Button("Remove goal", role: .destructive) { finish(nil) }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if let validAmount { finish(validAmount) } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validAmount == nil)
            }
        }
        .padding(22)
        .frame(width: 410)
        .onAppear {
            if let value { amount = value.formatted(.number.locale(locale)) }
            focused = true
        }
    }

    private func finish(_ value: Decimal?) {
        save(value)
        dismiss()
    }
}

private struct EarningsSegment: Identifiable {
    struct ID: Hashable { let month: Int; let project: UUID }
    let id: ID
    let projectName: String
    let month: Int
    let amount: Decimal
    let start: Double
    let end: Double
    let color: Color

    static func year(_ projects: [Project], year: Int, calendar: Calendar) -> [Self] {
        let sorted = projects.sorted { $0.id.uuidString < $1.id.uuidString }
        var above = Array(repeating: Decimal.zero, count: 12)
        var below = above
        var result: [Self] = []
        for (index, project) in sorted.enumerated() {
            var byMonth: [Int: Decimal] = [:]
            for invoice in project.estimate.issuedInvoices ?? [] {
                let date = calendar.dateComponents([.year, .month], from: invoice.issueDate)
                guard date.year == year, let month = date.month else { continue }
                byMonth[month, default: 0] += invoice.net
            }
            let hue = (0.46 + Double(index) * 0.618034).truncatingRemainder(dividingBy: 1)
            for (month, amount) in byMonth.sorted(by: { $0.key < $1.key }) where amount != 0 {
                let slot = month - 1
                let base = amount > 0 ? above[slot] : below[slot]
                let end = base + amount
                if amount > 0 { above[slot] = end } else { below[slot] = end }
                result.append(Self(id: ID(month: month, project: project.id), projectName: project.estimate.title,
                                   month: month, amount: amount, start: NSDecimalNumber(decimal: base).doubleValue,
                                   end: NSDecimalNumber(decimal: end).doubleValue,
                                   color: Color(hue: hue, saturation: 0.62, brightness: 0.73)))
            }
        }
        return result
    }
}
