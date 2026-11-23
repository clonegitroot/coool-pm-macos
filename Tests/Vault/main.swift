import Foundation
import CooolSQLCipher

private struct Failure: Error, CustomStringConvertible { let description: String }

private func check(_ message: String, _ condition: @autoclosure () throws -> Bool) throws {
    guard try condition() else { throw Failure(description: message) }
}

private func expectFailure(_ name: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch { return }
    throw Failure(description: "\(name) unexpectedly succeeded")
}

private func rawConnection(_ path: URL, key: LibraryKey? = nil, _ body: (OpaquePointer) throws -> Void) throws {
    var db: OpaquePointer?
    guard sqlite3_open(path.path, &db) == SQLITE_OK, let db else { throw Failure(description: "Open fixture SQLite") }
    defer { sqlite3_close(db) }
    if let key { try EncryptedSQLite.apply(key, to: db) }
    try body(db)
}

private func run(_ sql: String, on db: OpaquePointer) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw Failure(description: "Fixture SQL failed: \(String(cString: sqlite3_errmsg(db)))")
    }
}

private func roundTrip() throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("coool-vault-test-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: directory) }

    let source = directory.appendingPathComponent("library.sqlite")
    let suite = "app.cooolpm.fixture." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(description: "Create fixture preferences") }
    defer { defaults.removePersistentDomain(forName: suite); VaultSession.shared.lockSession() }
    let key = LibraryKey.generate()
    let wrong = LibraryKey.generate()
    let keyFile = try LibraryKey(recovery: "Coool PM — Recovery key\n\n" + key.printable + "\n")
    try check("Saved recovery key file is accepted", keyFile.printable == key.printable)
    let recovered = try LibraryKey(recovery: key.printable.lowercased())
    try expectFailure("Invalid recovery checksum") {
        _ = try LibraryKey(recovery: String(key.printable.dropLast()) + (key.printable.last == "0" ? "1" : "0"))
    }
    let marker = "Amber Kite private fixture 7551"
    let secret = Data(marker.utf8)
    var estimate = Estimate()
    estimate.title = marker
    var override = UsageFeatureOverrides()
    override.set(.costControlling, enabled: true)
    estimate.featureOverrides = override
    let id = UUID()
    try rawConnection(source) { db in
        try run("PRAGMA journal_mode=WAL; CREATE TABLE projects (id TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL)", on: db)
        let json = String(decoding: try JSONEncoder().encode(estimate), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
        try run("INSERT INTO projects VALUES ('\(id.uuidString)','\(json)')", on: db)
    }
    try check("Legacy fixture contains synthetic plaintext", try Data(contentsOf: source).range(of: secret) != nil)
    try expectFailure("Read-only migration") { _ = try ProjectDatabase(url: source, readOnly: true, vaultKey: key) }
    try expectFailure("MCP migration") { _ = try ProjectDatabase(url: source, vaultKey: key, allowMigration: false) }
    try check("Read-only open left legacy file intact", try EncryptedSQLite.isPlain(at: source))
    try rawConnection(source) { db in
        try run("BEGIN IMMEDIATE", on: db)
        try expectFailure("Migration during another writer") { _ = try ProjectDatabase(url: source, vaultKey: key) }
        try run("ROLLBACK", on: db)
    }

    VaultSession.shared.unlock(key)
    let database = try ProjectDatabase(url: source)
    try check("Migration retained project contents", try database.project(id: id)?.estimate.title == marker)
    try check("No cleartext database header", try !EncryptedSQLite.isPlain(at: source))
    try check("No cleartext project payload", try Data(contentsOf: source).range(of: secret) == nil)
    try expectFailure("Wrong database key") { _ = try ProjectDatabase(url: source, readOnly: true, vaultKey: wrong) }
    try rawConnection(source) { db in try expectFailure("Read with no key") { try run("SELECT * FROM projects", on: db) } }

    for mode in ["DELETE", "WAL"] {
        try rawConnection(source, key: recovered) { db in
            try run("PRAGMA journal_mode=\(mode); PRAGMA cache_size=1; BEGIN IMMEDIATE", on: db)
            let payload = String(repeating: marker, count: 300)
            try run("CREATE TABLE fixture(data TEXT); INSERT INTO fixture VALUES ('\(payload)')", on: db)
            let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in files { try check("Journal or DB leaked records", try Data(contentsOf: file).range(of: secret) == nil) }
            try run("ROLLBACK", on: db)
        }
    }
    print("Verified SQLCipher migration, busy-writer refusal, authenticated reopen, rollback journal and WAL.")

    var profile = BusinessProfile()
    profile.name = marker
    profile.usageFeatures = UsageProfile.solo.features
    defaults.set(try JSONEncoder().encode(profile), forKey: "businessProfile")
    defaults.set(marker, forKey: "letterContact")
    try VaultPreferences.migrate(defaults, key: key)
    let encoded = defaults.data(forKey: "businessProfile")!
    try check("Profile encryption", LibraryKey.isSealed(encoded) && encoded.range(of: secret) == nil)
    try check("Legacy preference retained", VaultPreferences.text("letterContact", in: defaults) == marker)
    try expectFailure("Wrong-key preference migration") { try VaultPreferences.migrate(defaults, key: wrong) }
    try check("Failed preference migration preserved data", defaults.data(forKey: "businessProfile") == encoded)
    defaults.set(true, forKey: "showClientsWithoutActiveProjects")
    defaults.set(AppLanguage.english.rawValue, forKey: "appLanguage")
    defaults.set(true, forKey: "localAIEnabled")
    defaults.set(7, forKey: BackupReminder.storageKey)
    defaults.set("fixture-model", forKey: "localAIModelID")
    var rateBook = DayRateLibrary()
    let rate = DayRateSchedule(name: "Fixture rates", tiers: [RateTier(lastDay: nil, rate: 900)])
    rateBook.schedules = [rate]
    rateBook.defaultID = rate.id
    try VaultPreferences.set(try rateBook.encoded(), for: DayRateLibrary.storageKey, in: defaults)
    let templateFolder = directory.appendingPathComponent("Templates", isDirectory: true)
    try fm.createDirectory(at: templateFolder, withIntermediateDirectories: false)
    let templateNames = ["proposal-en.docx", "proposal-de.docx", "invoice-en.docx", "invoice-de.docx"]
    for name in templateNames {
        try Data(name.utf8).write(to: templateFolder.appendingPathComponent(name))
    }
    let settings = try LibraryBackup.Settings.capture(defaults: defaults, folder: templateFolder)
    try check("Profile survives settings capture", settings.businessProfile.features == UsageProfile.solo.features)
    try check("Project feature override survives database capture", try database.project(id: id)?.estimate.featureOverrides?.value(.costControlling) == true)
    let archive = LibraryBackup(version: 3, savedAt: .now, library: try database.archive(), settings: settings)
    let backupFile = directory.appendingPathComponent("archive.cooolbackup")
    try archive.write(to: backupFile)
    let bytes = try Data(contentsOf: backupFile)
    try check("Encrypted archive and no marker", LibraryKey.isSealed(bytes) && bytes.range(of: secret) == nil)
    try archive.write(to: backupFile)
    try check("Fresh nonce for each encrypted backup", try bytes != Data(contentsOf: backupFile))
    let digest = try CloudLibrarySync.digest(of: archive)
    try expectFailure("Purpose-separated keys") { _ = try key.open(bytes, purpose: "preference/businessProfile") }
    var altered = bytes
    altered[altered.count - 1] ^= 1
    try expectFailure("Tampered backup") { _ = try LibraryBackup.decode(altered, recoveryKey: key) }
    VaultSession.shared.lockSession()
    try expectFailure("Locked archive write") { try archive.write(to: backupFile) }
    try expectFailure("Locked default database open") { _ = try ProjectDatabase(url: source, readOnly: true) }
    VaultSession.shared.unlock(wrong)
    try expectFailure("Wrong archive key") { _ = try LibraryBackup.decode(bytes) }
    let restored = try LibraryBackup.decode(bytes, recoveryKey: recovered)
    try check("Stable archive digest after restore", try CloudLibrarySync.digest(of: restored) == digest)
    try check("Recovered project", restored.library.projects.first?.estimate.title == marker)
    try check("Recovered profile", restored.settings?.businessProfile.name == marker)
    try check("Recovered template", restored.settings?.templates.count == templateNames.count)
    try check("Recovered filter", restored.settings?.showEmptyClients == true)
    let target = try ProjectDatabase(url: directory.appendingPathComponent("new-mac.sqlite"))
    try target.replaceLibrary(restored.library, ifVersionIs: target.changeVersion())
    let newTemplates = directory.appendingPathComponent("restored-templates", isDirectory: true)
    try fm.createDirectory(at: newTemplates, withIntermediateDirectories: false)
    try Data("Old template".utf8).write(to: newTemplates.appendingPathComponent("proposal-en.docx"))
    defaults.removeObject(forKey: "localAIEnabled")
    defaults.removeObject(forKey: BackupReminder.storageKey)
    defaults.removeObject(forKey: DayRateLibrary.storageKey)
    try restored.settings?.install(defaults: defaults, folder: newTemplates)
    for name in templateNames {
        try check("Installed template \(name)", try Data(contentsOf: newTemplates.appendingPathComponent(name)) == Data(name.utf8))
    }
    let rateData = try VaultPreferences.data(DayRateLibrary.storageKey, in: defaults)
    try check("Restored default rate", DayRateLibrary(data: rateData ?? Data()).defaultSchedule == rate)
    try check("Restored backup reminder", defaults.integer(forKey: BackupReminder.storageKey) == 7)
    try check("Restored app language", defaults.string(forKey: "appLanguage") == AppLanguage.english.rawValue)
    try check("Restored local AI preferences", defaults.bool(forKey: "localAIEnabled") &&
              defaults.string(forKey: "localAIModelID") == "fixture-model")
    try check("Profile re-encrypted under new Mac's local key", try BusinessProfile.read(defaults).name == marker)
    try check("Restored local settings do not contain plaintext", defaults.data(forKey: "businessProfile")?.range(of: secret) == nil)
    let resetURL = directory.appendingPathComponent("reset.sqlite")
    do {
        let resetting = try ProjectDatabase(url: resetURL, vaultKey: key)
        try resetting.replaceLibrary(restored.library)
        let version = try resetting.changeVersion()
        try expectFailure("Keychain failure rolls back full reset") {
            try resetting.detachForFreshSetup(at: resetURL, ifVersionIs: version) { throw VaultError.locked }
        }
        try check("Rollback restores encrypted library", try resetting.project(id: id)?.estimate.title == marker)
        try check("Rollback clears pending reset file", !fm.fileExists(atPath: ProjectDatabase.pendingResetURL(for: resetURL).path))
        try resetting.detachForFreshSetup(at: resetURL, ifVersionIs: version) {
            try check("Full reset stages database before removing key", !fm.fileExists(atPath: resetURL.path))
        }
    }
    try check("Full reset leaves no database or reset marker", !fm.fileExists(atPath: resetURL.path) &&
              !fm.fileExists(atPath: ProjectDatabase.pendingResetURL(for: resetURL).path))
    let fresh = try ProjectDatabase(url: resetURL, vaultKey: wrong)
    try check("Fresh setup opens with a new key", try fresh.archive().projects.isEmpty)
    let oldBackup = try JSONEncoder().encode(archive.library)
    try check("Legacy plaintext archive remains restorable", try LibraryBackup.decode(oldBackup).library.projects.count == 1)
    defaults.set(Data("damaged".utf8), forKey: "businessProfile")
    try expectFailure("Backup with unreadable profile") { _ = try LibraryBackup.Settings.capture(defaults: defaults, folder: templateFolder) }
    print("Verified recovery key checksum, preference migration, encrypted backups, tamper rejection, locked access and cross-key restore.")
}
private func leaseCheck() throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("coool-lease-" + UUID().uuidString)
    defer { try? fm.removeItem(at: directory) }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    func probe(expected: Bool, holder: URL = executable) throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = ["probe-lease", directory.path, holder.path]
        try proc.run()
        proc.waitUntilExit()
        try check("Unexpected live GUI ownership result", proc.terminationStatus == (expected ? 0 : 1))
    }
    try probe(expected: false)
    do {
        let lease = try UnlockedLibraryLease(directory: directory)
        try withExtendedLifetime(lease) {
            try probe(expected: true)
            try probe(expected: false, holder: URL(fileURLWithPath: "/usr/bin/true"))
        }
    }
    try probe(expected: false)
    print("Verified helper lease rejects a stale file or a different executable.")
}
if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "probe-lease" {
    exit(UnlockedLibraryLease.isHeld(in: URL(fileURLWithPath: CommandLine.arguments[2]), by: URL(fileURLWithPath: CommandLine.arguments[3])) ? 0 : 1)
}
try roundTrip()
try leaseCheck()
let reminderNow = Date(timeIntervalSince1970: 1_000_000)
let today = reminderNow.timeIntervalSince1970
let yesterday = today - 86_400
let twoDaysAgo = yesterday - 86_400
try check("Recent backup suppresses reminders",
          !BackupReminder.isDue(days: 2, lastBackup: yesterday, lastReminder: 0, started: 0, now: reminderNow))
try check("Two-day-old backup is eligible",
          BackupReminder.isDue(days: 2, lastBackup: twoDaysAgo, lastReminder: 0, started: today, now: reminderNow))
try check("Recent reminder snoozes the next prompt",
          !BackupReminder.isDue(days: 2, lastBackup: twoDaysAgo, lastReminder: yesterday, started: 0, now: reminderNow))
try check("Never disables reminders",
          !BackupReminder.isDue(days: 0, lastBackup: twoDaysAgo, lastReminder: 0, started: 0, now: reminderNow))
try check("New library receives the full grace period",
          !BackupReminder.isDue(days: 2, lastBackup: 0, lastReminder: 0, started: yesterday, now: reminderNow) &&
           BackupReminder.isDue(days: 2, lastBackup: 0, lastReminder: 0, started: twoDaysAgo, now: reminderNow))
print("Verified backup reminder interval, snooze, opt out, and new library grace period.")
