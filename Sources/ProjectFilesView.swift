import SwiftUI
import AppKit
import QuickLook
import UniformTypeIdentifiers

struct ProjectFilesView: View {
    enum Area { case documents, billing }

    @Environment(\.locale) private var locale
    @Binding var estimate: Estimate
    var area: Area = .documents
    var saveDocuments: ((Estimate) throws -> Void)?
    let createDocument: () -> Void

    @State private var importKind: ProjectFile.Kind = .sent
    @State private var importing = false
    @State private var proposalForAcceptance: ProjectFile?
    @State private var discardCandidate: ExportedDocument?
    @State private var exportedApproval: ExportedDocument?
    @State private var bookingFile: ProjectFile?
    @State private var previewURL: URL?
    @State private var previewFolder: URL?
    @State private var error: String?
    @State private var importNote: String?

    private var proposals: [ExportedDocument] {
        (estimate.documents ?? []).filter(\.proposal).reversed()
    }

    private var importedProposals: [ProjectFile] {
        (estimate.files ?? []).filter { $0.kind == .proposal }.reversed()
    }

    private var invoices: [ExportedDocument] {
        let recorded = Set((estimate.issuedInvoices ?? []).compactMap(\.sourceFileID))
        return (estimate.documents ?? []).filter { !$0.proposal && !recorded.contains($0.id) }.reversed()
    }

    private var sentFiles: [ProjectFile] {
        let recorded = Set((estimate.issuedInvoices ?? []).compactMap(\.sourceFileID))
        return (estimate.files ?? []).filter { $0.kind == .sent && !recorded.contains($0.id) }.reversed()
    }

