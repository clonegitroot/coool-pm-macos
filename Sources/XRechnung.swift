import Foundation

struct ElectronicParty: Codable, Equatable {
    var name: String
    var street: String
    var postcode: String
    var city: String
    var country = "DE"
    var endpoint: String
    var endpointScheme = "EM"
    var contact = ""
    var phone = ""
    var email = ""
    var vatID = ""
    var taxNumber = ""
    var sellerIdentifier: String?
    var legalRegistrationID: String?

    init(_ party: InvoiceParty?) {
        name = party?.name ?? ""
        var lines = (party?.address ?? "").components(separatedBy: .newlines).filter { !$0.isEmpty }
        if let index = lines.firstIndex(where: { $0.range(of: #"^\d{5}\s+\S"#, options: .regularExpression) != nil }) {
            let line = lines.remove(at: index)
            postcode = String(line.prefix(5))
            city = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        } else {
            postcode = ""
            city = ""
        }
        street = lines.first ?? ""
        endpoint = party?.email ?? ""
        email = party?.email ?? ""
        contact = party?.contact.isEmpty == false ? party?.contact ?? "" : name
        vatID = party?.vatID ?? ""
        taxNumber = party?.taxNumber ?? ""
    }

    func applying(_ defaults: ElectronicParty?, preserveIdentity: Bool = false) -> Self {
        guard let defaults else { return self }
        var result = self
        for field in [\Self.street, \.postcode, \.city, \.country, \.endpoint, \.endpointScheme, \.contact, \.phone, \.email] {
            let value = defaults[keyPath: field].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result[keyPath: field] = value }
        }
        for field in [\Self.name, \.vatID, \.taxNumber] {
            let value = defaults[keyPath: field].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty && (!preserveIdentity || result[keyPath: field].isEmpty) { result[keyPath: field] = value }
        }
        result.sellerIdentifier = defaults.sellerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.legalRegistrationID = defaults.legalRegistrationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

struct ElectronicInvoiceDefaults: Codable, Equatable {
    var seller = ElectronicParty(nil)
    var iban = ""
}

struct ElectronicRecipientDefaults: Codable, Equatable {
    var buyer = ElectronicParty(nil)
    var buyerReference = ""
}

struct XRechnung {
    let invoice: IssuedInvoice
    var precedingNumber: String?
    var seller: ElectronicParty
    var buyer: ElectronicParty
    var buyerReference = ""
    var iban = ""
    var serviceStart: Date
    var serviceEnd: Date
    var exemption = ""

    init(invoice: IssuedInvoice, precedingNumber: String?, sellerDefaults: ElectronicInvoiceDefaults? = nil,
         buyerDefaults: ElectronicRecipientDefaults? = nil) {
        self.invoice = invoice
        self.precedingNumber = precedingNumber
        seller = ElectronicParty(invoice.sender).applying(invoice.sender?.electronicDefaults ?? sellerDefaults?.seller,
                                                          preserveIdentity: true)
        buyer = ElectronicParty(invoice.recipient).applying(invoice.recipient?.electronicDefaults ?? buyerDefaults?.buyer,
                                                            preserveIdentity: true)
        buyerReference = invoice.buyerReference ?? buyerDefaults?.buyerReference ?? ""
        iban = invoice.sender?.iban?.isEmpty == false ? (invoice.sender?.iban ?? "") : (sellerDefaults?.iban ?? "")
        exemption = invoice.vatExemptionReason ?? ""
        serviceStart = invoice.issueDate
        serviceEnd = invoice.issueDate
    }

    var missingFields: [String] {
        func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        func partyFields(_ party: ElectronicParty) -> [(String, String)] {
            [(party.name, "Name"), (party.street, "Street"), (party.postcode, "Postcode"), (party.city, "City"),
             (party.country, "Country code"), (party.endpoint, "Electronic address"), (party.endpointScheme, "Electronic address scheme")]
        }
        let sellerDetails = partyFields(seller) + [(seller.contact, "Contact name"), (seller.phone, "Phone"), (seller.email, "Contact email")]
        var issues: [String] = []
        if sellerDetails.contains(where: { !filled($0.0) }) { issues.append("Complete the seller’s address, electronic address and contact fields.") }
        if partyFields(buyer).contains(where: { !filled($0.0) }) { issues.append("Complete the buyer’s postal and electronic address.") }
        if !filled(seller.vatID) && !filled(seller.taxNumber) { issues.append("Enter the seller’s tax number or VAT ID.") }
        if !filled(seller.vatID) && !filled(seller.sellerIdentifier ?? "") && !filled(seller.legalRegistrationID ?? "") {
            issues.append("Enter a seller identifier, legal registration ID, or VAT ID.")
        }
        if !filled(buyerReference) { issues.append("Enter the buyer reference or Leitweg-ID.") }
        if !filled(iban) { issues.append("Enter an IBAN.") }
        if serviceEnd < serviceStart { issues.append("The service end date must be on or after the start date.") }
        if invoice.vatRate == 0 && !filled(exemption) { issues.append("Enter the VAT exemption reason.") }
        if invoice.correctionOf != nil {
            if precedingNumber?.isEmpty != false { issues.append("The original invoice number is missing.") }
        } else if invoice.dueDate == nil && !filled(invoice.paymentTerms) {
            issues.append("The issued invoice needs a due date or payment terms.")
        }
        return issues
    }

    func xml() throws -> Data {
        guard missingFields.isEmpty else {
            throw LibraryError(description: "Complete the XRechnung addresses, contact details, buyer reference, payment details and service dates.")
        }
        func escape(_ value: String) -> String {
            let clean = String(value.unicodeScalars.filter { $0.value >= 32 || [9,10,13].contains($0.value) })
            return clean.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func c(_ name: String, _ value: String, attributes: String = "") -> String {
            "<cbc:\(name)\(attributes)>\(escape(value))</cbc:\(name)>"
        }
        func date(_ value: Date) -> String {
            let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: value)
            return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        }
        func amount(_ value: Decimal) -> String { NSDecimalNumber(decimal: abs(value)).stringValue }
        func money(_ name: String, _ value: Decimal) -> String { c(name, amount(value), attributes: " currencyID=\"EUR\"") }
        func party(_ person: ElectronicParty, sender: Bool) -> String {
            let registration = person.legalRegistrationID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let legalID = sender && !registration.isEmpty ? c("CompanyID", registration) : ""
            let identifier = person.sellerIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let partyID = sender && !identifier.isEmpty ? "<cac:PartyIdentification>\(c("ID", identifier))</cac:PartyIdentification>" : ""
            let legal = "<cac:PartyLegalEntity>\(c("RegistrationName", person.name))\(legalID)</cac:PartyLegalEntity>"
            let tax = [(person.vatID, "VAT"), (person.taxNumber, "FC")].filter { !$0.0.isEmpty }.map {
                "<cac:PartyTaxScheme>\(c("CompanyID", $0.0))<cac:TaxScheme>\(c("ID", $0.1))</cac:TaxScheme></cac:PartyTaxScheme>"
            }.joined()
            let contact = sender ? "<cac:Contact>\(c("Name", person.contact))\(c("Telephone", person.phone))\(c("ElectronicMail", person.email))</cac:Contact>" : ""
            return """
            <cac:Party>
            \(c("EndpointID", person.endpoint, attributes: " schemeID=\"\(escape(person.endpointScheme))\""))
            \(partyID)
            <cac:PostalAddress>\(c("StreetName",person.street))\(c("CityName",person.city))\(c("PostalZone",person.postcode))<cac:Country>\(c("IdentificationCode",person.country.uppercased()))</cac:Country></cac:PostalAddress>
            \(tax)\(legal)\(contact)
            </cac:Party>
            """
        }
        let correction = invoice.correctionOf != nil
        let root = correction ? "CreditNote" : "Invoice"
        let line = correction ? "CreditNoteLine" : "InvoiceLine"
        let qty = correction ? "CreditedQuantity" : "InvoicedQuantity"
        let type = c(correction ? "CreditNoteTypeCode" : "InvoiceTypeCode", correction ? "381" : "380")
        let due = !correction ? invoice.dueDate.map { c("DueDate", date($0)) } ?? "" : ""
        let preceding = precedingNumber.map { "<cac:BillingReference><cac:InvoiceDocumentReference>\(c("ID",$0))</cac:InvoiceDocumentReference></cac:BillingReference>" } ?? ""
        let reason = invoice.correctionReason.map { c("Note",$0) } ?? ""
        let payment = """
        <cac:PaymentMeans>\(c("PaymentMeansCode","58"))\(c("PaymentID",invoice.number))
        <cac:PayeeFinancialAccount>\(c("ID",iban.replacingOccurrences(of: " ", with: "")))</cac:PayeeFinancialAccount></cac:PaymentMeans>
        <cac:PaymentTerms>\(c("Note",invoice.paymentTerms.isEmpty ? "Bank transfer" : InlineText.runs(invoice.paymentTerms).map(\.text).joined()))</cac:PaymentTerms>
        """
        let taxCode = invoice.vatRate == 0 ? "E" : "S"
        let taxBody = c("ID",taxCode) + c("Percent",amount(invoice.vatRate))
        let scheme = "<cac:TaxScheme>\(c("ID","VAT"))</cac:TaxScheme>"
        let exempt = invoice.vatRate == 0 ? c("TaxExemptionReason",exemption) : ""
        let period = "<cac:InvoicePeriod>\(c("StartDate",date(serviceStart)))\(c("EndDate",date(serviceEnd)))</cac:InvoicePeriod>"
        let order = invoice.purchaseOrder.flatMap { reference in
            reference.isEmpty ? nil : "<cac:OrderReference>" + c("ID", reference) + "</cac:OrderReference>"
        } ?? ""
        let positions = invoice.positions.enumerated().map { index, position in
            """
        <cac:\(line)>\(c("ID",String(index + 1)))\(c(qty,"1",attributes:" unitCode=\"C62\""))\(money("LineExtensionAmount",position.amount))
          <cac:Item>\(c("Name",position.name))
            <cac:ClassifiedTaxCategory>\(taxBody)\(scheme)</cac:ClassifiedTaxCategory>
          </cac:Item><cac:Price>\(money("PriceAmount",position.amount))</cac:Price>
        </cac:\(line)>
        """
        }.joined(separator: "\n")
        let data = """
        <?xml version="1.0" encoding="UTF-8"?>
        <\(root) xmlns="urn:oasis:names:specification:ubl:schema:xsd:\(root)-2"
          xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
          xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
        \(c("CustomizationID","urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0"))
        \(c("ProfileID","urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"))
        \(c("ID",invoice.number))\(c("IssueDate",date(invoice.issueDate)))\(due)\(type)\(reason)
        \(c("DocumentCurrencyCode","EUR"))\(c("BuyerReference",buyerReference))\(period)\(order)\(preceding)
        <cac:AccountingSupplierParty>\(party(seller,sender:true))</cac:AccountingSupplierParty>
        <cac:AccountingCustomerParty>\(party(buyer,sender:false))</cac:AccountingCustomerParty>
        \(payment)
        <cac:TaxTotal>\(money("TaxAmount",invoice.vat))
          <cac:TaxSubtotal>\(money("TaxableAmount",invoice.net))\(money("TaxAmount",invoice.vat))
          <cac:TaxCategory>\(taxBody)\(exempt)\(scheme)</cac:TaxCategory></cac:TaxSubtotal>
        </cac:TaxTotal>
        <cac:LegalMonetaryTotal>\(money("LineExtensionAmount",invoice.net))\(money("TaxExclusiveAmount",invoice.net))
          \(money("TaxInclusiveAmount",invoice.gross))\(money("PayableAmount",invoice.gross))</cac:LegalMonetaryTotal>
        \(positions)
        </\(root)>
        """
        return Data(data.utf8)
    }
}

struct XRechnungValidator {
    let java: URL
    let jar: URL
    let scenarios: URL

    static var installed: Self {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Coool PM/XRechnung")
        func configured(_ key: String, fallback: String) -> URL {
            guard let path = VaultPreferences.text(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else { return base.appendingPathComponent(fallback) }
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return Self(java: configured("xrechnungJavaPath", fallback: "java/bin/java"),
                    jar: configured("xrechnungValidatorPath", fallback: "validator.jar"),
                    scenarios: configured("xrechnungRulesPath", fallback: "rules/scenarios.xml"))
    }

    var available: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: java.path) && fm.fileExists(atPath: jar.path) && fm.fileExists(atPath: scenarios.path)
    }

    func validate(_ xml: Data) throws -> Data {
        let fm = FileManager.default
        guard available else {
            throw LibraryError(description: "Check the Java executable, KoSIT validator JAR and rules file in Settings → XRechnung.")
        }
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        let document = temp.appendingPathComponent("invoice.xml")
        try xml.write(to: document)
        let task = Process()
        task.currentDirectoryURL = temp
        task.executableURL = java
        task.arguments = ["-jar", jar.path, "-s", scenarios.path, "-r", scenarios.deletingLastPathComponent().path, document.path]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let log = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let reportURL = temp.appendingPathComponent("invoice-report.xml")
        guard let report = try? Data(contentsOf: reportURL),
              let parsed = try? XMLDocument(data: report, options: [.nodeLoadExternalEntitiesNever]) else {
            throw LibraryError(description: "KoSIT did not produce a report. " + String(decoding: log.suffix(600), as: UTF8.self))
        }
        let decision = try parsed.nodes(forXPath: "//*[local-name()='accept' or local-name()='reject']")
        guard task.terminationStatus == 0, let result = decision.last, result.localName == "accept" else {
            let failures = try parsed.nodes(forXPath: "//*[local-name()='message' and @level='error']").compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            throw LibraryError(description: (["KoSIT rejected the XRechnung."] + failures.prefix(5)).joined(separator: "\n"))
        }
        return report
    }
}

