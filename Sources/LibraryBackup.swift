import AppKit

extension Notification.Name {
    static let cooolLibraryDidRestore = Self("cooolLibraryDidRestore")
}

enum BackupReminder {
    static let storageKey = "backupReminderDays"
    static let defaultDays = 2
    static let dayOptions = [0, 1, 2, 3, 7, 14, 30]

    static func isDue(days: Int, lastBackup: TimeInterval, lastReminder: TimeInterval,
                      started: TimeInterval, now: Date) -> Bool {
        guard days > 0 else { return false }
        let latest = max(lastBackup > 0 ? lastBackup : started, lastReminder)
        return latest > 0 && now.timeIntervalSince1970 - latest >= TimeInterval(days) * 86_400
    }
}

struct LibraryBackup: Codable {
    static let filenameExtension = "cooolbackup"
    private static let archiveVersion = 3
    private static let legacyVersions = 1...2
    private static let templateNames = Set(["invoice-de.docx", "invoice-en.docx", "proposal-de.docx", "proposal-en.docx"])

    let version: Int
    let savedAt: Date?
    let library: LibraryArchive
    let settings: Settings?

    struct Settings: Codable {
        let businessProfile: BusinessProfile
        let appLanguage: String
        let templates: [String: Data]
        var appearance: String?
        var documentLanguage: String?
        var dayRates: DayRateLibrary?
        var businessMonthlyGoals: Data?
        var pricingCategories: Data?
        var showArchived: Bool?
        var showEmptyClients: Bool?
        var completedSetup: Bool?
        var backupReminderDays: Int?
        var localAIEnabled: Bool?
        var localAIModelID: String?
        var localAIIdlePolicy: String?
        var projectAutosave: Bool?

        static var templateFolder: URL {
            WordTemplate(document: ClientDocument()).folder
        }

        static func capture(defaults: UserDefaults = .standard, folder: URL = templateFolder) throws -> Settings {
            var templates: [String: Data] = [:]
            for filename in templateNames {
                let file = folder.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: file.path) {
                    templates[filename] = try Data(contentsOf: file)
                }
            }
            return try Settings(businessProfile: BusinessProfile.read(defaults),
                            appLanguage: defaults.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue,
                            templates: templates,
                            appearance: defaults.string(forKey: "appAppearance"),
                            documentLanguage: defaults.string(forKey: "documentLanguage"),
                            dayRates: VaultPreferences.data(DayRateLibrary.storageKey, in: defaults).map { try JSONDecoder().decode(DayRateLibrary.self, from: $0) },
                            businessMonthlyGoals: VaultPreferences.data(BusinessMonthlyGoals.storageKey, in: defaults),
                            pricingCategories: VaultPreferences.data(PricingCatalog.storageKey, in: defaults),
                            showArchived: defaults.bool(forKey: "showArchivedProjects"),
                            showEmptyClients: defaults.bool(forKey: "showClientsWithoutActiveProjects"),
                            completedSetup: defaults.bool(forKey: "hasCompletedOnboarding"),
                            backupReminderDays: defaults.object(forKey: BackupReminder.storageKey) as? Int,
                            localAIEnabled: defaults.object(forKey: "localAIEnabled") as? Bool,
                            localAIModelID: defaults.string(forKey: "localAIModelID"),
                            localAIIdlePolicy: defaults.string(forKey: "localAIIdlePolicy"),
                            projectAutosave: defaults.object(forKey: "projectAutosave") as? Bool)
        }

