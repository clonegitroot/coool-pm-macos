import SwiftUI

struct LibraryMenuActions {
    let newProject: () -> Void
    let newClient: () -> Void
    let newFreelancer: (() -> Void)?
    let newFolder: (() -> Void)?
    let duplicate: (() -> Void)?
    let discard: (() -> Void)?
    let projects: () -> Void
    let business: () -> Void
    let clients: () -> Void
    let freelancers: (() -> Void)?
    let archived: Binding<Bool>
    let emptyClients: Binding<Bool>
    let backups: () -> Void
    let saveBackup: (() -> Void)?
    let restore: (() -> Void)?
}

struct ProjectMenuActions {
    let showTab: (ProjectTab) -> Void
    let controlling: Bool
    let createDocument: () -> Void
    let localAI: (() -> Void)?
}

private struct ProjectMenuKey: FocusedValueKey { typealias Value = ProjectMenuActions }

private struct LibraryMenuKey: FocusedValueKey { typealias Value = LibraryMenuActions }

extension FocusedValues {
    var projectMenu: ProjectMenuActions? {
        get { self[ProjectMenuKey.self] }
        set { self[ProjectMenuKey.self] = newValue }
    }

    var libraryMenu: LibraryMenuActions? {
        get { self[LibraryMenuKey.self] }
        set { self[LibraryMenuKey.self] = newValue }
    }
}

struct LibraryCommands: Commands {
    let locale: Locale
    @FocusedValue(\.libraryMenu) private var menu
    @FocusedValue(\.projectMenu) private var project

    var body: some Commands {
        CommandGroup(after: .newItem) {
            command("New project", menu?.newProject).keyboardShortcut("n")
            command("New client…", menu?.newClient).keyboardShortcut("n", modifiers: [.command, .shift])
            command("New freelancer…", menu?.newFreelancer)
            command("New folder…", menu?.newFolder)
            Divider()
            command("Duplicate project", menu?.duplicate).keyboardShortcut("d")
            command("Create document…", project?.createDocument)
        }
        CommandGroup(after: .saveItem) {
            command("Discard project edits…", menu?.discard)
            Divider()
            command("Backups & Recovery…", menu?.backups)
            command("Create Backup Elsewhere…", menu?.saveBackup)
            command("Restore from Backup…", menu?.restore)
        }
        CommandGroup(after: .sidebar) {
            command("Projects", menu?.projects).keyboardShortcut("1")
            command("Business overview", menu?.business).keyboardShortcut("2")
            command("Clients", menu?.clients).keyboardShortcut("3")
            command("Freelancers", menu?.freelancers).keyboardShortcut("4")
            Divider()
            filter("Show archived projects", menu?.archived)
            filter("Show clients without active projects", menu?.emptyClients)
            Divider()
            ForEach(ProjectTab.allCases, id: \.self) { tab in
                Button { project?.showTab(tab) } label: { Text(verbatim: title(tab.rawValue)) }
                    .disabled(project == nil || (tab == .controlling && project?.controlling != true))
            }
            command("Local AI…", project?.localAI)
        }
    }

    private func command(_ key: String, _ action: (() -> Void)?) -> some View {
        Button { action?() } label: { Text(verbatim: title(key)) }
            .disabled(action == nil)
    }

    private func filter(_ key: String, _ selection: Binding<Bool>?) -> some View {
        Toggle(isOn: selection ?? .constant(false)) { Text(verbatim: title(key)) }
            .disabled(selection == nil)
    }

    private func title(_ key: String) -> String {
        AppLanguage.text(key, fallback: key, locale: locale)
    }
}
