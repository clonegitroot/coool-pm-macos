import SwiftUI
import Contacts
import UniformTypeIdentifiers

struct ClientDefaultsFields: View {
    @Binding var profile: BusinessProfile

    private var numbering: Binding<NumberingPreferences> {
        Binding(get: { profile.numbering ?? NumberingPreferences() }, set: { profile.numbering = $0 })
    }

    var body: some View {
        TextField("Client number prefix", text: numbering.prefix)
        Stepper("Number of digits · \(numbering.wrappedValue.digits)", value: numbering.digits, in: 2...8)
        Toggle("Randomize new client numbers", isOn: numbering.randomize)
            .help("Turn off to assign consecutive numbers. Previously assigned numbers stay reserved.")
        Stepper("Default payment deadline · \(profile.defaultPaymentDays ?? 30) days", value: Binding(
            get: { profile.defaultPaymentDays ?? 30 }, set: { profile.defaultPaymentDays = $0 }), in: 0...3650)
    }
}

enum ContactCard {
    @MainActor static func export(name: String, company: String = "", role: String = "", email: String, phone: String = "", address: String = "") throws {
        let contact = CNMutableContact()
        contact.givenName = name
        contact.organizationName = company
        contact.jobTitle = role
        if name.isEmpty { contact.contactType = .organization }
        if !email.isEmpty { contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)] }
        if !phone.isEmpty { contact.phoneNumbers = [CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: phone))] }
        if !address.isEmpty {
            let value = CNMutablePostalAddress()
            value.street = address
            contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: value)]
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.vCard]
        panel.nameFieldStringValue = (name.isEmpty ? company : name).replacingOccurrences(of: "/", with: "-") + ".vcf"
        if panel.runModal() == .OK, let url = panel.url {
            try CNContactVCardSerialization.data(with: [contact]).write(to: url, options: .atomic)
        }
    }
}

struct AgreementField: View {
    let title: LocalizedStringKey
    @Binding var file: DirectoryFile?
    @State private var error: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .leading) {
                if let file {
                    HStack {
                        Text(verbatim: file.name).lineLimit(1).truncationMode(.middle)
                        Button {
                            let panel = NSSavePanel()
                            panel.nameFieldStringValue = URL(fileURLWithPath: file.name).lastPathComponent
                            if panel.runModal() == .OK, let url = panel.url {
                                do { try file.data.write(to: url, options: .atomic) }
                                catch { self.error = error.localizedDescription }
                            }
                        } label: { Image(systemName: "square.and.arrow.down") }.help("Save a copy…")
                        Button(role: .destructive) { self.file = nil } label: { Image(systemName: "minus.circle") }.help("Remove attachment")
                    }
                } else {
                    Button("Attach file…") {
                        let panel = NSOpenPanel()
                        if panel.runModal() == .OK, let url = panel.url {
                            do { file = DirectoryFile(name: url.lastPathComponent, data: try Data(contentsOf: url)) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
    }
}

struct FreelancerDirectory: View {
    let people: [Freelancer]
    let save: (Freelancer) throws -> Void
    let delete: (UUID) throws -> Void
    @State private var draft: Freelancer?
    @State private var deletion: Freelancer?
    @State private var archived = false
    @State private var error: String?
    @Environment(\.locale) private var locale
    @State private var search = ""
    private var visible: [Freelancer] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return people.filter { person in
            (archived || person.archivedAt == nil) &&
            (query.isEmpty || [person.name, person.role, person.email, person.website ?? ""].contains { $0.localizedStandardContains(query) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TextField("Search freelancers", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                Toggle("Show archived freelancers", isOn: $archived)
                Spacer()
                Button("New freelancer", systemImage: "plus") { draft = Freelancer() }
                    .buttonStyle(.borderedProminent)
            }.padding([.horizontal, .top], 24)

            if visible.isEmpty {
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("No freelancers yet", systemImage: "person.2")
                } else {
                    ContentUnavailableView.search(text: search)
                }
            } else {
                DirectoryGrid {
                    ForEach(visible) { person in
                        DirectoryContactCard(name: person.name, subtitle: person.role,
                                             detail: person.dayRate.formatted(.currency(code: "EUR").locale(locale)),
                                             archived: person.archivedAt != nil, email: person.email,
                                             phone: person.phone, website: person.website, accent: .teal) {
                            if person.nda != nil {
                                Text("NDA").font(.caption).foregroundStyle(.secondary)
                            }
                            Menu {
                                Button("Edit…") { draft = person }
                                Button("Save to Contacts…") { perform { try ContactCard.export(name: person.name, role: person.role, email: person.email, phone: person.phone) } }
                                Button(person.archivedAt == nil ? "Archive freelancer" : "Restore freelancer") {
                                    var updated = person
                                    updated.archivedAt = person.archivedAt == nil ? .now : nil
                                    perform { try save(updated) }
                                }
                                Button("Delete freelancer…", role: .destructive) { deletion = person }
                            } label: {
                                Label("Freelancer actions", systemImage: "ellipsis.circle")
                            }.labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $draft) { person in FreelancerEditor(person: person, save: save).environment(\.locale, locale) }
        .confirmationDialog("Delete this freelancer permanently?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                            titleVisibility: .visible, presenting: deletion) { person in
            Button("Delete", role: .destructive) { perform { try delete(person.id) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Directory action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

struct FreelancerEditor: View {
    @State var person: Freelancer
    let save: (Freelancer) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Freelancer details").font(.title2.bold())
            Form {
                TextField("Name", text: $person.name)
                TextField("Role", text: $person.role)
                TextField("Contact email", text: $person.email)
                TextField("Phone", text: $person.phone)
                TextField("Website", text: Binding(get: { person.website ?? "" }, set: { person.website = $0.isEmpty ? nil : $0 }))
                TextField("Day rate (EUR)", value: $person.dayRate, format: .number)
                AgreementField(title: "NDA", file: $person.nda)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel", role: .cancel) { dismiss() }; Button("Save") {
                do { try save(person); dismiss() } catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(minWidth: 460)
    }
}
