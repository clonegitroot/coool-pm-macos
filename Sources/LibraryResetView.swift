import SwiftUI

struct LibraryResetView: View {
    enum Scope: String, CaseIterable {
        case library = "Reset local library"
        case app = "Reset app and library"
    }

    let reset: (Scope) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scope = Scope.library
    @State private var error: String?
    @State private var authenticating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Reset Coool PM", systemImage: "arrow.counterclockwise").font(.title2.bold())
            Text("A recovery backup will be saved to the local Backups folder before anything is removed.")
                .foregroundStyle(.secondary)
            Picker("What to reset", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { item in Text(LocalizedStringKey(item.rawValue)).tag(item) }
            }
            .pickerStyle(.radioGroup)
            .disabled(authenticating)
            .labelsHidden()
            VStack(alignment: .leading, spacing: 8) {
                Text("Both options remove this Mac’s projects, clients, contacts, documents, and invoice number history. Private iCloud data stays in iCloud and automatic sync is turned off.")
                if scope == .app {
                    Text("App reset also clears settings, templates, and the local encryption key. Coool PM returns to the library setup screen. Keep your existing recovery key to open backups made before the reset.")
                } else {
                    Text("Library reset keeps your business settings, templates, rates, and goals.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(authenticating)
                Spacer()
                Button("Back Up and Reset", role: .destructive) {
                    authenticating = true
                    Task {
                        defer { authenticating = false }
                        do {
                            try await DeviceAuthentication.confirm("Authorize resetting your Coool PM library.")
                            try reset(scope)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).tint(.red).disabled(authenticating)
            }
        }
        .interactiveDismissDisabled(authenticating)
        .padding(24)
        .frame(width: 515)
        .fixedSize(horizontal: false, vertical: true)
    }
}