        func install(defaults: UserDefaults = .standard, folder: URL = templateFolder) throws {
            guard Set(templates.keys).isSubset(of: templateNames), AppLanguage(rawValue: appLanguage) != nil,
                  appearance.map({ AppAppearance(rawValue: $0) != nil }) != false,
                  documentLanguage.map({ AppLanguage(rawValue: $0) != nil }) != false,
                  backupReminderDays.map(BackupReminder.dayOptions.contains) != false else {
                throw LibraryError(description: "The backup contains invalid settings.")
            }

            let fileManager = FileManager.default
            let support = folder.deletingLastPathComponent()
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            let stage = support.appendingPathComponent(".templates-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: stage) }

            if fileManager.fileExists(atPath: folder.path) {
                try fileManager.copyItem(at: folder, to: stage)
            } else {
                try fileManager.createDirectory(at: stage, withIntermediateDirectories: false)
            }
            for filename in templateNames {
                let file = stage.appendingPathComponent(filename)
                if let data = templates[filename] {
                    try data.write(to: file, options: .atomic)
                } else if fileManager.fileExists(atPath: file.path) {
                    try fileManager.removeItem(at: file)
                }
            }

            let businessData = try JSONEncoder().encode(businessProfile)
            let rateData = try dayRates?.encoded()
            if fileManager.fileExists(atPath: folder.path) {
                _ = try fileManager.replaceItemAt(folder, withItemAt: stage)
            } else {
                try fileManager.moveItem(at: stage, to: folder)
            }
            try VaultPreferences.set(businessData, for: "businessProfile", in: defaults)
            if let showArchived { defaults.set(showArchived, forKey: "showArchivedProjects") }
            if let showEmptyClients { defaults.set(showEmptyClients, forKey: "showClientsWithoutActiveProjects") }
            if let completedSetup { defaults.set(completedSetup, forKey: "hasCompletedOnboarding") }
            if let backupReminderDays { defaults.set(backupReminderDays, forKey: BackupReminder.storageKey) }
            if let localAIEnabled { defaults.set(localAIEnabled, forKey: "localAIEnabled") }
            if let localAIModelID { defaults.set(localAIModelID, forKey: "localAIModelID") }
            if let localAIIdlePolicy { defaults.set(localAIIdlePolicy, forKey: "localAIIdlePolicy") }
            if let projectAutosave { defaults.set(projectAutosave, forKey: "projectAutosave") }
            defaults.set(appLanguage, forKey: "appLanguage")
            if let rateData { try VaultPreferences.set(rateData, for: DayRateLibrary.storageKey, in: defaults) }
            else { defaults.removeObject(forKey: DayRateLibrary.storageKey) }
            if let businessMonthlyGoals { try VaultPreferences.set(businessMonthlyGoals, for: BusinessMonthlyGoals.storageKey, in: defaults) }
            else { defaults.removeObject(forKey: BusinessMonthlyGoals.storageKey) }
            if let pricingCategories { try VaultPreferences.set(pricingCategories, for: PricingCatalog.storageKey, in: defaults) }
            else { defaults.removeObject(forKey: PricingCatalog.storageKey) }
            if let appearance { defaults.set(appearance, forKey: "appAppearance") }
            else { defaults.removeObject(forKey: "appAppearance") }
            if let documentLanguage { defaults.set(documentLanguage, forKey: "documentLanguage") }
            else { defaults.removeObject(forKey: "documentLanguage") }
        }
    }

    static func capture(library: LibraryArchive, at date: Date = .now) throws -> LibraryBackup {
        LibraryBackup(version: archiveVersion, savedAt: date, library: library, settings: try Settings.capture())
    }

    static func decode(_ input: Data, recoveryKey: LibraryKey? = nil) throws -> LibraryBackup {
        let data: Data
        if LibraryKey.isSealed(input) {
            data = try (recoveryKey ?? VaultSession.shared.key()).open(input, purpose: "backup")
        } else {
            data = input // Read-only compatibility for original v1–v3 plaintext archives.
        }
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        if header.version == archiveVersion {
            let backup = try decoder.decode(LibraryBackup.self, from: data)
            guard legacyVersions.contains(backup.library.version) else {
                throw LibraryError(description: "Unsupported library backup version.")
            }
            return backup
        }
        if legacyVersions.contains(header.version) {
            return LibraryBackup(version: header.version, savedAt: nil,
                                 library: try decoder.decode(LibraryArchive.self, from: data), settings: nil)
        }
        throw LibraryError(description: "Unsupported library backup version.")
    }

    func write(to url: URL) throws {
        let archive = LibraryBackup(version: Self.archiveVersion, savedAt: savedAt, library: library, settings: settings)
        let sealed = try VaultSession.shared.key().seal(JSONEncoder().encode(archive), purpose: "backup")
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func suggestedName(at date: Date, versioned: Bool = false) -> String {
        var style = Date.ISO8601FormatStyle(timeZone: .current)
            .year().month().day().dateSeparator(.dash)
        if versioned { style = style.time(includingFractionalSeconds: false).timeSeparator(.omitted) }
        let stamp = date.formatted(style).replacingOccurrences(of: "T", with: "-")
        let suffix = versioned ? "-\(UUID().uuidString.prefix(8).lowercased())" : ""
        return "Coool-PM-\(stamp)\(suffix).\(filenameExtension)"
    }

    static func localBackupFolder(creating: Bool = false) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: creating)
        let folder = support.appendingPathComponent("Coool PM/Backups", isDirectory: true)
        if creating { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder
    }
}

struct AutomaticBackupLocation {
    let bookmark: Data

    init(_ folder: URL) throws {
        self.bookmark = try folder.bookmarkData(options: [.minimalBookmark])
    }

    init(bookmark: Data) {
        self.bookmark = bookmark
    }

    func resolve() throws -> URL {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                             relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else {
            throw LibraryError(description: "The backup folder moved. Choose it again in Library Backup.")
        }
        return folder
    }
}

@MainActor
func readBackupForRestore(_ data: Data) throws -> LibraryBackup {
    do { return try LibraryBackup.decode(data) }
    catch VaultError.wrongKey {
        let dialog = NSAlert()
        dialog.messageText = AppLanguage.currentText("Enter this backup’s recovery key")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        dialog.accessoryView = field
        dialog.window.initialFirstResponder = field
        dialog.addButton(withTitle: AppLanguage.currentText("Unlock backup"))
        dialog.addButton(withTitle: AppLanguage.currentText("Cancel"))
        guard dialog.runModal() == .alertFirstButtonReturn else { throw CocoaError(.userCancelled) }
        return try LibraryBackup.decode(data, recoveryKey: LibraryKey(recovery: field.stringValue))
    }
}
