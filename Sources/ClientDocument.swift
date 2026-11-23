import AppKit
import CoreText

struct ExportedDocument: Codable, Identifiable {
    var id = UUID()
    let filename: String
    let data: Data
    let date: Date
    let proposal: Bool
    let net: Decimal
    let phaseFees: [PhaseFee]
    var rateTerms: RateTerms?
    var billingPlan: BillingSchedule?
    var billingNet: Decimal?
    var milestoneID: UUID?
    var exportVersion: Int?
    var costBudget: CostBudget?
    var sentOn: Date?
    var acceptedOn: Date?
    var calculationInputs: CalculationInputs?
    var reimbursedCosts: [InvoiceCostItem]?
    var purchaseOrder: String?
}

struct PhaseFee: Codable {
    let name: String
    let amount: Decimal
    let items: [String]
    var scopes: [String: String]?
    var deliverables: [String: String]?
    var startDate: Date?
    var endDate: Date?
}

struct RateTerms: Codable {
    struct Fixed: Codable {
        let phase: String
        let role: String
        let rate: Decimal
    }
    let schedule: Schedule?
    var tiers: [RateTier]?
    let fixed: [Fixed]
    let countOverrides: Bool

    init(_ estimate: Estimate) {
        schedule = estimate.billablePhases.contains { $0.entries.contains { $0.pricing == .producer } } ? estimate.calculationBasis.schedule : nil
        tiers = schedule != nil ? estimate.rateTiers : nil
        fixed = estimate.billablePhases.flatMap { phase in
            phase.entries.filter { $0.pricing == .override }.map { Fixed(phase: phase.name, role: $0.name, rate: $0.rate) }
        }
        countOverrides = estimate.calculationBasis.countOverrides
    }
    func text(_ doc: ClientDocument) -> String {
        func price(_ value: Decimal) -> String { value.formatted(.currency(code: "EUR").locale(doc.locale)) }
        var lines = [String]()
        if let schedule {
            var first = 1
            for band in tiers ?? schedule.tiers {
                let range = band.lastDay.map { "\(first)–\($0)" } ?? "\(first)+"
                lines.append(doc.label("Personentage ", "Producer days ") + range + " · " + price(band.rate) + doc.label(" je Tag", " per day"))
                if let last = band.lastDay { first = last + 1 }
            }
        }
        for item in fixed {
            lines.append([item.phase, item.role].filter { !$0.isEmpty }.joined(separator: " / ") + " · " + price(item.rate) + doc.label(" je Tag (Fest­satz)", " per day (fixed rate)"))
        }
        if !fixed.isEmpty && schedule != nil {
            lines.append(countOverrides ? doc.label("Die Tage zum Festsatz zählen zur Staffel.", "Fixed-rate producer days count towards the tiers.") : doc.label("Die Tage zum Festsatz sind von der Staffel ausgenommen.", "Fixed-rate producer days are excluded from the tier count."))
        }
        return lines.isEmpty ? doc.label("Gemäß Honorarübersicht.", "As set out in the fee summary.") : lines.joined(separator: "\n")
    }
}

