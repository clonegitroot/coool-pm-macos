import SwiftUI
import UniformTypeIdentifiers

struct XRechnungEditor: View {
    @State private var document: XRechnung
    let saveArtifacts: (InvoiceArtifact, InvoiceArtifact) -> Void
    @State private var error: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    init(invoice: IssuedInvoice, precedingNumber: String?, buyerDefaults: ElectronicRecipientDefaults? = nil,
         saveArtifacts: @escaping (InvoiceArtifact, InvoiceArtifact) -> Void) {
        _document = State(initialValue: XRechnung(invoice: invoice, precedingNumber: precedingNumber,
                                                  sellerDefaults: BusinessProfile.load().electronicInvoice,
                                                  buyerDefaults: buyerDefaults))
        self.saveArtifacts = saveArtifacts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("XRechnung").font(.title2.bold())
            ScrollView {
                Form {
                    Section("Seller") {
                        ElectronicPartyFields(party: $document.seller, seller: true)
                        TextField("Tax number", text: $document.seller.taxNumber)
                        TextField("VAT ID", text: $document.seller.vatID)
                    }
                    Section("Buyer") {
                        ElectronicPartyFields(party: $document.buyer, seller: false)
                    }
                    Section("Invoice details") {
                        TextField("Buyer reference / Leitweg-ID", text: $document.buyerReference)
                            .help("Use the reference the buyer gave you for electronic invoices.")
                        TextField("IBAN", text: $document.iban)
                        DatePicker("Service from", selection: $document.serviceStart, displayedComponents: .date)
                        DatePicker("Service until", selection: $document.serviceEnd, displayedComponents: .date)
                        if document.invoice.vatRate == 0 { TextField("VAT exemption reason", text: $document.exemption) }
                    }
                }.formStyle(.grouped)
            }
            if let first = document.missingFields.first {
                Label(LocalizedStringKey(first), systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !XRechnungValidator.installed.available {
                Text("Check the Java executable, KoSIT validator JAR and rules file in Settings → XRechnung.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Close") { dismiss() }.disabled(busy)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Validate and save…", action: export).keyboardShortcut(.defaultAction)
                    .disabled(busy || !document.missingFields.isEmpty || !XRechnungValidator.installed.available)
            }
        }.padding(20).frame(width: 570, height: 640)
    }

    private func export() {
        busy = true
        error = nil
        let snapshot = document
        Task {
            do {
                let (xml, report) = try await Task.detached(priority: .userInitiated) {
                    let xml = try snapshot.xml()
                    return (xml, try XRechnungValidator.installed.validate(xml))
                }.value
                let stem = snapshot.invoice.number.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted).joined(separator: "-")
                let name = stem + "-XRechnung.xml"
                let panel = NSSavePanel()
                panel.nameFieldStringValue = name
                panel.allowedContentTypes = [.xml]
                if panel.runModal() == .OK, let url = panel.url {
                    try xml.write(to: url, options: .atomic)
                    saveArtifacts(InvoiceArtifact(filename: name, data: xml), InvoiceArtifact(filename: stem + "-KoSIT-report.xml", data: report))
                    dismiss()
                }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct ElectronicPartyFields: View {
    @Binding var party: ElectronicParty
    let seller: Bool
    var includeName = true

    var body: some View {
        if includeName { TextField("Name", text: $party.name) }
        TextField("Street", text: $party.street)
        TextField("Postcode", text: $party.postcode)
        TextField("City", text: $party.city)
        TextField("Country code", text: $party.country)
            .help("Use a two-letter country code such as DE or AT.")
        TextField("Electronic address", text: $party.endpoint)
            .help("Enter the electronic invoice endpoint. This can be different from the contact email.")
        TextField("Electronic address scheme", text: $party.endpointScheme)
            .help("Use the scheme that matches the electronic address. For example, use EM for an email endpoint in XRechnung.")
        if seller {
            TextField("Seller identifier (BT-29)", text: optional(\.sellerIdentifier))
                .help("Use the supplier identifier agreed with the buyer if you don’t use a VAT ID or legal registration ID.")
            TextField("Legal registration ID (BT-30)", text: optional(\.legalRegistrationID))
            TextField("Contact name", text: $party.contact)
            TextField("Phone", text: $party.phone)
            TextField("Contact email", text: $party.email)
        }
    }

    private func optional(_ field: WritableKeyPath<ElectronicParty, String?>) -> Binding<String> {
        Binding(get: { party[keyPath: field] ?? "" }, set: { party[keyPath: field] = $0.isEmpty ? nil : $0 })
    }
}
