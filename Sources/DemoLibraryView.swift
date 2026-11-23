import SwiftUI

/// A fresh, in-memory library on every visit, including before the real library is unlocked.
struct DemoLibraryView: View {
    var startTour = false
    @Environment(\.dismiss) private var dismiss
    @State private var sample = DemoLibrary()
    @State private var selection: UUID?
    @State private var showingContacts = false
    @Environment(\.locale) private var locale
    @State private var tab = Tab.overview
    @State private var tourStep: Int?
    private enum Tab: String, CaseIterable { case overview = "Overview", estimate = "Estimate", controlling = "Controlling", documents = "Documents", billing = "Billing" }

    private let tour: [(tab: Tab, title: LocalizedStringKey, detail: LocalizedStringKey)] = [
        (.overview, "Start with a sample project", "See the agreed fee, forecast margin, and next step in the project overview."),
        (.estimate, "Build an estimate", "Change a quantity in the sample estimate to see how the fee changes."),
        (.controlling, "Track project costs", "Review planned and booked costs, recorded time, and the forecast margin."),
        (.documents, "Create a proposal", "Generate a sample proposal and find it in this project’s documents."),
        (.billing, "Track client invoices", "Review the sample invoices and try marking an open invoice as paid.")
    ]

    private func showTourStep(_ index: Int) {
        guard let project = sample.projects.first else { return }
        open(project.id)
        tab = tour[index].tab
        tourStep = index
    }

