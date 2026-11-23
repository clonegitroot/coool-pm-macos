import Foundation
import CooolSQLCipher

enum EncryptedSQLite {
    static func isPlain(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try file.read(upToCount: 16) == Data("SQLite format 3\0".utf8)
    }

    private static func material(_ key: LibraryKey) -> String {
        let hex = key.derived("sqlite").withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        return "x'" + hex + "'"
    }

    static func apply(_ key: LibraryKey, to db: OpaquePointer?) throws {
        let raw = material(key)
        guard sqlite3_key(db, raw, Int32(raw.utf8.count)) == SQLITE_OK else { throw VaultError.wrongKey }
        // Opening SQLite is lazy. Force page authentication before any schema change.
        do { try run("SELECT count(*) FROM sqlite_master", on: db) } catch { throw VaultError.wrongKey }
        try run("PRAGMA temp_store=MEMORY", on: db)
    }

    private static func run(_ sql: String, on db: OpaquePointer?) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw LibraryError(description: String(cString: sqlite3_errmsg(db)))
        }
    }

    static func migratePlaintext(at url: URL, key: LibraryKey) throws {
        var old: OpaquePointer?
        guard sqlite3_open_v2(url.path, &old, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(old)
            throw CocoaError(.fileReadNoPermission)
        }
        defer { sqlite3_close(old) }
        sqlite3_busy_timeout(old, 3000)
        // Roll back legacy hot journals and checkpoint any WAL before replacing the main file.
        try run("PRAGMA locking_mode=EXCLUSIVE; PRAGMA journal_mode=DELETE; BEGIN EXCLUSIVE; COMMIT", on: old)
        let stage = url.deletingLastPathComponent().appendingPathComponent(".vault-\(UUID().uuidString).sqlite")
        let stageFD = Darwin.open(stage.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard stageFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        close(stageFD)
        defer { try? FileManager.default.removeItem(at: stage) }
        var attachment: OpaquePointer?
        guard sqlite3_prepare_v2(old, "ATTACH DATABASE ? AS vault KEY ?", -1, &attachment, nil) == SQLITE_OK else {
            throw LibraryError(description: String(cString: sqlite3_errmsg(old)))
        }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(attachment, 1, stage.path, -1, copy)
        sqlite3_bind_text(attachment, 2, material(key), -1, copy)
        let attached = sqlite3_step(attachment)
        sqlite3_finalize(attachment)
        guard attached == SQLITE_DONE else { throw LibraryError(description: String(cString: sqlite3_errmsg(old))) }
        try run("SELECT sqlcipher_export('vault'); DETACH DATABASE vault", on: old)
        var encrypted: OpaquePointer?
        guard sqlite3_open_v2(stage.path, &encrypted, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(encrypted)
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(encrypted) }
        try apply(key, to: encrypted)
        var check: OpaquePointer?
        guard sqlite3_prepare_v2(encrypted, "PRAGMA integrity_check", -1, &check, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, String(cString: sqlite3_column_text(check, 0)) == "ok",
              sqlite3_step(check) == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.path)
        // Same-volume atomic rename, while the source connection still holds its exclusive lock.
        guard rename(stage.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
