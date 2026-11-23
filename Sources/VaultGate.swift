import SwiftUI
import LocalAuthentication

enum DeviceAuthentication {
    @MainActor static func confirm(_ reason: String) async throws {
        let context = LAContext()
        var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else {
            throw failure ?? VaultError.locked
        }
        let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: AppLanguage.currentText(reason))
        guard passed else { throw VaultError.locked }
    }
}

@MainActor
final class LibraryAccess: ObservableObject {
    enum Stage { case checking, locked, setup, recover, open }
    @Published private(set) var stage = Stage.checking
    @Published var message = ""
    private var started = false
    private var lease: UnlockedLibraryLease?

    func start() async {
        guard !started else { return }
        started = true
        do {
            let locked = try LibraryKey.launchLockEnabled()
            UserDefaults.standard.set(locked, forKey: "requireLaunchAuthentication")
            if locked { stage = .locked } else { await unlock() }
        } catch {
            message = error.localizedDescription
            stage = .locked
        }
    }

    func unlock() async {
        stage = .checking
        do {
            if try LibraryKey.launchLockEnabled() { try await DeviceAuthentication.confirm("Unlock your Coool PM library.") }
            let key = try LibraryKey.saved()
            let url = try ProjectDatabase.libraryURL()
            let staged = ProjectDatabase.pendingResetURL(for: url)
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: staged.path) {
                // An interruption before Keychain removal leaves the old library usable.
                if key != nil { try fm.moveItem(at: staged, to: url) }
                else { try? fm.removeItem(at: staged) }
            }
            if let key { try finish(key); return }
            let exists = FileManager.default.fileExists(atPath: url.path) && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            let needsRecovery = try exists && !EncryptedSQLite.isPlain(at: url)
            let hasProtectedPreferences = (VaultPreferences.dataKeys + VaultPreferences.textKeys).contains {
                UserDefaults.standard.data(forKey: $0).map(LibraryKey.isSealed) == true
            }
            stage = needsRecovery || hasProtectedPreferences ? .recover : .setup
        } catch {
            message = error.localizedDescription
            stage = .locked
        }
    }

    func beginFreshSetup() {
        lease = nil
        VaultSession.shared.lockSession()
        message = ""
        stage = .setup
    }

    func configure(_ key: LibraryKey) {
        do { try finish(key) }
        catch { message = error.localizedDescription }
    }
    private func finish(_ key: LibraryKey) throws {
        let url = try ProjectDatabase.libraryURL()
        if try EncryptedSQLite.isPlain(at: url), NSWorkspace.shared.runningApplications.contains(where: {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier &&
                ($0.bundleIdentifier == Bundle.main.bundleIdentifier || $0.executableURL?.lastPathComponent == "CooolPM")
        }) {
            throw LibraryError(description: "Close the other running copy of Coool PM and try again.")
        }
        let lease = try UnlockedLibraryLease()
        if FileManager.default.fileExists(atPath: url.path), try !EncryptedSQLite.isPlain(at: url) {
            _ = try ProjectDatabase(url: url, readOnly: true, vaultKey: key)
        }
        try VaultPreferences.migrate(key: key, validateOnly: true)
        try key.store()
        try VaultPreferences.migrate(key: key)
        VaultSession.shared.unlock(key)
        do { _ = try ProjectDatabase(url: url, vaultKey: key) }
        catch { VaultSession.shared.lockSession(); throw error }
        self.lease = lease
        message = ""
        stage = .open
    }
}

struct VaultGate<Content: View>: View {
    @Environment(\.locale) private var locale
    @ObservedObject var access: LibraryAccess
    @ViewBuilder let content: () -> Content
    @State private var newKey = LibraryKey.generate()
    @State private var useExisting = false
    @State private var recovery = ""
    @State private var recorded = false
    @State private var copiedKey = false
    @State private var demo = false

    var body: some View {
        Group {
            if access.stage == .open { content() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.tint)
                    switch access.stage {
                    case .checking: ProgressView("Opening library…")
                    case .locked:
                        Text("Library locked").font(.title.bold())
                        Button("Unlock library") { Task { await access.unlock() } }.buttonStyle(.borderedProminent)
                    case .setup, .recover:
                        Text("Protect your library").font(.title.bold())
                        Text("Your recovery key unlocks encrypted records and backups on another Mac. Keep a copy somewhere safe.")
                        if access.stage == .setup {
                            Picker("Recovery key", selection: $useExisting) {
                                Text("Create key").tag(false)
                                Text("Use existing key").tag(true)
                            }.pickerStyle(.segmented)
                        }
                        if useExisting || access.stage == .recover {
                            SecureField("Recovery key", text: $recovery)
                            Button("Use recovery key") {
                                do { access.configure(try LibraryKey(recovery: recovery)); recovery = "" }
                                catch { access.message = error.localizedDescription }
                            }.disabled(recovery.isEmpty)
                        } else {
                            Text(verbatim: newKey.printable).font(.body.monospaced())
                            HStack {
                                Button(copiedKey ? "Key copied" : "Copy recovery key") {
                                    NSPasteboard.general.clearContents()
                                    copiedKey = NSPasteboard.general.setString(newKey.printable, forType: .string)
                                }
                                Button("Save recovery key…") { saveKey() }
                                Button("Print recovery key…") { printKey() }
                            }
                            Toggle("I have saved my recovery key", isOn: $recorded)
                            Button("Continue") { access.configure(newKey) }
                                .disabled(!recorded).buttonStyle(.borderedProminent)
                        }
                        Button("Explore demo library", systemImage: "sparkles") { demo = true }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    case .open: EmptyView()
                    }
                    if !access.message.isEmpty { Text(verbatim: access.message).foregroundStyle(.red) }
                }
                .padding(36).frame(maxWidth: 560).frame(maxWidth: .infinity, maxHeight: .infinity)
                .sheet(isPresented: $demo) { DemoLibraryView(startTour: true).environment(\.locale, locale) }
            }
        }
        .onChange(of: access.stage) { _, stage in
            if stage == .setup {
                newKey = LibraryKey.generate()
                useExisting = false
                recovery = ""
                recorded = false
                copiedKey = false
            }
        }
        .task { await access.start() }
    }
    private var recoveryText: String {
        "Coool PM — " + AppLanguage.currentText("Recovery key") + "\n\n" + newKey.printable + "\n"
    }
    private func saveKey() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Coool-PM-Recovery-Key.txt"
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let file = FileWrapper(regularFileWithContents: Data(recoveryText.utf8))
                file.fileAttributes = [FileAttributeKey.posixPermissions.rawValue: 0o600]
                try file.write(to: url, options: .atomic, originalContentsURL: nil)
                recorded = true
                access.message = ""
            } catch { access.message = error.localizedDescription }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    private func printKey() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 250))
        view.string = recoveryText
        view.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        guard let window = NSApp.keyWindow else {
            access.message = AppLanguage.currentText("Activate the Coool PM window and try printing again.")
            return
        }
        NSPrintOperation(view: view).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