    private func tourBanner(_ index: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Guided tour · \(index + 1) of \(tour.count)").font(.caption).foregroundStyle(.secondary)
                Text(tour[index].title).font(.headline)
                Text(tour[index].detail).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Skip tour") { tourStep = nil }
            if index > 0 { Button("Back") { showTourStep(index - 1) } }
            Button(index == tour.count - 1 ? "Finish tour" : "Next") {
                if index == tour.count - 1 { tourStep = nil }
                else { showTourStep(index + 1) }
            }.buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.10))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Demo library", systemImage: "sparkles").font(.headline)
                Text("Fictional records · Changes last for this visit").foregroundStyle(.secondary)
                Spacer()
                if tourStep == nil { Button("Start guided tour…") { showTourStep(0) } }
                Button("Close demo") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            if let tourStep { tourBanner(tourStep); Divider() }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Business overview", systemImage: "chart.bar.xaxis") { selection = nil; showingContacts = false }
                    Button("Contacts hub", systemImage: "person.crop.rectangle") { showingContacts = true }
                    ForEach(sample.clients) { client in
                        Text(client.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(sample.projects.filter { $0.estimate.clientID == client.id }) { project in
                            Button(project.estimate.title) { open(project.id) }
                                .foregroundStyle(selection == project.id ? Color.accentColor : .primary)
                        }
                    }
                    Spacer()
                }.buttonStyle(.plain).padding(16).frame(width: 185, alignment: .leading)
                Divider()
                if showingContacts {
                    ContactsHub(showFreelancers: true) {
                        ClientDirectory(clients: sample.clients, projects: sample.projects, nextNumber: {
                            try NumberingPreferences().nextClientNumber(used: Set(sample.clients.map(\.number)))
                        }, save: { client in
                            sample.clients.removeAll { $0.id == client.id }
                            sample.clients.append(client)
                        }, delete: { id in sample.clients.removeAll { $0.id == id } },
                                        openProject: open, termsForNewClient: { "30 days" })
                    } freelancers: {
                        FreelancerDirectory(people: sample.people, save: { person in
                            sample.people.removeAll { $0.id == person.id }
                            sample.people.append(person)
                        }, delete: { id in sample.people.removeAll { $0.id == id } })
                    }
                } else if let index = sample.projects.firstIndex(where: { $0.id == selection }) {
                    projectDetail($sample.projects[index].estimate)
                } else {
                    BusinessOverviewView(projects: sample.projects, demo: true)
                }
            }
        }.frame(width: 1030, height: 650)
        .onAppear { if startTour { showTourStep(0) } }
    }

    private func open(_ id: UUID) {
        selection = id
        showingContacts = false
        tab = .overview
    }

    private func projectDetail(_ project: Binding<Estimate>) -> some View {
        let estimate = project.wrappedValue
        return VStack(alignment: .leading, spacing: 14) {
            Text(estimate.title).font(.largeTitle.bold())
            Text(estimate.client).foregroundStyle(.secondary)
            Picker("Project view", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                switch tab {
                case .overview:
                    ProjectOverview(estimate: estimate, showEstimate: { tab = .estimate }, showControlling: { tab = .controlling },
                                    showDocuments: { tab = .documents }, showBilling: { tab = .billing })
                case .estimate:
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(project.phases) { $phase in
                            GroupBox(phase.displayName(in: locale)) {
                                ForEach($phase.entries) { $entry in
                                    HStack {
                                        Text(entry.name)
                                        Spacer()
                                        TextField("Quantity", value: $entry.quantity, format: .number).frame(width: 130)
                                    }
                                }.padding(5)
                            }
                        }
                        LabeledContent("Net estimate", value: euros(estimate.calculate().totals.sales)).font(.headline)
                    }
                case .controlling: ControllingView(estimate: project)
                case .documents:
                    ProjectFilesView(estimate: project) {
                        sample.createProposal(for: project, german: locale.language.languageCode?.identifier == "de")
                    }
                case .billing:
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(estimate.issuedInvoices ?? []) { invoice in
                            GroupBox(invoice.number) {
                                VStack {
                                    LabeledContent("Net invoiced", value: euros(invoice.net))
                                    LabeledContent("Outstanding invoices", value: euros(invoice.outstanding))
                                    if estimate.canMarkInvoicePaid(invoice.id) {
                                        Button("Mark paid") { try? project.wrappedValue.markInvoicePaid(invoice.id) }
                                    }
                                }.padding(8)
                            }
                        }
                    }
                }
            }
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DemoLibrary {
    var clients: [Client]
    var people = [Freelancer(name: "Rae Example", role: "Camera operator", email: "camera@example.org", website: "https://example.org", dayRate: 650)]
    var projects: [Project]
    init() {
        let agency = Client(number: "KD4816", name: "Northlight Studio")
        let gallery = Client(number: "KD7293", name: "Paper Kite Gallery")
        clients = [agency, gallery].map { value in
            var client = value
            client.contacts = [ClientContact(name: "Production desk", role: "Production", email: "production@example.org"),
                               ClientContact(name: "Accounts desk", role: "Billing", email: "billing@example.org")]
            client.website = "https://example.org"
            client.projectAcronym = value.id == agency.id ? "NL" : "PK"
            return client
        }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: .now)
        let month = calendar.component(.month, from: .now)
        projects = [(agency, "Summer Stories", 4), (agency, "Studio Sessions", 2), (gallery, "After Hours", 3)]
            .enumerated().map { index, row in
                let (client, title, days) = row
                var estimate = Estimate()
                estimate.title = title
                estimate.client = client.name
                estimate.clientID = client.id
                estimate.clientNumber = client.number
                estimate.projectNumber = ["NL-001", "NL-002", "PK-001"][index]
                estimate.purchaseOrder = "PO-DEMO-0" + String(index + 1)
                estimate.status = .active
                estimate.applyDayRates(DayRateSchedule(name: "Studio day", tiers: [RateTier(lastDay: 3, rate: 800), RateTier(lastDay: nil, rate: 720)]))
                estimate.phases = [
                    Phase(name: "Pre-Production", entries: [Entry(name: "Planning", quantity: 1, cost: 300)]),
                    Phase(name: "Production", entries: [Entry(name: "Producer", quantity: Decimal(days), cost: 300),
                                                        Entry(name: "Camera crew", pricing: .crew, quantity: 1, rate: 650, cost: 500)])
                ]
                estimate.manualBudget = CostBudget(estimate)
                let phase = estimate.phases[1]
                let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
                estimate.externalCosts = [ProjectExternalCost(title: "Music licence", phaseID: phase.id, planned: 280, booked: 325,
                                                              date: date, reimbursable: index == 1)]
                estimate.timeRecords = [TimeRecord(date: date, phaseID: phase.id, lineID: phase.entries[0].id, days: 1, rate: 320)]
                estimate.issuedInvoices = (1...month).compactMap { m in
                    guard m == month || (m + index) % 3 == 0 else { return nil }
                    let day = calendar.date(from: DateComponents(year: year, month: m, day: 1)) ?? date
                    let net = Decimal(400 + (index + 1) * 190 + m * 22)
                    let vat = cents(net * Decimal(19) / 100)
                    var invoice = IssuedInvoice(number: "DEMO-\(index + 1)-\(m)", issueDate: day, dueDate: nil, title: title,
                                                projectName: title, sender: nil, recipient: nil, servicePeriod: "", paymentTerms: "",
                                                net: net, vatRate: 19, vat: vat)
                    if m < month || index == 1 { invoice.payments = [InvoicePayment(date: day, amount: net + vat)] }
                    return invoice
                }
                return Project(id: UUID(), estimate: estimate)
            }
    }

    @MainActor func createProposal(for estimate: Binding<Estimate>, german: Bool) {
        let project = estimate.wrappedValue
        let fees = ClientDocument.fees(for: project)
        let version = (project.documents ?? []).count + 1
        var document = ClientDocument(german: german, reference: "DEMO-0" + String(version), sender: "Example Production")
        document.scope = project.title
        let recipient = clients.first { $0.id == project.clientID }
        let layout = document.contents(project: project.title, recipient: recipient, fees: fees)
        guard let pdf = try? layout.pdfData() else { return }
        let naming = ExportNaming(date: document.date, invoice: false, reference: document.reference,
                                  project: project.title, invoiceName: "", milestone: nil, schedule: nil,
                                  history: project.documents ?? [], pdf: true,
                                  previousVersion: project.discardedExportVersions?["proposal"] ?? 0)
        let exported = ExportedDocument(filename: naming.filename, data: pdf, date: document.date, proposal: true,
                                        net: project.calculate().totals.sales, phaseFees: fees,
                                        exportVersion: naming.version, costBudget: CostBudget(project),
                                        calculationInputs: project.calculationInputs)
        estimate.wrappedValue.documents = (project.documents ?? []) + [exported]
    }
}