    private var supplierFiles: [ProjectFile] {
        (estimate.files ?? []).filter { $0.kind == .supplier }.reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if area == .billing {
                GroupBox {
                    VStack(spacing: 0) {
                        if invoices.isEmpty && sentFiles.isEmpty {
                            empty("Draft exports and unrecorded client invoices appear here.")
                        }
                        ForEach(invoices) { exportRow($0) }
                        ForEach(sentFiles) { importedRow($0) }
                    }
                } label: {
                    HStack {
                        Text("Invoice drafts and files")
                        Spacer()
                        Button("Import sent invoice…", systemImage: "tray.and.arrow.down") { startImport(.sent) }
                    }
                }
            } else {
                HStack {
                    Button("Create proposal…", systemImage: "square.and.pencil", action: createDocument)
                    Spacer()
                    Button("Import sent proposal…", systemImage: "tray.and.arrow.down") { startImport(.proposal) }
                    Button("Import supplier invoice…", systemImage: "tray.and.arrow.down") { startImport(.supplier) }
                }
                GroupBox("Proposals") {
                    VStack(spacing: 0) {
                        if proposals.isEmpty && importedProposals.isEmpty {
                            empty("Export a proposal or import a copy you already sent.")
                        }
                        ForEach(proposals) { exportRow($0) }
                        ForEach(importedProposals) { importedRow($0) }
                    }
                }
                GroupBox("Supplier invoices") {
                    VStack(spacing: 0) {
                        if supplierFiles.isEmpty {
                            empty("Import a supplier invoice to book its net cost to this project.")
                        }
                        ForEach(supplierFiles) { importedRow($0) }
                    }
                }
            }
            if let importNote { Text(importNote).font(.caption).foregroundStyle(.secondary) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .xml, .spreadsheet, .plainText, UTType(filenameExtension: "docx") ?? .data], allowsMultipleSelection: true) { result in
            perform { try addFiles(result.get()) }
        }
        .sheet(item: $proposalForAcceptance) { file in
            ImportedProposalEditor(filename: file.name, net: file.proposalNet) { net in
                try estimate.acceptImportedProposal(file.id, net: net)
            }.environment(\.locale, locale)
        }
        .sheet(item: $bookingFile) { file in
            SupplierBookingEditor(booking: file.booking ?? SupplierBooking(), filename: file.name,
                                  phases: estimate.controlPhases,
                                  privateCosts: (estimate.externalCosts ?? []).filter { cost in
                                      !estimate.invoicedCostIDs.contains(cost.id) && (cost.id == file.booking?.externalCostID ||
                                          !estimate.linkedExternalCostIDs.contains(cost.id))
                                  }) { booking in
                try estimate.book(booking, fileID: file.id)
            }.environment(\.locale, locale)
        }
        .confirmationDialog("Approve this proposal and lock the calculation?", isPresented: Binding(
            get: { exportedApproval != nil }, set: { if !$0 { exportedApproval = nil } }
        ), titleVisibility: .visible, presenting: exportedApproval) { proposal in
            Button("Approve proposal") { estimate.acceptProposal(proposal.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The approved proposal fixes the base fee and scope. Use change orders for any adjustments.")
        }
        .confirmationDialog("Discard this draft?", isPresented: Binding(get: { discardCandidate != nil }, set: { if !$0 { discardCandidate = nil } }), presenting: discardCandidate) { draft in
            Button("Discard draft", role: .destructive) { estimate.discardDraft(draft.id) }
        } message: { _ in
            Text("This removes the draft from the project. Your exported copy stays on disk.")
        }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { _, current in
            if current == nil { clearPreview() }
        }
        .onDisappear(perform: clearPreview)
        .alert("Document action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func empty(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
    }

    private func exportRow(_ document: ExportedDocument) -> some View {
        let accepted = document.proposal ? estimate.acceptedProposalID == document.id : document.acceptedOn != nil
        let status = accepted ? "Accepted" : (document.sentOn == nil ? (document.proposal ? "Not sent" : "Exported") : "Sent")
        return HStack(spacing: 12) {
            fileLabel(document.filename, detail: document.date.formatted(date: .abbreviated, time: .omitted))
            Text(LocalizedStringKey(status)).foregroundStyle(accepted ? Color.green : Color.secondary).font(.caption)
            if document.proposal {
                if document.sentOn == nil && !accepted {
                    Button("Mark sent") { estimate.setProposalSent(document.id, isSent: true) }
                }
                if !estimate.calculationLocked {
                    Button("Mark accepted") { exportedApproval = document }
                        .help("Approving a proposal locks the calculation. Later adjustments use change orders.")
                }
            } else {
                if document.sentOn == nil {
                    Button("Mark sent") { updateExport(document.id) { $0.sentOn = .now } }
                }
                Button(accepted ? "Undo acceptance" : "Mark accepted") {
                    updateExport(document.id) {
                        $0.acceptedOn = accepted ? nil : .now
                        if !accepted && $0.sentOn == nil { $0.sentOn = .now }
                    }
                }
            }
            fileMenu(data: document.data, name: document.filename) {
                if !accepted && document.sentOn == nil {
                    Button("Discard draft…", role: .destructive) { discardCandidate = document }
                }
                if document.sentOn != nil && !accepted {
                    Button("Clear sent status") {
                        if document.proposal { estimate.setProposalSent(document.id, isSent: false) }
                        else { updateExport(document.id) { $0.sentOn = nil } }
                    }
                }
            }
        }.padding(8)
    }

    private func importedRow(_ file: ProjectFile) -> some View {
        let booking = file.booking
        let phase = estimate.controlPhases.first { $0.id == booking?.phaseID }?.displayName(in: locale)
        let detail = booking.map { value in
            let date = value.invoiceDate?.formatted(.dateTime.year().month(.abbreviated).day().locale(locale))
            return [value.supplier, value.reference, date ?? "", phase ?? AppLanguage.text("Whole project", fallback: "Whole project", locale: locale),
                    value.amount.formatted(.currency(code: "EUR").locale(locale))]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return HStack(spacing: 12) {
            fileLabel(file.name, detail: detail ?? file.proposalNet?.formatted(.currency(code: "EUR")))
            if file.kind == .proposal {
                let accepted = estimate.acceptedProposalID == file.id
                Text(accepted ? "Accepted" : (file.markedUnsent == true ? "Not sent" : "Sent"))
                    .font(.caption).foregroundStyle(accepted ? Color.green : Color.secondary)
                if file.markedUnsent == true && !accepted {
                    Button("Mark sent") { estimate.setProposalSent(file.id, isSent: true) }
                }
                if !estimate.calculationLocked {
                    Button("Mark accepted") { proposalForAcceptance = file }
                        .help("Approving a proposal locks the calculation. Later adjustments use change orders.")
                }
            } else if file.kind == .supplier {
                Text(booking == nil ? "Unbooked" : "Booked").font(.caption).foregroundStyle(.secondary)
                Button(booking == nil ? "Book cost…" : "Edit booking…") { bookingFile = file }
                    .disabled(estimate.invoicedCostIDs.contains(booking?.externalCostID ?? file.id))
            } else {
                let accepted = file.accepted != nil
                Text(accepted ? "Accepted" : "Sent").font(.caption).foregroundStyle(accepted ? Color.green : Color.secondary)
                Button(accepted ? "Undo acceptance" : "Mark accepted") {
                    guard let index = estimate.files?.firstIndex(where: { $0.id == file.id }) else { return }
                    estimate.files?[index].accepted = accepted ? nil : .now
                }
            }
            fileMenu(data: file.data, name: file.name) {
                if file.kind == .proposal && file.markedUnsent != true && file.id != estimate.acceptedProposalID {
                    Button("Clear sent status") { estimate.setProposalSent(file.id, isSent: false) }
                }
                if file.kind == .supplier && booking != nil && !estimate.invoicedCostIDs.contains(booking?.externalCostID ?? file.id) {
                    Button("Unbook cost") {
                        guard let index = estimate.files?.firstIndex(where: { $0.id == file.id }) else { return }
                        estimate.files?[index].booking = nil
                    }
                }
            }
        }.padding(8)
    }

    private func fileLabel(_ filename: String, detail: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(filename).lineLimit(1).truncationMode(.middle).help(filename)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
        }
    }

    private func fileMenu<Extra: View>(data: Data, name: String, @ViewBuilder contents: () -> Extra) -> some View {
        Menu {
            Button("Quick Look", systemImage: "eye") { perform { try preview(data, name: name) } }
            Button("Save copy…", systemImage: "square.and.arrow.down") { perform { try saveCopy(data, name: name) } }
            contents()
        } label: {
            Image(systemName: "ellipsis.circle")
        }.menuIndicator(.hidden).fixedSize().accessibilityLabel("Document actions")
    }

    private func startImport(_ kind: ProjectFile.Kind) {
        importKind = kind
        importNote = nil
        importing = true
    }

    private func addFiles(_ urls: [URL]) throws {
        var project = estimate
        var files = project.files ?? []
        var documents = project.documents ?? []
        var skipped = 0
        var matched = 0
        var addedSupplier: ProjectFile?
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw LibraryError(description: "\(url.lastPathComponent) is empty.") }
            if importKind == .sent, let index = project.issuedInvoices?.firstIndex(where: { invoice in
                invoice.correctionOf == nil && invoice.files.contains { $0.data == data }
            }) {
                if project.issuedInvoices?[index].sentOn == nil {
                    project.issuedInvoices?[index].sentOn = .now
                    matched += 1
                } else {
                    skipped += 1
                }
                continue
            }
            if importKind != .supplier,
               let index = documents.firstIndex(where: { $0.proposal == (importKind == .proposal) && $0.data == data }) {
                if documents[index].sentOn == nil {
                    documents[index].sentOn = .now
                    matched += 1
                } else {
                    skipped += 1
                }
                continue
            }
            if let index = files.firstIndex(where: { $0.kind == importKind && $0.data == data }) {
                if importKind == .proposal && files[index].markedUnsent == true {
                    files[index].markedUnsent = nil
                    matched += 1
                } else {
                    skipped += 1
                }
                continue
            }
            let file = ProjectFile(kind: importKind, name: url.lastPathComponent, data: data)
            files.append(file)
            if importKind == .supplier { addedSupplier = file }
        }
        project.files = files
        project.documents = documents
        if let saveDocuments { try saveDocuments(project) }
        else { estimate = project }
        func note(_ count: Int, _ format: String) -> String {
            guard count > 0 else { return "" }
            return String(format: AppLanguage.text(format, fallback: format, locale: locale), locale: locale, count)
        }
        let notes = [note(matched, "Marked %lld matching documents as sent."),
                     note(skipped, "Skipped %lld files already recorded.")].filter { !$0.isEmpty }
        importNote = notes.isEmpty ? nil : notes.joined(separator: " ")
        if urls.count == 1 { bookingFile = addedSupplier }
    }

