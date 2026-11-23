import AppKit

// Keep the original Office package and replace only paragraphs containing merge fields.
struct WordTemplate {
    let document: ClientDocument
    var key: String { (document.invoice ? "invoice" : "proposal") + (document.german ? "-de" : "-en") }
    var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Coool PM/Templates", isDirectory: true)
    }
    var url: URL { folder.appendingPathComponent(key + ".docx") }
    var installed: Bool { FileManager.default.fileExists(atPath: url.path) }

    func starter() throws -> Data {
        var letter = LetterLayout(invoice: document.invoice, footer: ["{{business}}", "{{contact}}", "{{bank}}"], font: document.font, logo: document.logo)
        letter.letterhead(identity: "{{business}}", contact: "{{contact}}")
        letter.add("{{client}}\n{{client_contact}}\n{{address}}", after: 24)
        letter.add("{{date}}", right: true)
        letter.add("{{document_title}} {{number}} – {{project}}", bold: true, after: 12)
        letter.add(document.label("Leistungszeitraum", "Service period") + "   {{period}}")
        if document.invoice { letter.add("{{purchase_order}}") }
        letter.add("{{scope}}", after: 16)
        if document.invoice { letter.add("{{invoice_positions}}") }
        if !document.invoice {
            letter.breakPage()
            letter.add(document.label("Honorarübersicht", "Fee summary"), bold: true, band: true)
            letter.add("{{phase}}\t{{phase_fee}}")
        }
        letter.add(document.label("Nettobetrag", "Net amount") + "\t{{net}}")
        letter.add(document.label("Umsatzsteuer", "VAT") + " ({{vat_rate}}%)\t{{vat}}")
        if document.invoice { letter.add("{{vat_exemption}}") }
        letter.add(document.label("Gesamtbetrag", "Total") + "\t{{total}}", bold: true, after: 12)
        letter.add(document.label("Zahlungsbedingungen", "Payment terms") + "   {{payment}}")
        if document.invoice { letter.add("{{tax_number}}\n{{vat_id}}\n{{bank}}") }
        if !document.invoice {
            letter.add("{{options}}")
            letter.add("{{terms}}")
        }
        return try letter.wordData()
    }

    func fields(project: String, client: Client?, fees: [PhaseFee]) -> [String: String] {
        let net = fees.reduce(Decimal.zero) { $0 + $1.amount }
        var raw = net * document.vat / 100
        var vat = Decimal.zero
        NSDecimalRound(&vat, &raw, 2, .plain)
        let po = document.purchaseOrder.flatMap { $0.isEmpty ? nil : document.label("Auftragsnummer", "Purchase order") + "  " + $0 } ?? ""
        let service = net - document.reimbursedCosts.reduce(0) { $0 + $1.amount }
        var positions = [String]()
        if !document.reimbursedCosts.isEmpty {
            if service != 0 { positions.append(document.label("Projekthonorar", "Project fee") + " · " + money(service)) }
            positions += document.reimbursedCosts.map { $0.title + " · " + money($0.amount) }
        }
        return ["purchase_order": po, "invoice_positions": positions.joined(separator: "\n"), "document_title": document.title, "milestone": document.milestoneText, "business": document.sender, "contact": document.contactDetails, "bank": document.bankDetails,
                "tax_number": document.taxNumber, "vat_id": document.vatID, "city": document.city,
                "project": project, "number": document.reference, "scope": document.invoice ? document.invoiceIntroduction : document.scope,
                "date": document.date.formatted(.dateTime.day().month(.wide).year().locale(document.locale)),
                "client": client?.name ?? "", "client_contact": client?.contact ?? "", "client_number": client?.number ?? "",
                "address": client?.address ?? "", "period": document.servicePeriod,
                "options": document.optionalFees.isEmpty ? "" : ([document.label("Optionale Leistungen", "Optional scope")] + document.optionalFees.map { $0.name + " · " + money($0.amount) } + [document.label("Gesamtnetto inkl. Optionen", "Total net including options") + " · " + money(net + document.optionalFees.reduce(0) { $0 + $1.amount })]).joined(separator: "\n"),
                "vat_exemption": document.exemptionReason, "payment": document.paymentText(client), "terms": document.invoice ? "" : document.resolvedTerms(client), "day_rates": document.rateTerms?.text(document) ?? document.label("Gemäß Angebot.", "As agreed in the proposal."),
                "net": money(net), "vat": money(vat), "vat_rate": document.vat.formatted(.number.locale(document.locale)), "total": money(net + vat)]
    }
    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: "EUR").locale(document.locale)) }

    private func run(_ executable: String, _ args: [String], at folder: URL) throws -> Data {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = folder
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LibraryError(description: "Could not read the Word template. Export it as a .docx document and try again.") }
        return data
    }

    func render(source: URL, project: String, client: Client?, fees: [PhaseFee]) throws -> Data {
        let fm = FileManager.default, work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent("template.docx")
        try fm.copyItem(at: source, to: archive)
        let listing = try run("/usr/bin/unzip", ["-Z1", archive.path], at: work)
        let parts = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init).filter {
            $0.range(of: #"^word/(document|header[0-9]+|footer[0-9]+)\.xml$"#, options: .regularExpression) != nil
        }
        guard parts.contains("word/document.xml") else { throw LibraryError(description: "Choose a Word (.docx) document.") }
        let values = fields(project: project, client: client, fees: fees)
        let marker = try NSRegularExpression(pattern: #"\{\{([a-zA-Z_0-9]+)\}\}"#)
        var found = false
        for part in parts {
            let bytes = try run("/usr/bin/unzip", ["-p", archive.path, part], at: work)
            let xml = try XMLDocument(data: bytes, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
            let paragraphs = try xml.nodes(forXPath: "//*[local-name()='p']")
            // Older custom templates predate these two invoice fields.
            if document.invoice, part == "word/document.xml",
               let body = try xml.nodes(forXPath: "//*[local-name()='body']").first as? XMLElement {
                let markers = try paragraphs.map { paragraph in
                    try paragraph.nodes(forXPath: ".//*[local-name()='t']").compactMap(\.stringValue).joined()
                }
                let totals = zip(paragraphs, markers).first { $0.1.contains("{{net}}") }?.0
                var anchor = totals
                while let parent = anchor?.parent, parent !== body { anchor = parent }
                let section = try body.nodes(forXPath: "./*[local-name()='sectPr']").first
                var index = anchor?.index ?? section?.index ?? (body.children?.count ?? 0)
                for key in ["purchase_order", "invoice_positions"] where !markers.contains(where: { $0.contains("{{" + key + "}}") }) {
                    guard let value = values[key], !value.isEmpty else { continue }
                    for text in value.components(separatedBy: .newlines) {
                        let paragraph = XMLElement(name: "w:p", uri: body.uri)
                        let run = XMLElement(name: "w:r", uri: body.uri)
                        let content = XMLElement(name: "w:t", uri: body.uri)
                        content.stringValue = text
                        run.addChild(content); paragraph.addChild(run)
                        body.insertChild(paragraph, at: index)
                        index += 1
                    }
                }
            }
            var repeats = Set<ObjectIdentifier>()
            for paragraph in paragraphs {
                let nodes = try paragraph.nodes(forXPath: ".//*[local-name()='t']")
                let combined = nodes.compactMap(\.stringValue).joined()
                if document.invoice, combined == document.label("Rechnung", "Invoice") + " {{number}} – {{project}}" {
                    let literal = document.label("Rechnung", "Invoice")
                    let legacyTitle = try NSRegularExpression(pattern: "^(" + literal + ")")
                    _ = try replace(in: paragraph, values: [literal: "{{document_title}}"], marker: legacyTitle)
                }
                if part == "word/document.xml", combined.trimmingCharacters(in: .whitespacesAndNewlines) == "{{terms}}",
                   let element = paragraph as? XMLElement {
                    if values["terms", default: ""].isEmpty {
                        // Retain the paragraph in table cells to preserve the Word schema.
                        if element.parent?.localName == "body" { element.detach() }
                    } else {
                        let properties = try element.nodes(forXPath: "./*[local-name()='pPr']").first as? XMLElement ?? XMLElement(name: "w:pPr", uri: element.uri)
                        if properties.parent == nil { element.insertChild(properties, at: 0) }
                        if try properties.nodes(forXPath: "./*[local-name()='pageBreakBefore']").isEmpty {
                            properties.insertChild(XMLElement(name: "w:pageBreakBefore", uri: element.uri), at: 0)
                        }
                    }
                    found = true
                }
                if ["{{phase}}","{{phase_fee}}","{{phase_items}}"].contains(where: combined.contains) {
                    let unit = try paragraph.nodes(forXPath: "ancestor::*[local-name()='tr'][1]").first ?? paragraph
                    guard repeats.insert(ObjectIdentifier(unit)).inserted, let parent = unit.parent as? XMLElement else { continue }
                    var index = unit.index
                    let prototype = unit.xmlString
                    var bindings: [String: String] = [:]
                    var ancestor: XMLNode? = unit
                    while let element = ancestor as? XMLElement {
                        for ns in element.namespaces ?? [] {
                            if let name = ns.name, bindings[name] == nil { bindings[name] = ns.xmlString }
                        }
                        ancestor = element.parent
                    }
                    let wrapper = "<root " + bindings.values.joined(separator: " ") + ">" + prototype + "</root>"
                    for fee in document.invoice ? [] : fees {
                        let copy = try XMLDocument(xmlString: wrapper, options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever])
                        guard let clone = copy.rootElement()?.children?.first else { throw CocoaError(.fileReadCorruptFile) }
                        var row = values
                        row["phase"] = fee.name
                        row["phase_fee"] = money(fee.amount)
                        row["phase_items"] = document.showItems ? fee.items.joined(separator: "\n") : ""
                        let targets = clone.localName == "p" ? [clone] : try clone.nodes(forXPath: ".//*[local-name()='p']")
                        for target in targets { _ = try replace(in: target, values: row, marker: marker) }
                        clone.detach()
                        parent.insertChild(clone, at: index)
                        index += 1
                    }
                    unit.detach()
                    found = true
                }
            }
            // Query again after expansion, skipping cloned values to avoid interpreting client text as fields.
            for paragraph in paragraphs where paragraph.rootDocument != nil {
                if try replace(in: paragraph, values: values, marker: marker) { found = true }
            }
            try expandInlineStyles(in: xml)
            let output = work.appendingPathComponent(part)
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try xml.xmlData(options: [.nodePreserveAll]).write(to: output)
        }
        guard found else { throw LibraryError(description: "Add a merge field such as {{project}} to your document before importing it.") }
        _ = try run("/usr/bin/zip", ["-q", archive.path] + parts, at: work)
        return try Data(contentsOf: archive)
    }

    private func expandInlineStyles(in xml: XMLDocument) throws {
        for run in try xml.nodes(forXPath: "//*[local-name()='r']") {
            guard let parent = run.parent as? XMLElement, let children = run.children,
                  children.contains(where: { $0.localName == "t" && ($0.stringValue ?? "").contains(InlineText.marker) }) else { continue }
            let base = children.first { $0.localName == "rPr" }
            let ns = run.uri
            let prefix = run.prefix.map { $0 + ":" } ?? ""
            var index = run.index, mask = 0
            func emit(_ child: XMLNode, style: Int) {
                let newRun = XMLElement(name: prefix + "r", uri: ns)
                let props = (base?.copy() as? XMLElement) ?? XMLElement(name: prefix + "rPr", uri: ns)
                for (bit, tag) in [(1,"b"),(2,"i"),(4,"u")] where style & bit != 0 {
                    for old in props.children ?? [] where old.localName == tag { old.detach() }
                    let flag = XMLElement(name: prefix + tag, uri: ns)
                    if bit == 4 { flag.addAttribute(XMLNode.attribute(withName: prefix + "val", uri: ns ?? "http://schemas.openxmlformats.org/wordprocessingml/2006/main", stringValue: "single") as! XMLNode) }
                    props.addChild(flag)
                }
                newRun.addChild(props)
                newRun.addChild(child)
                parent.insertChild(newRun, at: index)
                index += 1
            }
            for child in children where child.localName != "rPr" {
                guard child.localName == "t" else { emit(child.copy() as! XMLNode, style: mask); continue }
                let value = child.stringValue ?? ""
                let spans = InlineText.runs(InlineText.marker + String(mask) + value + " ")
                for (i, span) in spans.enumerated() {
                    mask = span.mask
                    let text = i == spans.count - 1 ? String(span.text.dropLast()) : span.text
                    guard !text.isEmpty else { continue }
                    let copy = child.copy() as! XMLNode
                    copy.stringValue = text
                    emit(copy, style: mask)
                }
            }
            run.detach()
        }
    }

    // Replace backwards so original UTF-16 offsets stay valid even when Word splits a field across styled runs.
    private func replace(in paragraph: XMLNode, values: [String: String], marker: NSRegularExpression) throws -> Bool {
        let nodes = try paragraph.nodes(forXPath: ".//*[local-name()='t']")
        var ranges = [NSRange](), combined = ""
        for node in nodes {
            let value = node.stringValue ?? ""
            ranges.append(NSRange(location: (combined as NSString).length, length: (value as NSString).length))
            combined += value
        }
        let source = combined as NSString
        let matches = marker.matches(in: combined, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            let key = source.substring(with: match.range(at: 1))
            guard let value = values[key] else { throw LibraryError(description: "Unknown template field {{\(key)}}.") }
            for (index, range) in ranges.enumerated() {
                let overlap = NSIntersectionRange(range, match.range)
                guard overlap.length > 0 else { continue }
                let old = (nodes[index].stringValue ?? "") as NSString
                nodes[index].stringValue = old.replacingCharacters(in: NSRange(location: overlap.location-range.location, length: overlap.length), with: overlap.location == match.range.location ? value : "")
            }
        }
        for node in nodes where node.stringValue?.contains("\n") == true {
            guard let parent = node.parent as? XMLElement else { continue }
            let lines = node.stringValue!.components(separatedBy: "\n")
            node.stringValue = lines[0]
            var index = node.index + 1
            for line in lines.dropFirst() {
                let br = XMLElement(name: (node.prefix.map { $0 + ":" } ?? "") + "br", uri: node.uri)
                parent.insertChild(br, at: index)
                let copy = node.copy() as! XMLNode
                copy.stringValue = line
                parent.insertChild(copy, at: index + 1)
                index += 2
            }
        }
        return !matches.isEmpty
    }
}

