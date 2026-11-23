import SwiftUI

struct LibraryBackupView: View {
    enum Freshness: Sendable {
        case none, checking, current, changed, unavailable, unverified

        var label: LocalizedStringKey {
            switch self {
            case .none: "No backups created yet."
            case .checking: "Checking backup status…"
            case .current: "Recovery copy up to date"
            case .changed: "Recovery copy is out of date"
            case .unavailable: "Last backup file unavailable"
            case .unverified: "Backup freshness unverified"
            }
        }

        var icon: String {
            switch self {
            case .none: "externaldrive.badge.questionmark"
            case .checking: "arrow.trianglehead.clockwise"
            case .current: "checkmark.circle"
            case .changed: "clock"
            case .unavailable, .unverified: "exclamationmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .current: .green
            case .unavailable: .orange
            default: .secondary
            }
        }
    }

    let databaseReady: Bool
    let databaseLocation: String
    let freshness: Freshness
    let folderName: String
    let lastBackup: Double
    let lastBackupFile: String
    let lastError: String
    let isBackingUp: Bool
    let chooseFolder: () -> Void
    let chooseLocalFolder: () -> Void
    let stopAutomatic: () -> Void
    let backUp: () -> Void
    let saveAs: () -> Void
    let restore: () -> Void
    let cloudConfigured: Bool
    let cloudRunning: Bool
    let lastSync: Double
    let syncError: String
    let conflict: CloudLibrarySync.Conflict?
    @Binding var automaticSync: Bool
    let sync: () -> Void
    let resolveConflict: (CloudLibrarySync.ConflictChoice) -> Void
    @State private var confirmingConflict = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backups & Recovery").font(.title2.bold())
            Text("Backups are separate encrypted recovery copies of your library. Keep your recovery key separately.")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox("Local library") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Saving") {
                        if databaseReady {
                            Label("Autosave on", systemImage: "checkmark.circle").foregroundStyle(.green)
                        } else {
                            Label("Database unavailable", systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        }
                    }
                    if databaseReady {
                        Text("Edits save automatically to the library on this Mac.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if !databaseLocation.isEmpty {
                        location(databaseLocation)
                    }
                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Recovery backup") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(freshness.label, systemImage: freshness.icon)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(freshness.color)
                    if lastBackup > 0 {
                        LabeledContent("Last successful backup") {
                            Text(Date(timeIntervalSince1970: lastBackup), format: timestampFormat)
                        }
                        if !lastBackupFile.isEmpty { location(lastBackupFile) }
                    }
                    if !lastError.isEmpty { Text(lastError).foregroundStyle(.red).textSelection(.enabled) }
                    if isBackingUp {
                        ProgressView("Creating backup…").controlSize(.small)
                    }
                }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Automatic backups") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Destination") {
                        if folderName.isEmpty {
                            Text("Off").foregroundStyle(.secondary)
                        } else {
                            Text(folderName).textSelection(.enabled).lineLimit(2)
                        }
                    }
                    Text("Coool PM saves a dated backup once a day while it is open. Choose an iCloud Drive folder to let macOS copy the archive to your other devices.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Choose folder…", action: chooseFolder)
                        Button("Use local folder", action: chooseLocalFolder)
                        Spacer()
                        if !folderName.isEmpty {
                            Button("Turn off", action: stopAutomatic)
                        }
                    }
                    .disabled(!databaseReady || isBackingUp)
                }.padding(6)
            }
            cloudControls
            HStack {
                Button("Restore from backup…") { dismiss(); restore() }
                    .disabled(!databaseReady || isBackingUp || cloudRunning)
                Spacer()
                Button("Create Backup Elsewhere…", action: saveAs)
                    .disabled(!databaseReady || isBackingUp)
                Button("Create Backup Now", action: backUp)
                    .help("Creates a new backup immediately, even if one already exists today. Uses the local Backups folder when automatic backups are off.")
                    .disabled(!databaseReady || isBackingUp)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620)
        .confirmationDialog("Choose a library for iCloud sync", isPresented: $confirmingConflict, titleVisibility: .visible) {
            if conflict?.cloudAvailable == true {
                Button("Replace this Mac’s library", role: .destructive) { resolveConflict(.useCloud) }
            }
            Button("Keep this Mac’s library in iCloud", role: .destructive) { resolveConflict(.keepLocal) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The libraries differ. Coool PM saves a local recovery backup before replacing this Mac’s library.")
        }
    }

    private var timestampFormat: Date.FormatStyle {
        .dateTime.day().month().year().hour().minute().locale(locale)
    }

    private func location(_ path: String) -> some View {
        Text((path as NSString).abbreviatingWithTildeInPath)
            .font(.caption)
            .foregroundStyle(.secondary)
            .truncationMode(.middle)
            .lineLimit(2)
            .textSelection(.enabled)
            .help(path)
    }

    private var cloudControls: some View {
        GroupBox("Private iCloud sync") {
            VStack(alignment: .leading, spacing: 8) {
                if cloudConfigured {
                    Toggle("Sync automatically while Coool PM is open", isOn: $automaticSync)
                        .help("Checks the private iCloud library for changes while the app is running.")
                        .disabled(!databaseReady || cloudRunning)
                    if lastSync > 0 {
                        LabeledContent("Last successful sync") {
                            Text(Date(timeIntervalSince1970: lastSync), format: timestampFormat)
                        }
                    }
                    if !syncError.isEmpty { Text(syncError).foregroundStyle(.red).textSelection(.enabled) }
                    if conflict != nil {
                        Button("Review different library versions…") { confirmingConflict = true }
                            .disabled(!databaseReady || cloudRunning)
                    } else {
                        Button("Sync now", action: sync).disabled(!databaseReady || cloudRunning)
                    }
                    if cloudRunning { ProgressView().controlSize(.small) }
                } else {
                    LabeledContent("Status") {
                        Text("Local library").foregroundStyle(.secondary)
                    }
                    Text("Private sync requires a build signed with this app’s CloudKit container.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