    private func updateExport(_ id: UUID, apply: (inout ExportedDocument) -> Void) {
        guard var documents = estimate.documents, let index = documents.firstIndex(where: { $0.id == id }) else { return }
        apply(&documents[index])
        estimate.documents = documents
    }

    private func preview(_ data: Data, name: String) throws {
        clearPreview()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previewFolder = folder
        let url = folder.appendingPathComponent(safeFilename(name))
        try data.write(to: url, options: .atomic)
        previewURL = url
    }

    private func clearPreview() {
        if let previewFolder { try? FileManager.default.removeItem(at: previewFolder) }
        previewFolder = nil
    }

    private func safeFilename(_ name: String) -> String {
        let last = URL(fileURLWithPath: name).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || last == "/" ? "Document" : last
    }

    private func saveCopy(_ data: Data, name: String) throws {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = safeFilename(name)
        if let type = UTType(filenameExtension: (name as NSString).pathExtension) { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

private struct ImportedProposalEditor: View {
    let filename: String
    @State var net: Decimal?
    let save: (Decimal) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Accept imported proposal").font(.title2.bold())
            Text(filename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Text("Use the net fee from the sent proposal.").font(.callout)
            TextField("Accepted net fee (EUR)", value: $net, format: .number)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    guard let net else { return }
                    do { try save(net); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
                    .disabled(net.map { $0 < 0 || $0 != cents($0) } ?? true)
            }
        }.padding(22).frame(width: 450)
    }
}

private struct SupplierBookingEditor: View {
    @State var booking: SupplierBooking
    let filename: String
    let phases: [Phase]
    let privateCosts: [ProjectExternalCost]
    let save: (SupplierBooking) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var error: String?

    private var costLines: [Entry] {
        phases.first { $0.id == booking.phaseID }?.entries.filter(\.externalCost) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Book supplier invoice").font(.title2.bold())
            Text(filename).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Form {
                TextField("Supplier", text: $booking.supplier)
                TextField("Invoice number", text: $booking.reference)
                Toggle("Record invoice date", isOn: Binding(
                    get: { booking.invoiceDate != nil },
                    set: { booking.invoiceDate = $0 ? Date.now : nil }
                ))
                .help("The invoice date assigns this cost to a month and year in business reports.")
                if let date = booking.invoiceDate {
                    DatePicker("Supplier invoice date", selection: Binding(
                        get: { booking.invoiceDate ?? date },
                        set: { booking.invoiceDate = $0 }
                    ), displayedComponents: .date)
                }
                TextField("Net amount (EUR)", value: $booking.amount, format: .number)
                Picker("Production phase", selection: $booking.phaseID) {
                    Text("Whole project").tag(UUID?.none)
                    ForEach(phases) { phase in
                        Text(phase.displayName(in: locale)).tag(Optional(phase.id))
                    }
                }
                .onChange(of: booking.phaseID) { _, _ in
                    booking.lineID = nil
                    booking.externalCostID = nil
                }
                let privateLines = privateCosts.filter { $0.phaseID == booking.phaseID }
                if !costLines.isEmpty || !privateLines.isEmpty {
                    Picker("Match estimated cost", selection: Binding(get: { booking.externalCostID ?? booking.lineID }, set: { id in
                        if let cost = privateLines.first(where: { $0.id == id }) {
                            booking.externalCostID = cost.id
                            booking.lineID = nil
                            booking.billAtCost = cost.reimbursable
                            if booking.amount == 0 { booking.amount = cost.booked ?? cost.planned ?? 0 }
                        } else {
                            booking.externalCostID = nil
                            booking.lineID = id
                        }
                    })) {
                        Text("Additional cost").tag(UUID?.none)
                        ForEach(costLines) { line in
                            Text(line.name.isEmpty ? line.pricingTitle(in: locale) : line.name).tag(Optional(line.id))
                        }
                        if !privateLines.isEmpty {
                            Section("Private cost estimates") {
                                ForEach(privateLines) { cost in Text(cost.title).tag(Optional(cost.id)) }
                            }
                        }
                    }
                }
                Toggle("Bill at cost", isOn: Binding(get: { booking.billAtCost == true }, set: { booking.billAtCost = $0 }))
                    .help("Offer this amount as a separate position on the next invoice.")
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Book cost") {
                    do {
                        try save(booking)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 460)
    }
}
