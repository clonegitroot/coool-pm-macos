import SwiftUI

enum ProjectLibrarySelection: Hashable {
    case project(UUID)
    case folder(clientID: UUID, folderID: UUID)
}

struct ProjectFolderRequest: Identifiable {
    let id = UUID()
    let clientID: UUID?
    var folder: ProjectFolder?
}

struct ProjectLibrarySidebar: View {
    let clients: [Client]
    let projects: [Project]
    let search: String
    let showEmptyClients: Bool
    let showArchived: Bool
    @Binding var selection: ProjectLibrarySelection?
    let newProject: (UUID?, UUID?) -> Void
    let editFolder: (ProjectFolderRequest) -> Void
    let move: (UUID, UUID?) -> Void
    let archive: (UUID, Bool) -> Void
    let duplicate: (UUID) -> Void
    let askToDelete: (Project) -> Void

    @Environment(\.locale) private var locale
    @State private var collapsedClients: Set<UUID> = []
    @State private var expandedFolders: Set<UUID> = []

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var selectedProject: Project? {
        guard case .project(let id) = selection else { return nil }
        return projects.first { $0.id == id }
    }

    var body: some View {
        let knownClients = Set(clients.map(\.id))
        let eligible = projects.filter { showArchived || $0.estimate.archivedAt == nil }
        let grouped = Dictionary(grouping: eligible) { $0.estimate.clientID }
        let clientNames = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0.name) })
        let unassigned = eligible.filter { project in
            project.estimate.clientID.map { !knownClients.contains($0) } ?? true
        }.filter { matches($0, clientNames: clientNames) }

        List(selection: $selection) {
            ForEach(clients.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { client in
                let assigned = grouped[client.id] ?? []
                let active = assigned.contains { $0.estimate.archivedAt == nil && $0.estimate.currentStatus != .closed }
                let revealed = assigned.contains { $0.id == selectedProject?.id } ||
                    (showArchived && !assigned.isEmpty) || (!query.isEmpty && !assigned.isEmpty)
                if active || revealed || (showEmptyClients && (client.archivedAt == nil || showArchived)) {
                    clientSection(client, projects: assigned, clientNames: clientNames)
                }
            }
            if !unassigned.isEmpty {
                Section("No client assigned") {
                    ForEach(unassigned) { project in projectRow(project, client: nil) }
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection, initial: true) { _, value in
            switch value {
            case .project:
                if let clientID = selectedProject?.estimate.clientID { collapsedClients.remove(clientID) }
                if let folderID = selectedProject?.estimate.folderID { expandedFolders.insert(folderID) }
            case .folder(let clientID, _):
                collapsedClients.remove(clientID)
            case nil:
                break
            }
        }
        .onChange(of: selectedProject?.estimate.clientID) { _, id in
            if let id { collapsedClients.remove(id) }
        }
        .onChange(of: selectedProject?.estimate.folderID) { _, id in
            if let id { expandedFolders.insert(id) }
        }
    }

    @ViewBuilder
    private func clientSection(_ client: Client, projects: [Project], clientNames: [UUID: String]) -> some View {
        let folders = (client.projectFolders ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let folderIDs = Set(folders.map(\.id))
        let matchesClient = containsQuery(client.name) || containsQuery(client.number)
        let visibleProjects = matchesClient ? projects : projects.filter { project in
            matches(project, clientNames: clientNames, folderName: client.folder(project.estimate.folderID)?.name)
        }
        let grouped = Dictionary(grouping: visibleProjects) { $0.estimate.folderID }
        let visibleFolders = folders.filter { matchesClient || containsQuery($0.name) || grouped[$0.id] != nil }
        let outsideFolders = visibleProjects.filter { project in
            project.estimate.folderID.map { !folderIDs.contains($0) } ?? true
        }

        if matchesClient || !visibleProjects.isEmpty || !visibleFolders.isEmpty {
            Section(isExpanded: clientExpansion(client.id)) {
                ForEach(visibleFolders) { folder in
                    folderRow(folder, client: client, projects: grouped[folder.id] ?? [])
                }
                ForEach(outsideFolders) { project in projectRow(project, client: client) }
                if visibleFolders.isEmpty && outsideFolders.isEmpty {
                    Text("No projects yet").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(client.name)
                    .help("\(client.name) · \(client.number)")
                    .contextMenu {
                        if client.archivedAt == nil {
                            Button("New folder…", systemImage: "folder.badge.plus") {
                                editFolder(ProjectFolderRequest(clientID: client.id))
                            }
                            Button("New project for client", systemImage: "plus") { newProject(client.id, nil) }
                        }
                    }
            }
        }
    }

    private func folderRow(_ folder: ProjectFolder, client: Client, projects: [Project]) -> some View {
        let item = ProjectLibrarySelection.folder(clientID: client.id, folderID: folder.id)
        return DisclosureGroup(isExpanded: folderExpansion(folder.id)) {
            ForEach(projects) { project in projectRow(project, client: client) }
            if projects.isEmpty { Text("No projects yet").font(.caption).foregroundStyle(.secondary) }
        } label: {
            Button { selection = item } label: {
                Label(folder.name, systemImage: selection == item ? "folder.fill" : "folder")
                    .foregroundStyle(selection == item ? Color.accentColor : Color.primary)
                    .fontWeight(selection == item ? .semibold : .regular)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == item ? .isSelected : [])
            .help("Open the folder’s financial report.")
            .contextMenu {
                if client.archivedAt == nil {
                    Button("New project in folder", systemImage: "plus") { newProject(client.id, folder.id) }
                }
                Button("Rename folder…", systemImage: "pencil") {
                    editFolder(ProjectFolderRequest(clientID: client.id, folder: folder))
                }
            }
        }
        .tag(item)
    }

    private func projectRow(_ project: Project, client: Client?) -> some View {
        let isArchived = project.estimate.archivedAt != nil
        return VStack(alignment: .leading, spacing: 3) {
            Text(project.estimate.displayTitle(in: locale)).lineLimit(1)
            HStack(spacing: 5) {
                Text(project.estimate.currentStatus.label(in: locale))
                if isArchived { Text("Archived") }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .tag(ProjectLibrarySelection.project(project.id))
        .contextMenu {
            Button("Duplicate project", systemImage: "plus.square.on.square") { duplicate(project.id) }
            folderMenu(for: project, client: client)
            Button(isArchived ? "Restore project from archive" : "Archive project",
                   systemImage: isArchived ? "arrow.uturn.backward" : "archivebox") {
                archive(project.id, !isArchived)
            }
            Button("Delete project…", systemImage: "trash", role: .destructive) { askToDelete(project) }
        }
    }

    @ViewBuilder
    private func folderMenu(for project: Project, client: Client?) -> some View {
        if let client, let folders = client.projectFolders, !folders.isEmpty {
            Menu("Move to folder", systemImage: "folder") {
                Button("No folder") { move(project.id, nil) }
                    .disabled(client.folder(project.estimate.folderID) == nil)
                ForEach(folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                    Button(folder.name) { move(project.id, folder.id) }
                        .disabled(project.estimate.folderID == folder.id)
                }
            }
        }
    }

    private func clientExpansion(_ id: UUID) -> Binding<Bool> {
        Binding {
            !query.isEmpty || !collapsedClients.contains(id)
        } set: { isExpanded in
            if isExpanded { collapsedClients.remove(id) }
            else { collapsedClients.insert(id) }
        }
    }

    private func folderExpansion(_ id: UUID) -> Binding<Bool> {
        Binding {
            !query.isEmpty || expandedFolders.contains(id)
        } set: { isExpanded in
            if isExpanded { expandedFolders.insert(id) }
            else { expandedFolders.remove(id) }
        }
    }

    private func containsQuery(_ value: String) -> Bool {
        query.isEmpty || value.localizedCaseInsensitiveContains(query)
    }

    private func matches(_ project: Project, clientNames: [UUID: String], folderName: String? = nil) -> Bool {
        let estimate = project.estimate
        let linkedNames = [estimate.clientID, estimate.endClientID, estimate.invoiceClientID]
            .compactMap { $0 }.compactMap { clientNames[$0] }
        return ([estimate.displayTitle(in: locale), estimate.currentStatus.label(in: locale), folderName ?? ""] + linkedNames)
            .contains(where: containsQuery)
    }
}

struct ProjectFolderEditor: View {
    let request: ProjectFolderRequest
    let clients: [Client]
    let save: (UUID, ProjectFolder) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var clientID: UUID?
    @State private var name: String
    @State private var error: String?

    init(request: ProjectFolderRequest, clients: [Client], save: @escaping (UUID, ProjectFolder) throws -> Void) {
        self.request = request
        self.clients = clients
        self.save = save
        _clientID = State(initialValue: request.clientID ?? (clients.count == 1 ? clients.first?.id : nil))
        _name = State(initialValue: request.folder?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.folder == nil ? "New project folder" : "Rename project folder")
                .font(.title2.bold())
            if request.folder == nil {
                Picker("Client", selection: $clientID) {
                    Text("Select client").tag(nil as UUID?)
                    ForEach(clients) { client in Text("\(client.name) · \(client.number)").tag(Optional(client.id)) }
                }
            } else if let client = clients.first(where: { $0.id == clientID }) {
                Text(client.name).foregroundStyle(.secondary)
            }
            TextField("Folder name", text: $name).focused($nameFocused)
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: submit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(clientID == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { nameFocused = true }
    }

    private func submit() {
        guard let clientID else { return }
        var folder = request.folder ?? ProjectFolder(name: "")
        folder.name = name
        do {
            try save(clientID, folder)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