extension WordTemplate {
    func pdf(from data: Data) throws -> Data {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let input = folder.appendingPathComponent("Document.docx")
        let output = folder.appendingPathComponent("Document.pdf")
        try data.write(to: input)
        let script = """
        on run argv
            set inputFile to POSIX file (item 1 of argv)
            set outputFile to POSIX file (item 2 of argv)
            tell application id "com.apple.iWork.Pages"
                set importedDoc to open inputFile
                try
                    export importedDoc to outputFile as PDF
                on error msg
                    close importedDoc saving no
                    error msg
                end try
                close importedDoc saving no
            end tell
        end run
        """
        // Resolve the installed edition before asking macOS to automate it.
        let bundle = ["com.apple.Pages", "com.apple.iWork.Pages"].first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        guard let bundle else { throw LibraryError(description: "PDF export with an imported template requires Pages. You can also export DOCX and save it as PDF in Word.") }
        do {
            _ = try run("/usr/bin/osascript", ["-e", script.replacingOccurrences(of: "com.apple.iWork.Pages", with: bundle), input.path, output.path], at: folder)
            return try Data(contentsOf: output)
        } catch { throw LibraryError(description: "Pages could not export the PDF. Check macOS Automation permission for Pages, or export DOCX and save as PDF in Word or Pages.") }
    }
}
