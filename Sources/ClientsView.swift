import SwiftUI

struct ClientDirectory: View {
    let clients: [Client]
    let projects: [Project]
    let nextNumber: () throws -> String
    let save: (Client) throws -> Void
    let delete: (UUID) throws -> Void
    let openProject: (UUID) -> Void
    var termsForNewClient: () -> String = { BusinessProfile.load().newClientTerms }
    @Environment(\.locale) private var locale
    @State private var draft: Client?
    @State private var selected: UUID?
    @State private var showArchived = false
    @State private var deletingClient: Client?
    @State private var error: String?

    @State private var search = ""

    private var visibleClients: [Client] { clients.filter { showArchived || $0.archivedAt == nil } }

    private var matchingClients: [Client] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleClients.filter { client in
            query.isEmpty || [client.name, client.number, client.website ?? ""].contains { $0.localizedStandardContains(query) } ||
            client.activeContacts.contains { $0.displayName.localizedStandardContains(query) || $0.email.localizedStandardContains(query) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if let client = visibleClients.first(where: { $0.id == selected }) {
                clientDetail(client)
            } else {
                cardBrowser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $draft) { client in
            ClientEditor(client: client) { updated in
                try save(updated)
                selected = updated.id
            }.environment(\.locale, locale)
        }
        .confirmationDialog("Delete this client permanently?", isPresented: Binding(
            get: { deletingClient != nil }, set: { if !$0 { deletingClient = nil } }
        ), titleVisibility: .visible, presenting: deletingClient) { client in
            Button("Delete client", role: .destructive) {
                perform {
                    try delete(client.id)
                    if selected == client.id { selected = nil }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { client in
            Text("Deleting \(client.name) removes its contacts and folders. Linked projects and issued documents remain in the library.")
        }
        .alert("Client action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private var cardBrowser: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TextField("Search clients", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle("Show archived clients", isOn: $showArchived)
                Spacer()
                Button("New client", systemImage: "plus") {
                    perform { draft = Client(number: try nextNumber(), name: "", terms: termsForNewClient()) }
                }.buttonStyle(.borderedProminent)
            }.padding([.horizontal, .top], 24)

            if matchingClients.isEmpty {
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("No clients yet", systemImage: "building.2")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            } else {
                DirectoryGrid {
                    ForEach(matchingClients) { client in
                        let primary = client.primaryContact
                        DirectoryContactCard(name: client.name, subtitle: client.number, detail: primary?.displayName ?? "",
                                             archived: client.archivedAt != nil, email: primary?.email ?? "",
                                             phone: primary?.phone ?? "", website: client.website, accent: .accentColor) {
                            Button("View client", systemImage: "arrow.up.right") { selected = client.id }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.bordered)
                                .help("View client")
                        }
                        .contextMenu {
                            Button("Edit client") { draft = client }
                            clientActions(client)
                        }
                    }
                }
            }
        }
    }

    private func clientDetail(_ client: Client) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("Back to clients", systemImage: "chevron.left") { selected = nil }
                HStack(alignment: .top) {
                    Text(client.name).font(.largeTitle.bold())
                    if client.archivedAt != nil { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Menu { clientActions(client) } label: {
                        Label("Client actions", systemImage: "ellipsis.circle")
                    }.labelStyle(.iconOnly)
                }
                Text(client.number).foregroundStyle(.secondary)
                if !client.address.isEmpty { Text(client.address) }
                LabeledContent("Payment terms", value: client.terms)
                ContactShortcuts(email: client.primaryContact?.email ?? "", phone: client.primaryContact?.phone ?? "",
                                 website: client.website)
                HStack {
                    Button("Edit client") { draft = client }
                    Button("Save company contact…") {
                        perform { try ContactCard.export(name: "", company: client.name, email: "", address: client.address) }
                    }
                }

                Divider()
                Text("Contacts").font(.headline)
                if client.activeContacts.isEmpty {
                    Text("No contacts yet").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(client.activeContacts) { person in
                            DirectoryContactCard(name: person.displayName, subtitle: person.role,
                                                 detail: person.email.isEmpty ? person.phone : person.email, archived: false,
                                                 email: person.email, phone: person.phone, website: client.website, accent: .accentColor,
                                                 isPrimary: client.primaryContact?.id == person.id) {
                                Button("Save to Contacts…", systemImage: "square.and.arrow.up") {
                                    perform { try ContactCard.export(name: person.name, company: client.name, role: person.role,
                                                                     email: person.email, phone: person.phone, address: client.address) }
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.bordered)
                                .help("Save to Contacts…")
                            }
                        }
                    }
                }

                Divider()
                Text("Projects").font(.headline)
                let related = projects.filter {
                    [$0.estimate.clientID, $0.estimate.endClientID, $0.estimate.invoiceClientID].contains(client.id)
                }
                if related.isEmpty { Text("No linked projects").foregroundStyle(.secondary) }
                ForEach(related) { project in
                    Button(project.estimate.displayTitle(in: locale)) { openProject(project.id) }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func clientActions(_ client: Client) -> some View {
        Button(client.archivedAt == nil ? "Archive client" : "Restore client from archive") {
            perform {
                var updated = client
                updated.archivedAt = client.archivedAt == nil ? .now : nil
                try save(updated)
                if !showArchived && updated.archivedAt != nil && selected == client.id { selected = nil }
            }
        }
        Button("Delete client…", role: .destructive) { deletingClient = client }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

struct ClientEditor: View {
    @State var client: Client
    let save: (Client) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var error = ""

    private enum Tab: String, CaseIterable {
        case company = "Company", contacts = "Contacts", electronic = "XRechnung"
    }
    @State private var tab = Tab.company
    @State private var editedPerson: ClientContact?
    @State private var personToRemove: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(client.name.isEmpty ? "New client" : "Edit client").font(.title2.bold())
            Picker("Client details", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { option in Text(LocalizedStringKey(option.rawValue)).tag(option) }
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                switch tab {
                case .contacts: contactsContent
                case .company:
                    Form {
                        TextField("Company", text: $client.name)
                        TextField("Website", text: Binding(get: { client.website ?? "" }, set: { client.website = $0.isEmpty ? nil : $0 }))
                        TextField("Client number", text: $client.number)
                        TextField("Project number acronym", text: Binding(get: { client.projectAcronym ?? "" }, set: { client.projectAcronym = $0 }))
                            .help("Used for new project numbers, for example ST-001. Leave blank to use the client number.")
                        AgreementField(title: "NDA", file: $client.nda)
                        AgreementField(title: "Client contract", file: $client.contract)
                        TextField("Billing address", text: $client.address, axis: .vertical).lineLimit(2...5)
                        TextField("Payment terms", text: $client.terms)
                        RebatePercentField("Client rebate (%)", percent: $client.rebatePercent)
                            .help("Default rebate for this client’s draft projects. Subcontractor and expense lines are excluded.")
                    }.formStyle(.grouped)
                case .electronic:
                    Form {
                        TextField("Buyer reference / Leitweg-ID", text: electronic.buyerReference)
                            .help("Use the reference the buyer gave you for electronic invoices.")
                        ElectronicPartyFields(party: electronic.buyer, seller: false, includeName: false)
                    }.formStyle(.grouped)
                }
            }.frame(minHeight: 225)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save client", action: submit).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580, height: 470)
        .sheet(item: $editedPerson) { person in
            ContactEditor(person: person) { updated in
                var people = client.contactPeople
                if let index = people.firstIndex(where: { $0.id == updated.id }) { people[index] = updated }
                else { people.append(updated) }
                client.contacts = people
            }.environment(\.locale, locale)
        }
        .confirmationDialog("Delete this contact permanently?", isPresented: Binding(
            get: { personToRemove != nil }, set: { if !$0 { personToRemove = nil } }
        )) {
            Button("Delete contact", role: .destructive) {
                if let id = personToRemove { client.contacts = client.contactPeople.filter { $0.id != id } }
                personToRemove = nil
            }
            Button("Cancel", role: .cancel) { personToRemove = nil }
        }
    }

    private var electronic: Binding<ElectronicRecipientDefaults> {
        Binding(get: { client.electronicInvoice ?? ElectronicRecipientDefaults() },
                set: { client.electronicInvoice = $0 })
    }

    private var contactsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Add contact…", systemImage: "plus") { editedPerson = ClientContact() }
            if client.contactPeople.isEmpty {
                Text("No contacts yet").foregroundStyle(.secondary)
            }
            ForEach(client.contactPeople) { person in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(person.displayName).fontWeight(.medium)
                        if !person.email.isEmpty { Text(person.email).foregroundStyle(.secondary) }
                        if person.archivedAt != nil { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if client.primaryContact?.id == person.id {
                        Text("Primary contact").font(.caption).foregroundStyle(.secondary)
                    }
                    Menu {
                        Button("Edit contact…") { editedPerson = person }
                        if person.archivedAt == nil && client.primaryContact?.id != person.id {
                            Button("Make primary") { client.primaryContactID = person.id }
                        }
                        Button(person.archivedAt == nil ? "Archive contact" : "Restore contact from archive") {
                            var contacts = client.contactPeople
                            guard let index = contacts.firstIndex(where: { $0.id == person.id }) else { return }
                            contacts[index].archivedAt = person.archivedAt == nil ? .now : nil
                            client.contacts = contacts
                        }
                        Button("Delete contact…", role: .destructive) { personToRemove = person.id }
                    } label: { Label("Contact actions", systemImage: "ellipsis.circle") }.labelStyle(.iconOnly)
                }
                Divider()
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        do {
            client.number = client.number.trimmingCharacters(in: .whitespacesAndNewlines)
            client.name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try save(client)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ContactEditor: View {
    @State var person: ClientContact
    let save: (ClientContact) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contact details").font(.title2.bold())
            Form {
                TextField("Contact name", text: $person.name)
                TextField("Role", text: $person.role)
                TextField("Contact email", text: $person.email)
                TextField("Phone", text: $person.phone)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save contact") {
                    person.trimFields()
                    save(person)
                    dismiss()
                }.keyboardShortcut(.defaultAction)
                    .disabled(person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              person.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(22).frame(width: 425)
    }
}

struct RebatePercentField: View {
    let label: LocalizedStringKey
    @Binding var percent: Decimal?

    init(_ label: LocalizedStringKey, percent: Binding<Decimal?>) {
        self.label = label
        _percent = percent
    }

    var body: some View {
        TextField(label, value: Binding(get: { percent }, set: { value in
            percent = value.map { cents(min(100, max(0, $0))) }
        }), format: .number)
    }
}
