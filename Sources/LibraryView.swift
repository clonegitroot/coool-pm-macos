import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let beginFreshSetup: () -> Void
    private enum Destination { case project, contacts, business }
    @State private var contactArea = ContactArea.clients
    @State private var newClientDraft: Client?
    @State private var newFreelancerDraft: Freelancer?

    @Environment(\.locale) private var locale
    @Environment(\.openWindow) private var openWindow
    @ProtectedSetting(DayRateLibrary.storageKey) private var rateLibraryData = Data()
    @ProtectedSetting("businessProfile") private var profileData = Data()
    private var features: UsageFeatures { (try? JSONDecoder().decode(BusinessProfile.self, from: profileData))?.features ?? .full }
    @State private var database: ProjectDatabase?
    @State private var libraryVersion: Int64?
    @State private var clients = [Client]()
    @State private var freelancers = [Freelancer]()
    @State private var destination = Destination.project
    @State private var search = ""
    @State private var projects = [Project]()
    @AppStorage("projectAutosave") private var projectAutosave = true
    @State private var projectDrafts: [UUID: ProjectDraft] = [:]
    @State private var confirmingDiscard = false

    private struct ProjectDraft {
        let baseline: Estimate
        var estimate: Estimate
    }
    @ProtectedSetting("selectedProject") private var lastProject = ""
    @State private var selection: ProjectLibrarySelection?
    @AppStorage("showArchivedProjects") private var showArchivedProjects = false
    @AppStorage("showClientsWithoutActiveProjects") private var showEmptyClients = false
    @State private var folderRequest: ProjectFolderRequest?
    @State private var projectToDelete: Project?
    @State private var message: String?
    @AppStorage("libraryBackupRequested") private var libraryBackupRequested = false
    @AppStorage("libraryResetRequested") private var libraryResetRequested = false
    @State private var showingReset = false
    @State private var reopenSetupAfterReset = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("onboardingRequested") private var onboardingRequested = false
    @State private var showingOnboarding = false
    @State private var showingBackup = false
    @State private var selectingRestoreAfterBackup = false
    @State private var pendingRestore: LibraryBackup?
    @State private var lastFreshnessProbe: Int?
    @State private var backupRunning = false
    @State private var backupFreshness = LibraryBackupView.Freshness.none
    @State private var cloud = CloudLibrarySync()
    @State private var cloudRunning = false
    @State private var cloudConflict: CloudLibrarySync.Conflict?
    @State private var syncError = ""
    @AppStorage("automaticCloudSync") private var automaticCloudSync = false
    @AppStorage("lastLibrarySync") private var lastLibrarySync = 0.0
    @ProtectedSetting("automaticBackupBookmark") private var automaticBackupBookmark = Data()
    @ProtectedSetting("automaticBackupFolder") private var automaticBackupFolder = ""
    @AppStorage("lastAutomaticBackup") private var lastAutomaticBackup = 0.0
    @AppStorage("lastLibraryBackup") private var lastLibraryBackup = 0.0
    @AppStorage(BackupReminder.storageKey) private var backupReminderDays = BackupReminder.defaultDays
    @AppStorage("backupReminderStartedAt") private var backupReminderStartedAt = 0.0
    @AppStorage("lastBackupReminderAt") private var lastBackupReminderAt = 0.0
    @ProtectedSetting("lastLibraryBackupFile") private var lastLibraryBackupFile = ""
    @AppStorage("lastLibraryBackupDigest") private var lastLibraryBackupDigest = ""
    @ProtectedSetting("lastLibraryBackupError") private var lastLibraryBackupError = ""

    private var backupStatusIcon: String {
        if backupRunning { return "arrow.triangle.2.circlepath" }
        if !lastLibraryBackupError.isEmpty { return "exclamationmark.circle" }
        return "externaldrive"
    }

    private var selectedProject: Project? {
        guard case .project(let id) = selection else { return nil }
        return projects.first { $0.id == id }
    }

    private var selectedFolder: (client: Client, folder: ProjectFolder)? {
        guard case .folder(let clientID, let folderID) = selection,
              let client = clients.first(where: { $0.id == clientID }),
              let folder = client.folder(folderID) else { return nil }
        return (client, folder)
    }

    private var libraryContent: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            libraryDetail
        }
        .environment(\.usageFeatures, features)
        .background(BackupWindow(allowClose: confirmClose))
        .focusedSceneValue(\.saveProjectEdits, saveProjectEditsAction)
        .focusedSceneValue(\.libraryMenu, database == nil ? nil : menuActions)
        .focusedSceneValue(\.backUpNow, database != nil && !backupRunning ? { automaticBackup(force: true) } : nil)
        .toolbar { libraryToolbar }
    }

    var body: some View {
        libraryContent
        .onAppear {
            if database == nil { attempt { try load() } }
            openRequestedBackup()
            openRequestedReset()
            presentOnboardingIfNeeded()
        }
        .onChange(of: projectAutosave) { _, enabled in
            guard enabled else { return }
            do { try saveDrafts() }
            catch {
                projectAutosave = false
                message = error.localizedDescription
            }
        }
        .onChange(of: libraryBackupRequested) { _, _ in openRequestedBackup() }
        .onChange(of: libraryResetRequested) { _, _ in openRequestedReset() }
        .onChange(of: onboardingRequested) { _, _ in presentOnboardingIfNeeded() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) }
                catch { break }
                try? refreshExternalProjects()
                await refreshBackupFreshness()
            }
        }
        .task {
            if database == nil { attempt { try load() } }
            while !Task.isCancelled {
                automaticBackup()
                if automaticCloudSync { synchronize() }
                do { try await Task.sleep(for: .seconds(300)) }
                catch { break }
            }
        }
        .sheet(isPresented: $showingBackup, onDismiss: {
            if selectingRestoreAfterBackup {
                selectingRestoreAfterBackup = false
                chooseRestore()
            }
        }) {
            backupSheet.environment(\.locale, locale)
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: { hasCompletedOnboarding = true }) {
            OnboardingView { startProject in
                hasCompletedOnboarding = true
                showingOnboarding = false
                if startProject { newProject() }
            }
        }
        .sheet(item: $newClientDraft) { client in
            ClientEditor(client: client, save: updateClient).environment(\.locale, locale)
        }
        .sheet(item: $newFreelancerDraft) { person in
            FreelancerEditor(person: person, save: saveFreelancer).environment(\.locale, locale)
        }
        .sheet(item: $folderRequest) { request in
            ProjectFolderEditor(request: request, clients: clients.filter { $0.archivedAt == nil || $0.id == request.clientID },
                                save: saveFolder)
                .environment(\.locale, locale)
        }
        .sheet(isPresented: $showingReset, onDismiss: {
            if reopenSetupAfterReset {
                reopenSetupAfterReset = false
                beginFreshSetup()
            }
        }) {
            LibraryResetView(reset: resetLocalLibrary)
                .environment(\.locale, locale)
        }
        .onChange(of: automaticCloudSync) { _, enabled in
            if enabled { synchronize() }
        }
        .confirmationDialog("Restore this library?", isPresented: Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        ), titleVisibility: .visible) {
            Button("Replace library", role: .destructive) {
                guard let backup = pendingRestore else { return }
                pendingRestore = nil
                attempt { try restore(backup) }
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let backup = pendingRestore {
                let counts = Text("Projects: \(backup.library.projects.count) · Clients: \(backup.library.clients?.count ?? 0)")
                let recovery = Text("Coool PM first creates a recovery copy of this Mac’s library.")
                if let settings = backup.settings {
                    let contents = Text("This archive also restores your business profile, rates, and preferences. Custom Word templates: \(settings.templates.count).")
                    counts + Text("\n\n") + contents + Text("\n\n") + recovery
                } else {
                    let contents = Text("This older archive contains library records only. This Mac’s settings and templates will be kept.")
                    counts + Text("\n\n") + contents + Text("\n\n") + recovery
                }
            }
        }
        .onChange(of: selection) { _, value in
            guard let value else { return }
            destination = .project
            if case .project(let id) = value { lastProject = id.uuidString }
        }
        .onChange(of: showArchivedProjects) { _, showing in
            if !showing && selectedProject?.estimate.archivedAt != nil { selection = nil }
        }
        .confirmationDialog("Discard unsaved project edits?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard project edits", role: .destructive) { projectDrafts.removeAll() }
        }
        .alert("Library action failed", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private var saveProjectEditsAction: (() -> Void)? {
        guard !projectDrafts.isEmpty else { return nil }
        return { attempt { try saveDrafts() } }
    }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if database != nil {
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(projectAutosave ? Color.green : Color.orange)
                        Text(projectAutosave ? "Autosave on" : "Autosave off")
                    }
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .help(projectAutosave ? "Edits save automatically to the library on this Mac." : "Save project edits with Command-S.")
                    if !projectAutosave {
                        Button("Save project edits") { attempt { try saveDrafts() } }
                            .disabled(projectDrafts.isEmpty)

                    }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingBackup = true } label: {
                Label("Backups", systemImage: backupStatusIcon)
                    .labelStyle(.titleAndIcon).font(.caption)
            }.help("Manage separate recovery copies of this library.")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Settings", systemImage: "gearshape") { openWindow(id: BusinessSettingsWindow.id) }
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 4) {
                sidebarDestination("Business overview", icon: "chart.bar.xaxis", target: .business)
                sidebarDestination("Contacts hub", icon: "person.crop.rectangle", target: .contacts)
            }
            .padding(.horizontal, 12)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search projects", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12)

            ProjectLibrarySidebar(clients: clients, projects: projects, search: search, showEmptyClients: showEmptyClients, showArchived: showArchivedProjects,
                                  selection: $selection, newProject: newProject(clientID:folderID:),
                                  editFolder: { folderRequest = $0 }, move: moveProject, archive: setProjectArchived, duplicate: duplicateProject,
                                  askToDelete: { projectToDelete = $0 })
                .confirmationDialog("Delete this project permanently?", isPresented: Binding(
                    get: { projectToDelete != nil },
                    set: { if !$0 { projectToDelete = nil } }
                ), titleVisibility: .visible, presenting: projectToDelete) { project in
                    Button("Delete project", role: .destructive) { attempt { try deleteProject(project.id) } }
                    Button("Cancel", role: .cancel) { projectToDelete = nil }
                } message: { project in
                    Text("Deleting \(project.estimate.displayTitle(in: locale)) removes its documents, invoices, and costs from the library and its reports.")
                }
        }
        .navigationTitle("Projects")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            Button("New project", systemImage: "plus", action: newProject)
                .disabled(database == nil)
        }
    }

    private var menuActions: LibraryMenuActions {
        LibraryMenuActions(newProject: newProject, newClient: newClient,
                           newFreelancer: features.teamPlanning ? newFreelancer : nil,
                           newFolder: clients.contains { $0.archivedAt == nil } ? newFolder : nil,
                           duplicate: selectedProject.map { project in { duplicateProject(project.id) } },
                           discard: projectDrafts.isEmpty ? nil : { confirmingDiscard = true },
                           projects: showProjects, business: { selection = nil; destination = .business },
                           clients: { showContacts(.clients) },
                           freelancers: features.teamPlanning ? { showContacts(.freelancers) } : nil,
                           archived: $showArchivedProjects, emptyClients: $showEmptyClients,
                           backups: { showingBackup = true },
                           saveBackup: backupRunning ? nil : saveBackup,
                           restore: backupRunning || cloudRunning ? nil : chooseRestore)
    }

    private func showProjects() {
        if let previous = projects.first(where: { $0.id.uuidString == lastProject && (showArchivedProjects || $0.estimate.archivedAt == nil) }) {
            selection = .project(previous.id)
        }
        destination = .project
    }

    private func showContacts(_ area: ContactArea) {
        selection = nil
        contactArea = area
        destination = .contacts
    }

    private func newClient() {
        attempt {
            guard let database else { return }
            let number = try database.nextClientNumber()
            showContacts(.clients)
            newClientDraft = Client(number: number, name: "", terms: BusinessProfile.load().newClientTerms)
        }
    }

    private func newFreelancer() {
        showContacts(.freelancers)
        newFreelancerDraft = Freelancer()
    }

    private func saveFreelancer(_ person: Freelancer) throws {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        try database.saveFreelancer(person)
        freelancers = try database.freelancers()
    }

    private func duplicateProject(_ id: UUID) {
        attempt {
            try refreshExternalProjects()
            guard let database, let project = projects.first(where: { $0.id == id }) else { return }
            let source = projectDrafts[id]?.estimate ?? project.estimate
            let title = source.displayTitle(in: locale)
            let format = AppLanguage.text("%@ (Copy)", fallback: "%@ (Copy)", locale: locale)
            let copy = source.duplicateCalculation(titled: String(format: format, title))
            let stored = try database.insert(Project(id: UUID(), estimate: copy))
            projects.append(stored)
            openProject(stored.id)
        }
    }

    @ViewBuilder
    private var libraryDetail: some View {
        if destination == .business {
            BusinessOverviewView(projects: projects)
        } else if destination == .contacts {
            ContactsHub(showFreelancers: features.teamPlanning, selection: $contactArea) {
                ClientDirectory(clients: clients, projects: projects, nextNumber: {
                    guard let database else { throw LibraryError(description: "Library unavailable.") }
                    return try database.nextClientNumber()
                }, save: updateClient, delete: deleteClient, openProject: openProject)
            } freelancers: {
                FreelancerDirectory(people: freelancers, save: saveFreelancer, delete: { id in
                    guard let database else { throw LibraryError(description: "Library unavailable.") }
                    try database.deleteFreelancer(id: id)
                    freelancers = try database.freelancers()
                })
            }
        } else if let selectedFolder {
            BusinessOverviewView(projects: selectedFolder.folder.projects(in: projects, clientID: selectedFolder.client.id),
                                 folder: selectedFolder.folder, folderClient: selectedFolder.client.name)
                .id(selectedFolder.folder.id)
        } else if let project = selectedProject {
            SheetView(estimate: Binding(get: {
                projectDrafts[project.id]?.estimate ?? projects.first { $0.id == project.id }?.estimate ?? project.estimate
            }, set: { updated in
                editProject(Project(id: project.id, estimate: updated))
            }), clients: clients, assignProjectNumber: {
                assignProjectNumber(to: project.id)
            }, saveDocuments: { updated in
                try commitProject(Project(id: project.id, estimate: updated))
            }, recordInvoice: { number, make in
                try recordInvoice(projectID: project.id, preferredNumber: number, make: make)
            }, referenceProjects: projects.filter { $0.id != project.id })
            .environment(\.usageFeatures, features.resolving((projectDrafts[project.id]?.estimate ?? project.estimate).featureOverrides))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ProjectFeaturesView(overrides: Binding(get: {
                    (projectDrafts[project.id]?.estimate ?? project.estimate).featureOverrides
                }, set: { value in
                    guard var current = projects.first(where: { $0.id == project.id }) else { return }
                    current.estimate = projectDrafts[project.id]?.estimate ?? current.estimate
                    current.estimate.featureOverrides = value
                    editProject(current)
                }), defaults: features)
                .padding(.horizontal, SheetView.horizontalInset - 16)
                .background(.bar)
            }.id(project.id)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "folder").font(.largeTitle).foregroundStyle(.secondary)
                Text(projects.isEmpty ? "Your project library" : "Select a project").font(.title2.bold())
                Button("Create project", action: newProject).buttonStyle(.borderedProminent).disabled(database == nil)
            }.frame(minWidth: 500, minHeight: 400)
        }
    }

    private func sidebarDestination(_ title: LocalizedStringKey, icon: String, target: Destination) -> some View {
        Button {
            selection = nil
            destination = target
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(destination == target ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(destination == target ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(destination == target ? .isSelected : [])
    }

    private func presentOnboardingIfNeeded() {
        guard database != nil else { return }
        if onboardingRequested {
            onboardingRequested = false
            showingOnboarding = true
        } else if !hasCompletedOnboarding {
            let existingSetup = !projects.isEmpty || !clients.isEmpty || !rateLibraryData.isEmpty ||
                BusinessProfile.load() != BusinessProfile()
            if existingSetup { hasCompletedOnboarding = true }
            else { showingOnboarding = true }
        }
    }

    private func openRequestedBackup() {
        guard libraryBackupRequested else { return }
        libraryBackupRequested = false
        showingBackup = true
    }

    private func openRequestedReset() {
        guard database != nil, libraryResetRequested else { return }
        libraryResetRequested = false
        guard projectDrafts.isEmpty else { message = LibraryError(description: "Save or discard your project edits first.").localizedDescription; return }
        guard !backupRunning && !cloudRunning else {
            message = LibraryError(description: "Wait for backup or sync to finish before resetting.").localizedDescription
            return
        }
        showingReset = true
    }

    private func updateClient(_ client: Client) throws {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        try database.updateClient(client)
        let library = try database.archive()
        clients = library.clients ?? []
        freelancers = library.freelancers ?? []
        projects = library.projects
    }

    private func deleteClient(_ id: UUID) throws {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        try database.deleteClient(id: id)
        let library = try database.archive()
        clients = library.clients ?? []
        freelancers = library.freelancers ?? []
        projects = library.projects
    }

    private func resetLocalLibrary(_ scope: LibraryResetView.Scope) throws {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        guard projectDrafts.isEmpty else { throw LibraryError(description: "Save or discard your project edits first.") }
        guard !backupRunning && !cloudRunning else {
            throw LibraryError(description: "Wait for backup or sync to finish before resetting.")
        }
        let version = try database.changeVersion()
        let date = Date.now
        let recovery = try captureBackup(at: date)
        let folder = try LibraryBackup.localBackupFolder(creating: true)
        let file = folder.appendingPathComponent(LibraryBackup.suggestedName(at: date, versioned: true))
        let digest = try CloudLibrarySync.digest(of: recovery)
        try recovery.write(to: file)
        if scope == .app {
            let defaults = UserDefaults.standard
            let domain = LibraryKey.applicationID
            let previousPreferences = defaults.persistentDomain(forName: domain)
            defaults.set(false, forKey: "mcpEnabled")
            defaults.synchronize()
            do {
                try LibraryBackup.Settings(businessProfile: BusinessProfile(), appLanguage: AppLanguage.system.rawValue,
                                           templates: [:]).install()
                try database.detachForFreshSetup(at: ProjectDatabase.libraryURL(), ifVersionIs: version,
                                                  complete: LibraryKey.clearLocalSetup)
            } catch {
                try? recovery.settings?.install()
                if let previousPreferences { defaults.setPersistentDomain(previousPreferences, forName: domain) }
                throw error
            }
            self.database = nil
            reopenSetupAfterReset = true
        } else {
            try database.resetLibrary(ifVersionIs: version)
            automaticCloudSync = false
            cloud.forgetLocalAssociation()
            cloudConflict = nil
            syncError = ""
            lastLibrarySync = 0
            lastProject = ""
            rememberBackup(at: file, date: date, digest: digest)
            NotificationCenter.default.post(name: .cooolLibraryDidRestore, object: nil)
        }
        projects = []
        clients = []
        freelancers = []
        search = ""
        selection = nil
        destination = .project
    }

    private var backupSheet: some View {
        LibraryBackupView(databaseReady: database != nil, databaseLocation: (try? ProjectDatabase.libraryURL().path) ?? "",
                          freshness: backupFreshness, folderName: automaticBackupFolder, lastBackup: lastLibraryBackup,
                          lastBackupFile: lastLibraryBackupFile, lastError: lastLibraryBackupError,
                          isBackingUp: backupRunning, chooseFolder: chooseAutomaticFolder,
                          chooseLocalFolder: { attempt { try setAutomaticFolder(LibraryBackup.localBackupFolder(creating: true)) } },
                          stopAutomatic: {
                              automaticBackupBookmark = Data()
                              automaticBackupFolder = ""
                              lastLibraryBackupError = ""
                          }, backUp: { automaticBackup(force: true) }, saveAs: saveBackup,
                          restore: { selectingRestoreAfterBackup = true },
                          cloudConfigured: CloudLibrarySync.isConfigured, cloudRunning: cloudRunning,
                          lastSync: lastLibrarySync, syncError: syncError, conflict: cloudConflict,
                          automaticSync: $automaticCloudSync, sync: { synchronize() },
                          resolveConflict: { choice in synchronize(choice) })

    }

    private func load() throws {
        let db = try ProjectDatabase(url: ProjectDatabase.libraryURL())
        libraryVersion = try db.changeVersion()
        let library = try db.archive()
        clients = library.clients ?? []
        freelancers = library.freelancers ?? []
        projects = library.projects
        database = db
        if lastLibraryBackup == 0 && backupReminderStartedAt == 0 { backupReminderStartedAt = Date.now.timeIntervalSince1970 }
        let visible = projects.filter { showArchivedProjects || $0.estimate.archivedAt == nil }
        selection = (visible.first { $0.id.uuidString == lastProject } ?? visible.first).map { .project($0.id) }
    }

    private func refreshExternalProjects() throws {
        guard let database else { return }
        let version = try database.changeVersion()
        guard version != libraryVersion else { return }
        let library = try database.archive()
        clients = library.clients ?? []
        freelancers = library.freelancers ?? []
        projects = library.projects
        libraryVersion = version
        switch selection {
        case .project:
            if selectedProject == nil || (!showArchivedProjects && selectedProject?.estimate.archivedAt != nil) { selection = nil }
        case .folder:
            if selectedFolder == nil { selection = nil }
        case nil:
            break
        }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }

    private func matchesBaseline(_ estimate: Estimate, _ baseline: Estimate) throws -> Bool {
        guard estimate.completedCostLines == baseline.completedCostLines,
              estimate.commitments == baseline.commitments else { return false }
        var current = estimate
        var original = baseline
        // Both fields encode as unordered arrays. Compare them structurally first.
        current.completedCostLines = nil
        original.completedCostLines = nil
        current.commitments = nil
        original.commitments = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(current) == encoder.encode(original)
    }

    private func editProject(_ updated: Project) {
        guard !projectAutosave else { attempt { try saveProject(updated) }; return }
        guard let saved = projects.first(where: { $0.id == updated.id }) else { return }
        let baseline = projectDrafts[updated.id]?.baseline ?? saved.estimate
        projectDrafts[updated.id] = ProjectDraft(baseline: baseline, estimate: updated.estimate)
    }

    private func commitProject(_ updated: Project) throws {
        if let draft = projectDrafts[updated.id] {
            try refreshExternalProjects()
            guard let saved = projects.first(where: { $0.id == updated.id }),
                  try matchesBaseline(saved.estimate, draft.baseline) else {
                throw LibraryError(description: "This project changed outside the editor. Review or discard the unsaved edits before continuing.")
            }
        }
        try saveProject(updated)
        projectDrafts.removeValue(forKey: updated.id)
    }

    private func saveDrafts() throws {
        try refreshExternalProjects()
        for (id, draft) in projectDrafts {
            try commitProject(Project(id: id, estimate: draft.estimate))
        }
    }

    private func saveProject(_ updated: Project) throws {
        guard let database, let index = projects.firstIndex(where: { $0.id == updated.id }) else {
            throw LibraryError(description: "The project is unavailable.")
        }
        var project = updated
        let client = clients.first { $0.id == project.estimate.clientID }
        if client?.folder(project.estimate.folderID) == nil { project.estimate.folderID = nil }
        project.estimate.preserveApprovedCalculation(from: projects[index].estimate)
        do {
            projects[index] = try database.save(project, ifVersionIs: libraryVersion)
        } catch {
            try? refreshExternalProjects()
            throw error
        }
    }

    private func openProject(_ id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        if project.estimate.archivedAt != nil { showArchivedProjects = true }
        search = ""
        selection = .project(id)
        destination = .project
    }

    private func newFolder() {
        let contextID = selectedFolder?.client.id ?? selectedProject?.estimate.clientID
        let clientID = clients.first { $0.id == contextID && $0.archivedAt == nil }?.id
        folderRequest = ProjectFolderRequest(clientID: clientID)
    }

    private func saveFolder(clientID: UUID, folder: ProjectFolder) throws {
        try refreshExternalProjects()
        guard let database, var client = clients.first(where: { $0.id == clientID }) else {
            throw LibraryError(description: "Select a client.")
        }
        try client.saveFolder(folder)
        try database.saveClient(client)
        clients = try database.clients()
        search = ""
        selection = .folder(clientID: clientID, folderID: folder.id)
        destination = .project
    }

    private func moveProject(_ id: UUID, _ folderID: UUID?) {
        guard var project = projects.first(where: { $0.id == id }),
              let client = clients.first(where: { $0.id == project.estimate.clientID }),
              folderID == nil || client.folder(folderID) != nil else { return }
        project.estimate = projectDrafts[id]?.estimate ?? project.estimate
        project.estimate.folderID = folderID
        attempt { try commitProject(project) }
    }

    private func setProjectArchived(_ id: UUID, _ archived: Bool) {
        guard var project = projects.first(where: { $0.id == id }) else { return }
        project.estimate = projectDrafts[id]?.estimate ?? project.estimate
        project.estimate.archivedAt = archived ? .now : nil
        attempt { try commitProject(project) }
        if archived && !showArchivedProjects && selectedProject?.estimate.archivedAt != nil {
            selection = nil
        }
    }

    private func deleteProject(_ id: UUID) throws {
        guard let database else { return }
        try database.deleteProject(id: id)
        projectDrafts.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
        if selection == .project(id) { selection = nil }
        if lastProject == id.uuidString { lastProject = "" }
        projectToDelete = nil
    }

    private func newProject() {
        let folder = selectedFolder
        newProject(clientID: folder?.client.id, folderID: folder?.folder.id)
    }

    private func newProject(clientID: UUID?, folderID: UUID?) {
        guard let database else { return }
        var estimate = Estimate()
        if let client = clients.first(where: { $0.id == clientID && $0.archivedAt == nil }) {
            estimate.clientID = client.id
            estimate.client = client.name
            estimate.clientNumber = client.number
            estimate.clientRebatePercent = client.rebatePercent
            estimate.folderID = client.folder(folderID)?.id
        }
        let storedRates = (try? VaultPreferences.data(DayRateLibrary.storageKey)) ?? rateLibraryData
        if let preset = DayRateLibrary(data: storedRates).defaultSchedule { estimate.applyDayRates(preset) }
        let project = Project(id: UUID(), estimate: estimate)
        attempt {
            projects.append(try database.insert(project))
            search = ""
            selection = .project(project.id)
            destination = .project
        }
    }

    private func assignProjectNumber(to id: UUID) {
        attempt {
            if let draft = projectDrafts[id] { try commitProject(Project(id: id, estimate: draft.estimate)) }
            guard let database, let index = projects.firstIndex(where: { $0.id == id }) else {
                throw LibraryError(description: "The project is unavailable.")
            }
            do {
                projects[index] = try database.assignProjectNumber(to: id, ifVersionIs: libraryVersion)
            } catch {
                try? refreshExternalProjects()
                throw error
            }
        }
    }

    private func recordInvoice(projectID: UUID, preferredNumber: String?, make: (String, Estimate) throws -> IssuedInvoice) throws {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        if let draft = projectDrafts[projectID] { try commitProject(Project(id: projectID, estimate: draft.estimate)) }
        let stored = try database.issueInvoice(projectID: projectID, preferredNumber: preferredNumber,
                                               ifVersionIs: libraryVersion, make: make)
        if let index = projects.firstIndex(where: { $0.id == stored.id }) { projects[index] = stored }
    }

    private func saveBackup() {
        guard database != nil, !backupRunning else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: LibraryBackup.filenameExtension) ?? .data]
        panel.nameFieldStringValue = LibraryBackup.suggestedName(at: .now)
        if panel.runModal() == .OK, let url = panel.url {
            startBackup(to: url, accessing: url, at: .now, automatic: false)
        }
    }

    private func chooseAutomaticFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let folder = panel.url {
            attempt { try setAutomaticFolder(folder) }
        }
    }

    private func setAutomaticFolder(_ folder: URL) throws {
        automaticBackupBookmark = try AutomaticBackupLocation(folder).bookmark
        automaticBackupFolder = folder.path
        automaticBackup(force: true)
    }

    private func automaticBackup(force: Bool = false) {
        let hasAutomaticFolder = !automaticBackupBookmark.isEmpty
        guard database != nil, !backupRunning, force || hasAutomaticFolder else { return }
        let now = Date.now
        guard force || lastAutomaticBackup == 0 ||
                !Calendar.current.isDate(now, inSameDayAs: Date(timeIntervalSince1970: lastAutomaticBackup)) else { return }
        do {
            let folder = try hasAutomaticFolder
                ? AutomaticBackupLocation(bookmark: automaticBackupBookmark).resolve()
                : LibraryBackup.localBackupFolder(creating: true)
            let file = folder.appendingPathComponent(LibraryBackup.suggestedName(at: now, versioned: true))
            startBackup(to: file, accessing: folder, at: now, automatic: hasAutomaticFolder)
        } catch { lastLibraryBackupError = error.localizedDescription }
    }

    private func startBackup(to file: URL, accessing scope: URL, at date: Date, automatic: Bool) {
        guard !backupRunning else { return }
        backupRunning = true
        lastLibraryBackupError = ""
        Task { @MainActor in
            defer { backupRunning = false }
            do {
                let digest = try await Task.detached(priority: .utility) {
                    let accessing = scope.startAccessingSecurityScopedResource()
                    defer { if accessing { scope.stopAccessingSecurityScopedResource() } }
                    let database = try ProjectDatabase(url: ProjectDatabase.libraryURL(), readOnly: true)
                    let archive = try LibraryBackup.capture(library: database.archive(), at: date)
                    let digest = try CloudLibrarySync.digest(of: archive)
                    try archive.write(to: file)
                    return digest
                }.value
                if automatic { lastAutomaticBackup = date.timeIntervalSince1970 }
                rememberBackup(at: file, date: date, digest: digest)
                await refreshBackupFreshness()
            } catch { lastLibraryBackupError = error.localizedDescription }
        }
    }

    private func rememberBackup(at url: URL, date: Date, digest: String) {
        guard date.timeIntervalSince1970 >= lastLibraryBackup else { return }
        lastLibraryBackup = date.timeIntervalSince1970
        lastLibraryBackupFile = url.path
        lastLibraryBackupDigest = digest
        lastLibraryBackupError = ""
        lastFreshnessProbe = nil
        backupFreshness = .checking
    }

    // Most polls need only cheap revision and file metadata checks. Re-hash the archive when an input changes.
    private func backupProbe() -> Int {
        var hash = Hasher()
        hash.combine(database?.localChangeCount)
        hash.combine(libraryVersion)
        hash.combine(lastLibraryBackup)
        hash.combine(lastLibraryBackupDigest)
        hash.combine(lastLibraryBackupFile)
        hash.combine(automaticBackupBookmark)
        let defaults = UserDefaults.standard
        for key in ["appLanguage", "appAppearance", "documentLanguage", "businessProfile", DayRateLibrary.storageKey,
                    BusinessMonthlyGoals.storageKey, PricingCatalog.storageKey, BackupReminder.storageKey, "showClientsWithoutActiveProjects",
                    "showArchivedProjects", "hasCompletedOnboarding", "localAIEnabled", "localAIModelID", "localAIIdlePolicy", "xrechnungJavaPath", "xrechnungRulesPath", "xrechnungValidatorPath"] {
            if let sealed = defaults.data(forKey: key) {
                // Every encrypted preference write has a fresh nonce near the start of the envelope.
                hash.combine(sealed.prefix(64))
                hash.combine(sealed.count)
            } else {
                hash.combine((defaults.object(forKey: key) as? NSObject)?.hash)
            }
        }
        let fm = FileManager.default
        let templates = LibraryBackup.Settings.templateFolder
        let files = (try? fm.contentsOfDirectory(at: templates, includingPropertiesForKeys: nil)) ?? []
        for file in (files.sorted { $0.path < $1.path } + [URL(fileURLWithPath: lastLibraryBackupFile)]) {
            let attributes = try? fm.attributesOfItem(atPath: file.path)
            hash.combine(file.lastPathComponent)
            hash.combine(attributes?[.modificationDate] as? Date)
            hash.combine(attributes?[.size] as? Int)
        }
        return hash.finalize()
    }

    private func confirmClose() -> Bool {
        guard database != nil else { return true }
        func local(_ text: String) -> String { AppLanguage.text(text, fallback: text, locale: locale) }
        do {
            if backupRunning || cloudRunning {
                throw LibraryError(description: "A backup or sync is in progress. Try closing again when it finishes.")
            }
            if !projectDrafts.isEmpty {
                let alert = NSAlert()
                alert.messageText = local("Save project edits before closing?")
                alert.addButton(withTitle: local("Save project edits"))
                alert.addButton(withTitle: local("Cancel")).keyEquivalent = "\u{1b}"
                alert.addButton(withTitle: local("Discard project edits"))
                switch alert.runModal() {
                case .alertFirstButtonReturn: try saveDrafts()
                case .alertThirdButtonReturn: projectDrafts.removeAll()
                default: return false
                }
            }
            guard BackupReminder.isDue(days: backupReminderDays, lastBackup: lastLibraryBackup,
                                       lastReminder: lastBackupReminderAt, started: backupReminderStartedAt, now: .now) else { return true }
            if lastLibraryBackup == 0 && !hasCompletedOnboarding && projects.isEmpty && clients.isEmpty { return true }
            let snapshot = try captureBackup()
            let digest = try CloudLibrarySync.digest(of: snapshot)
            let folder = try? AutomaticBackupLocation(bookmark: automaticBackupBookmark).resolve()
            let scoped = folder?.startAccessingSecurityScopedResource() == true
            defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
            if digest == lastLibraryBackupDigest && FileManager.default.isReadableFile(atPath: lastLibraryBackupFile) { return true }
            let alert = NSAlert()
            alert.messageText = local("Create a recovery backup before closing?")
            alert.informativeText = local("Your edits are already saved on this Mac. You can close now or create a separate encrypted recovery copy first.")
            alert.addButton(withTitle: local("Close"))
            alert.addButton(withTitle: local("Create Backup and Close"))
            alert.addButton(withTitle: local("Cancel")).keyEquivalent = "\u{1b}"
            let choice = alert.runModal()
            lastBackupReminderAt = Date.now.timeIntervalSince1970
            switch choice {
            case .alertFirstButtonReturn: return true
            case .alertSecondButtonReturn:
                let destination = try automaticBackupBookmark.isEmpty
                    ? LibraryBackup.localBackupFolder(creating: true)
                    : AutomaticBackupLocation(bookmark: automaticBackupBookmark).resolve()
                let date = Date()
                let file = destination.appendingPathComponent(LibraryBackup.suggestedName(at: date, versioned: true))
                try snapshot.write(to: file)
                rememberBackup(at: file, date: date, digest: digest)
                return true
            default: return false
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }

    private func refreshBackupFreshness() async {
        let probe = backupProbe()
        guard lastFreshnessProbe != probe else { return }
        guard lastLibraryBackup > 0 else {
            backupFreshness = .none
            lastFreshnessProbe = probe
            return
        }
        guard database != nil, !lastLibraryBackupFile.isEmpty else {
            backupFreshness = .unverified
            lastFreshnessProbe = probe
            return
        }
        if lastFreshnessProbe == nil { backupFreshness = .checking }
        let backupFile = lastLibraryBackupFile
        let savedDigest = lastLibraryBackupDigest
        let bookmark = automaticBackupBookmark
        let freshness = await Task.detached(priority: .utility) { () -> LibraryBackupView.Freshness in
            let permittedFolder = bookmark.isEmpty ? nil : try? AutomaticBackupLocation(bookmark: bookmark).resolve()
            let scoped = permittedFolder?.startAccessingSecurityScopedResource() == true
            defer { if scoped { permittedFolder?.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.isReadableFile(atPath: backupFile) else { return .unavailable }
            guard !savedDigest.isEmpty else { return .unverified }
            do {
                let database = try ProjectDatabase(url: ProjectDatabase.libraryURL(), readOnly: true)
                let snapshot = try LibraryBackup.capture(library: database.archive())
                let currentDigest = try CloudLibrarySync.digest(of: snapshot)
                return savedDigest == currentDigest ? .current : .changed
            } catch { return .unverified }
        }.value
        guard !Task.isCancelled, probe == backupProbe() else { return }
        lastFreshnessProbe = probe
        backupFreshness = freshness
    }

    private func captureBackup(at date: Date = .now) throws -> LibraryBackup {
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        return try LibraryBackup.capture(library: database.archive(), at: date)
    }

    private func synchronize(_ choice: CloudLibrarySync.ConflictChoice? = nil) {
        guard CloudLibrarySync.isConfigured, database != nil, !cloudRunning, pendingRestore == nil else { return }
        guard choice != nil || cloudConflict == nil else { return }
        cloudRunning = true
        syncError = ""
        Task { @MainActor in
            defer { cloudRunning = false }
            do {
                let local = try captureBackup()
                let outcome: CloudLibrarySync.Outcome
                if let choice, let conflict = cloudConflict {
                    outcome = try await cloud.resolve(conflict, using: choice, local: local)
                } else {
                    outcome = try await cloud.synchronize(local: local)
                }
                switch outcome {
                case .upToDate, .uploaded:
                    cloudConflict = nil
                    lastLibrarySync = Date.now.timeIntervalSince1970
                case .download(let download):
                    guard let database else { throw LibraryError(description: "Library unavailable.") }
                    let version = try database.changeVersion()
                    try cloud.checkLocal(captureBackup(), for: download)
                    try restore(download.backup, ifVersionIs: version)
                    cloud.didApply(download)
                    cloudConflict = nil
                    lastLibrarySync = Date.now.timeIntervalSince1970
                case .conflict(let conflict):
                    cloudConflict = conflict
                    showingBackup = true
                }
            } catch {
                cloudConflict = nil
                syncError = error.localizedDescription
            }
        }
    }

    private func chooseRestore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: LibraryBackup.filenameExtension) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attempt { pendingRestore = try readBackupForRestore(Data(contentsOf: url)) }
    }

    private func restore(_ backup: LibraryBackup, ifVersionIs expectedVersion: Int64? = nil) throws {
        guard projectDrafts.isEmpty else { throw LibraryError(description: "Save or discard your project edits first.") }
        guard let database else { throw LibraryError(description: "Library unavailable.") }
        try validate(backup.library.projects)
        let version = try expectedVersion ?? database.changeVersion()
        let recoveryFolder = try LibraryBackup.localBackupFolder(creating: true)
        let recoveryFile = recoveryFolder.appendingPathComponent(LibraryBackup.suggestedName(at: .now, versioned: true))
        let recovery = try captureBackup()
        let recoveryDigest = try CloudLibrarySync.digest(of: recovery)
        try recovery.write(to: recoveryFile)
        rememberBackup(at: recoveryFile, date: recovery.savedAt ?? .now, digest: recoveryDigest)
        let previous = recovery.settings
        do {
            try backup.settings?.install()
            try database.replaceLibrary(backup.library, ifVersionIs: version)
        } catch {
            if backup.settings != nil { try? previous?.install() }
            throw error
        }
        clients = try database.clients()
        freelancers = try database.freelancers()
        projects = try database.all()
        search = ""
        destination = .project
        selection = projects.first { showArchivedProjects || $0.estimate.archivedAt == nil }.map { .project($0.id) }
        NotificationCenter.default.post(name: .cooolLibraryDidRestore, object: nil)
    }

    private func validate(_ incoming: [Project]) throws {
        for project in incoming {
            guard project.estimate.phases.flatMap(\.entries).allSatisfy({ $0.quantity >= 0 && $0.rate >= 0 && $0.cost >= 0 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }
}

private struct SaveProjectEditsKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var saveProjectEdits: (() -> Void)? {
        get { self[SaveProjectEditsKey.self] }
        set { self[SaveProjectEditsKey.self] = newValue }
    }
}

struct ProjectSaveCommands: Commands {
    let locale: Locale
    @FocusedValue(\.saveProjectEdits) private var saveProjectEdits

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button(AppLanguage.text("Save project edits", fallback: "Save project edits", locale: locale)) {
                saveProjectEdits?()
            }
            .keyboardShortcut("s")
            .disabled(saveProjectEdits == nil)
        }
    }
}