struct ClientDocument {
    var german = true
    var invoice = false
    var showItems = false
    var reference = ""
    var purchaseOrder: String?
    var reimbursedCosts: [InvoiceCostItem] = []
    var includedRebate: Decimal?
    var sender = ""
    var scope = ""
    var servicePeriod = ""
    var payment = ""
    var vat: Decimal = 19
    var date = Date()
    func label(_ de: String, _ en: String) -> String { german ? de : en }
    var invoiceName = ""
    var optionalFees: [PhaseFee] = []
    var correctionReference: String?
    var taxAmountOverride: Decimal?
    var exemptionReason = ""
    var milestone: BillingMilestone?
    var milestoneText: String {
        guard let milestone else { return "" }
        return milestone.title(german: german) + " · " + milestone.shareLabel(locale: locale)
    }
    var invoiceIntroduction: String {
        guard let milestone, let stages = billingPlan?.stages, stages.count > 1,
              let index = stages.firstIndex(where: { $0.id == milestone.id }) else {
            return scope.isEmpty ? label("anbei erhalten Sie die Rechnung für die erbrachten Leistungen.", "Please find the invoice for the services provided below.") : scope
        }
        let share = milestone.shareLabel(locale: locale)
        let mixed = stages.contains { $0.fixedAmount != nil }
        let basisDE = milestone.fixedAmount != nil ? "" : (mixed ? " des Restbetrags" : " des vereinbarten Projekthonorars")
        let basisEN = milestone.fixedAmount != nil ? "" : (mixed ? " of the balance" : " of the agreed project fee")
        let germanShare = milestone.fixedAmount == nil ? share.replacingOccurrences(of: "%", with: " %") : share
        let name = milestone.title(german: german)
        let detail = label(
            "Mit dieser Teilrechnung berechnen wir \(germanShare)\(basisDE) (Rate \(index + 1) von \(stages.count), \(name)).",
            "This invoice covers instalment \(index + 1) of \(stages.count) (\(name)), amounting to \(share)\(basisEN)."
        )
        return [scope, detail].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    var defaultInvoiceName: String {
        guard let milestone, let stages = billingPlan?.stages, stages.count > 1,
              let index = stages.firstIndex(where: { $0.id == milestone.id }) else { return label("Rechnung", "Invoice") }
        return label("Teilrechnung", "Partial invoice") + " " + String(index + 1) + label(" von ", " of ") + String(stages.count)
    }
    var title: String {
        guard invoice else { return label("Angebot", "Proposal") }
        let name = invoiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? defaultInvoiceName : name
    }
    var locale: Locale { Locale(identifier: german ? "de_DE" : "en_IE") }

    static func fees(for estimate: Estimate) -> [PhaseFee] {
        let result = estimate.calculate()
        return estimate.billablePhases.map { phase in
            PhaseFee(name: phase.name, amount: result.phases[phase.id] ?? 0,
                     items: phase.entries.filter { !$0.name.isEmpty }.map { entry in
                         if let hours = entry.hoursPerDay, entry.pricing.supportsDayLength { return entry.name + " (" + hours.formatted() + " h)" }
                         return entry.name
                     }, scopes: phase.scopes, deliverables: phase.deliverables, startDate: phase.startDate, endDate: phase.endDate)
        }
    }

    var billingPlan: BillingSchedule?
    var style = DocumentStyle()
    var rateTerms: RateTerms?
    func paymentDays(client: Client?) -> Int? {
        if !payment.isEmpty, payment == billingPlan?.deadline(german: german) { return billingPlan?.days }
        if payment.isEmpty, let days = billingPlan?.days { return days }
        let value = payment.isEmpty ? client?.terms ?? "" : payment
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: " ")
        if parts.count == 2 && ["day", "days", "tag", "tage"].contains(parts[1]), let days = Int(parts[0]), (0...3650).contains(days) { return days }
        return nil
    }
    func paymentText(_ recipient: Client?) -> String {
        let text = payment.isEmpty ? billingPlan?.deadline(german: german) ?? recipient?.terms ?? "" : payment
        let parts = text.lowercased().split(separator: " ")
        let deadline: String
        if parts.count == 2, let days = Int(parts[0]), ["days", "day", "tag", "tage"].contains(parts[1]) {
            deadline = german ? "\(days) " + (days == 1 ? "Tag" : "Tage") : "\(days) " + (days == 1 ? "day" : "days")
        } else { deadline = text }
        if invoice { return deadline }
        return [deadline, billingPlan?.description(german: german) ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
    }
    func resolvedTerms(_ recipient: Client?) -> String {
        InlineText.substituting(["{{payment}}": paymentText(recipient),
                                 "{{day_rates}}": rateTerms?.text(self) ?? label("Gemäß Angebot.", "As agreed in the proposal.")], in: termsText)
    }

    var detailed = false
    var termsText = ""
    var contactDetails = ""
    var bankDetails = ""
    var city = ""
    var taxNumber = ""
    var vatID = ""
    var font = LetterFont.arial
    var logo: Data?

    func contents(project: String, recipient: Client?, fees: [PhaseFee]) -> LetterLayout {
        let identity = sender.isEmpty ? label("[Firmenname]", "[Business name]") : sender
        let address = InlineText.lines(contactDetails)
        var layout = LetterLayout(invoice: invoice, footer: style.customFooter ? [style.leftFooter, style.middleFooter, style.rightFooter] : [
            ([identity] + address.prefix(2)).joined(separator: "\n"),
            address.dropFirst(2).joined(separator: "\n"),
            bankDetails
        ], font: font, logo: style.header == "Brand and contact" ? logo : nil, style: style)
        func money(_ amount: Decimal) -> String {
            amount.formatted(.number.precision(.fractionLength(2)).locale(locale)) + " EUR"
        }
        func phaseName(_ fee: PhaseFee) -> String {
            let names = ["Pre-Production": "Vorproduktion", "Production": "Produktion", "Post-Production": "Postproduktion", "Data-Handling": "Datenhandling"]
            return german ? names[fee.name] ?? fee.name : fee.name
        }
        if style.header == "Brand and contact" {
            layout.letterhead(identity: identity, contact: style.headerText.isEmpty ? contactDetails : style.headerText)
        } else if style.header == "Text only" {
            layout.addHeader(style.headerText.isEmpty ? identity : style.headerText)
        }
        layout.add([recipient?.name ?? label("[Empfänger]", "[Recipient]"), recipient?.contact ?? "", recipient?.address ?? ""].filter { !$0.isEmpty }.joined(separator: "\n"), after: 24)
        layout.add((city.isEmpty ? "" : city + ", ") + date.formatted(.dateTime.day().month(.wide).year().locale(locale)), right: true, after: 16)
        layout.add(title + label(" Nr. ", " No. ") + reference + " – " + project, bold: true, after: 4)
        if let recipient {
            layout.add(label("Kundennummer", "Client number") + "  " + recipient.number, size: 9)
        }
        if invoice {
            if let purchaseOrder, !purchaseOrder.isEmpty { layout.add(label("Auftragsnummer", "Purchase order") + "  " + purchaseOrder) }
            if let correctionReference { layout.add(label("Bezug zur Rechnung", "Original invoice") + "  " + correctionReference, bold: true) }
            layout.add(label("Leistungszeitraum", "Service period") + "  " + (servicePeriod.isEmpty ? "[…]" : servicePeriod), after: 18)
        }
        layout.add(label("Guten Tag,", "Dear team,"), after: 10)
        let proposalIntro = scope.isEmpty ? label("anbei erhalten Sie die Leistungs- und Honorarübersicht für das Projekt.", "Please find the scope of work and proposed fees for the project below.") : scope
        layout.add(invoice ? invoiceIntroduction : proposalIntro, after: 16)
        if !invoice {
            layout.add(label("Projekttimeline", "Project timeline"), bold: true)
            layout.add(servicePeriod.isEmpty ? label("[Zeitraum ergänzen]", "[Add project dates]") : servicePeriod)
            layout.breakPage()
            for (index, fee) in fees.enumerated() {
                layout.add("\(index + 1).0  " + (style.uppercase ? phaseName(fee).uppercased() : phaseName(fee)), size: CGFloat(style.phaseSize), bold: true, band: true, after: 8)
                let dateStyle = Date.FormatStyle.dateTime.day().month().year().locale(locale)
                if let start = fee.startDate {
                    let end = fee.endDate.map { " – " + $0.formatted(dateStyle) } ?? ""
                    layout.add(start.formatted(dateStyle) + end, size: 9)
                } else if let end = fee.endDate { layout.add(label("Bis ", "By ") + end.formatted(dateStyle), size: 9) }
                layout.add(label("Enthaltene Leistungen", "Included services"), bold: true)
                let language = german ? "de" : "en"
                let scope = fee.scopes?[language] ?? ""
                let detail = showItems ? fee.items.map { "•  " + $0 } : []
                let lines = ([scope] + detail).filter { !$0.isEmpty }
                layout.add(lines.isEmpty ? label("[Leistungsumfang ergänzen]", "[Add scope of work]") : lines.joined(separator: "\n"), after: 8)
                let delivery = fee.deliverables?[language] ?? ""
                if detailed || !delivery.isEmpty {
                    layout.add(label("Ergebnis", "Deliverables"), bold: true)
                    layout.add(delivery.isEmpty ? label("[Ergebnisse und Liefertermine ergänzen]", "[Add deliverables and deadlines]") : delivery, after: 6)
                }
                if detailed {
                    layout.add(label("Honorar", "Fee") + "\t" + money(fee.amount), bold: true, after: 14)
                }
            }
            if detailed && !fees.isEmpty { layout.breakPage() }
            layout.add(label("Honorarübersicht", "Fee summary"), bold: true, after: 6)
            for (i, fee) in fees.enumerated() {
                layout.add("\(i + 1).0  " + phaseName(fee) + "\t" + money(fee.amount))
            }
        }
        let net = fees.reduce(Decimal.zero) { $0 + $1.amount }
        if invoice && !reimbursedCosts.isEmpty {
            let service = net - reimbursedCosts.reduce(0) { $0 + $1.amount }
            if service != 0 { layout.add(label("Projekthonorar", "Project fee") + "\t" + money(service)) }
            for item in reimbursedCosts { layout.add(item.title + "\t" + money(item.amount)) }
        }
        var value = net * vat / 100
        var tax = Decimal.zero
        NSDecimalRound(&tax, &value, 2, .plain)
        tax = taxAmountOverride ?? tax
        layout.add(label("Summe Honorare (netto)", "Total fees (net)") + "\t" + money(net), bold: true, after: 8)
        if !invoice, let includedRebate, includedRebate > 0 {
            layout.add(label("Enthaltener Nachlass", "Rebate included") + "\t" + money(includedRebate), size: 9, after: 6)
        }
        layout.add(label("Umsatzsteuer", "VAT") + " (" + vat.formatted(.number.locale(locale)) + "%)\t" + money(tax), after: 8)
        if invoice && vat == 0 && !exemptionReason.isEmpty { layout.add(exemptionReason, size: 10, after: 8) }
        layout.add((invoice ? label("Rechnungsbetrag", "Invoice total") : label("Gesamtbetrag", "Total")) + "\t" + money(net + tax), bold: true, after: 14)
        if !invoice && !optionalFees.isEmpty {
            layout.add(label("Optionale Leistungen", "Optional scope"), bold: true, band: true, after: 6)
            for fee in optionalFees {
                layout.add(phaseName(fee) + "\t" + money(fee.amount))
                if let copy = fee.scopes?[german ? "de" : "en"], !copy.isEmpty { layout.add(copy, after: 5) }
            }
            layout.add(label("Gesamtnetto inkl. Optionen", "Total net including options") + "\t" + money(net + optionalFees.reduce(0) { $0 + $1.amount }), bold: true, after: 14)
        }
        if invoice {
            layout.breakPage()
            layout.add(label("Betrag", "Payment"), bold: true)
            if !bankDetails.isEmpty && correctionReference == nil {
            layout.add(label("Bitte überweisen Sie ", "Please transfer ") + money(net + tax) + label(" auf folgendes Konto.", " to the following account."))
            layout.add(bankDetails, after: 12)
            }
            if !taxNumber.isEmpty { layout.add(label("Steuernummer", "Tax number") + "  " + taxNumber) }
            if !vatID.isEmpty { layout.add(label("USt-IdNr.", "VAT ID") + "  " + vatID) }
        }
        let terms = paymentText(recipient)
        layout.add(label("Zahlungsbedingungen", "Payment terms"), bold: true)
        layout.add(german && terms == "30 days" ? "30 Tage" : (terms.isEmpty ? "[…]" : terms), after: 12)
        layout.add(label("Viele Grüße", "Kind regards") + "\n" + identity)
        if !invoice && !termsText.isEmpty {
            layout.addTerms(title: label("Allgemeine Projektbedingungen", "Project terms"), text: resolvedTerms(recipient))
        }
        return layout
    }

    func encode(_ layout: LetterLayout, pdf: Bool) throws -> Data {
        try pdf ? layout.pdfData() : layout.wordData()
    }
}
