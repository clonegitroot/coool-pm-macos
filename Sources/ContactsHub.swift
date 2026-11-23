import SwiftUI

enum ContactArea { case clients, freelancers }

struct ContactsHub<ClientContent: View, FreelancerContent: View>: View {

    let showFreelancers: Bool
    var selection: Binding<ContactArea>? = nil
    @ViewBuilder let clients: () -> ClientContent
    @ViewBuilder let freelancers: () -> FreelancerContent
    @State private var localTab = ContactArea.clients
    private var tab: Binding<ContactArea> { selection ?? $localTab }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Label("Contacts hub", systemImage: "person.crop.rectangle")
                    .font(.title2.weight(.semibold))
                Spacer()
                if showFreelancers {
                    Picker("Contact type", selection: tab) {
                        Text("Clients").tag(ContactArea.clients)
                        Text("Freelancers").tag(ContactArea.freelancers)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            Divider()
            if showFreelancers && tab.wrappedValue == .freelancers {
                freelancers()
            } else {
                clients()
            }
        }
        .onChange(of: showFreelancers) { _, enabled in
            if !enabled { tab.wrappedValue = .clients }
        }
    }
}

struct DirectoryGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14, alignment: .top)],
                      alignment: .leading, spacing: 14, content: content)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 2)
        }
    }
}

struct DirectoryContactCard<Actions: View>: View {
    let name: String
    let subtitle: String
    let detail: String
    let archived: Bool
    let email: String
    let phone: String
    let website: String?
    let accent: Color
    var isPrimary = false
    @ViewBuilder let actions: () -> Actions

    private var initials: String {
        name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
            .map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(initials)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if archived {
                        Label("Archived", systemImage: "archivebox")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if isPrimary {
                        Text("Primary contact").font(.caption).foregroundStyle(accent)
                    }
                }
                Spacer(minLength: 0)
                actions()
            }
            Group {
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(minHeight: 15, alignment: .leading)
            Divider()
            ContactShortcuts(email: email, phone: phone, website: website)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary)
                .allowsHitTesting(false)
        }
    }
}

struct ContactShortcuts: View {
    let email: String
    let phone: String
    let website: String?

    var body: some View {
        HStack(spacing: 6) {
            shortcut("Mail", icon: "envelope", url: ContactLink.mail(email))
            shortcut("Call", icon: "phone", url: ContactLink.call(phone))
            shortcut("Website", icon: "globe", url: ContactLink.website(website))
        }
        .controlSize(.small)
    }

    private func shortcut(_ title: LocalizedStringKey, icon: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) }
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .disabled(url == nil)
        .help(title)
    }

    @Environment(\.openURL) private var openURL
}

private enum ContactLink {
    static func mail(_ value: String) -> URL? {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        return components.url
    }

    static func call(_ value: String) -> URL? {
        let number = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = "0123456789"
        let body = number.hasPrefix("+") ? number.dropFirst() : number[...]
        guard body.allSatisfy({ digits.contains($0) || " ()-.".contains($0) }) else { return nil }
        let normalized = body.filter { digits.contains($0) }
        guard !normalized.isEmpty else { return nil }
        return URL(string: "tel:" + (number.hasPrefix("+") ? "+" : "") + normalized)
    }

    static func website(_ value: String?) -> URL? {
        guard let address = value?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty,
              address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }
        let candidate = address.contains("://") ? address : "https://" + address
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil else { return nil }
        return components.url
    }
}
