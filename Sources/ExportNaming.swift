import Foundation

struct ExportNaming {
    let version: Int
    let filename: String

    init(date: Date, invoice: Bool, reference: String, project: String, invoiceName: String,
         milestone: BillingMilestone?, schedule: BillingSchedule?, history: [ExportedDocument],
         pdf: Bool, previousVersion: Int = 0, timeZone: TimeZone = .current) {
        let latest = Self.latestVersion(in: history, invoice: invoice, milestoneID: milestone?.id)
        version = max(latest, previousVersion) + 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year,.month,.day], from: date)
        let stamp = String(format: "%02d%02d%02d", parts.year! % 100, parts.month!, parts.day!)
        let name = [reference, invoice ? invoiceName : "", project].map(Self.component).first { !$0.isEmpty }
        var tokens = [stamp, invoice ? "RE" : "AN", name ?? (invoice ? "Invoice" : "Proposal")]
        if invoice, let milestone, let index = schedule?.stages.firstIndex(where: { $0.id == milestone.id }) {
            tokens.append(String(format: "TR%02ld", index + 1))
        }
        tokens.append(String(format: "v%02ld", version))
        filename = tokens.joined(separator: "_") + (pdf ? ".pdf" : ".docx")
    }

    static func latestVersion(in history: [ExportedDocument], invoice: Bool, milestoneID: UUID?) -> Int {
        let series = history.filter { $0.proposal == !invoice && (!invoice || $0.milestoneID == milestoneID) }
        var latest = 0
        for record in series {
            if let saved = record.exportVersion {
                latest = max(latest, saved)
            } else {
                // Earlier releases saved the chosen filename, without separate revision metadata.
                let stem = (record.filename as NSString).deletingPathExtension
                let suffix = stem.range(of: #"_v[0-9]{2,8}$"#, options: .regularExpression)
                let numbered = suffix.flatMap { Int(stem[$0].dropFirst(2)) } ?? 0
                latest = max(latest + 1, numbered)
            }
        }
        return latest
    }

    private static func component(_ raw: String) -> String {
        let words = raw.precomposedStringWithCanonicalMapping.components(separatedBy: CharacterSet.alphanumerics.union(.nonBaseCharacters).inverted)
        let cleaned = words.filter { !$0.isEmpty }.joined(separator: "-")
        var result = ""
        for char in cleaned {
            if result.utf8.count + String(char).utf8.count > 170 { break }
            result.append(char)
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Estimate {
    func seriesKey(invoice: Bool, milestoneID: UUID?) -> String {
        invoice ? milestoneID?.uuidString ?? "invoice" : "proposal"
    }

    mutating func discardDraft(_ id: UUID) {
        guard let document = documents?.first(where: { $0.id == id }), document.id != acceptedProposalID,
              document.sentOn == nil, document.acceptedOn == nil,
              !(issuedInvoices ?? []).contains(where: { $0.sourceFileID == id }) else { return }
        let key = seriesKey(invoice: !document.proposal, milestoneID: document.milestoneID)
        let latest = ExportNaming.latestVersion(in: documents ?? [], invoice: !document.proposal, milestoneID: document.milestoneID)
        var history = discardedExportVersions ?? [:]
        history[key] = max(history[key] ?? 0, latest)
        discardedExportVersions = history
        documents?.removeAll { $0.id == id }
    }
}
