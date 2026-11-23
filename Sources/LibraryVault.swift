import Foundation
import CryptoKit
import Security

enum VaultError: LocalizedError {
    case locked, invalidKey, wrongKey, missingKey, keychain(OSStatus), legacyOpen
    var errorDescription: String? {
        let message = switch self {
        case .locked: "Unlock the library before accessing its records."
        case .invalidKey: "Enter the complete Coool PM recovery key, including its checksum."
        case .wrongKey: "This data could not be authenticated. Check its recovery key and file integrity."
        case .missingKey: "The key is missing from this Mac’s Keychain. Enter your saved recovery key."
        case .keychain(let status): "Keychain returned error \(status)."
        case .legacyOpen: "Open Coool PM to finish encrypting the existing library."
        }
        return AppLanguage.currentText(message)
    }
}

/// One 256-bit random recovery secret. HKDF isolates database, archive, and preference keys.
struct LibraryKey {
    private let bytes: Data
    static func generate() -> Self {
        Self(bytes: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }
    private init(bytes: Data) { self.bytes = bytes }

    private var checksum: String { SHA256.hash(data: bytes).prefix(4).map { String(format: "%02X", $0) }.joined() }
    var printable: String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let groups = stride(from: 0, to: hex.count, by: 8).map { String(hex.dropFirst($0).prefix(8)) }
        return (["CPM1"] + groups + [checksum]).joined(separator: "-")
    }
    init(recovery: String) throws {
        let lines = recovery.split(whereSeparator: \.isNewline)
        let input = lines.first?.hasPrefix("Coool PM — ") == true ? lines.dropFirst().joined() : recovery
        let parts = input.uppercased().split { $0 == "-" || $0.isWhitespace }.joined()
        guard parts.hasPrefix("CPM1"), parts.count == 76 else { throw VaultError.invalidKey }
        let hex = String(parts.dropFirst(4).prefix(64))
        let values = stride(from: 0, to: 64, by: 2).compactMap { UInt8(hex.dropFirst($0).prefix(2), radix: 16) }
        guard values.count == 32 else { throw VaultError.invalidKey }
        bytes = Data(values)
        guard parts.suffix(8) == checksum else { throw VaultError.invalidKey }
    }

    func derived(_ purpose: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: Data("Coool PM vault v1".utf8),
                                info: Data(purpose.utf8), outputByteCount: 32)
    }
    private static let magic = Data("COOOLPM-SEALED-1\n".utf8)
    static func isSealed(_ data: Data) -> Bool { data.starts(with: magic) }
    func seal(_ data: Data, purpose: String) throws -> Data {
        let box = try AES.GCM.seal(data, using: derived(purpose), authenticating: Self.magic)
        guard let combined = box.combined else { throw VaultError.wrongKey }
        return Self.magic + combined
    }
    func open(_ data: Data, purpose: String) throws -> Data {
        guard Self.isSealed(data) else { throw VaultError.wrongKey }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.magic.count))
            return try AES.GCM.open(box, using: derived(purpose), authenticating: Self.magic)
        } catch { throw VaultError.wrongKey }
    }

    static var applicationID: String {
        if let identifier = Bundle.main.bundleIdentifier { return identifier }
        if let exe = Bundle.main.executableURL {
            let bundle = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if let identifier = Bundle(url: bundle)?.bundleIdentifier { return identifier }
        }
        return "app.cooolpm.desktop"
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: applicationID + ".library-vault.v1",
         kSecAttrAccount as String: "local-library"]
    }
    // Keep the lock policy with the key so clearing ordinary app preferences cannot disable it.
    private static let launchLockMarker = "Coool PM: require device-owner authentication on launch"
    static func launchLockEnabled() throws -> Bool {
        var query = query
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let attributes = result as? [String: Any] else { throw VaultError.invalidKey }
        return attributes[kSecAttrDescription as String] as? String == launchLockMarker
    }
    static func setLaunchLock(_ enabled: Bool) throws {
        let changes = [kSecAttrDescription as String: enabled ? launchLockMarker : "Coool PM local library"]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
    static func saved() throws -> Self? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
        guard let data = result as? Data, data.count == 32 else { throw VaultError.invalidKey }
        return Self(bytes: data)
    }
    static func clearLocalSetup() throws {
        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: applicationID)
        defaults.synchronize()
        try removeFromKeychain()
    }

    private static func removeFromKeychain() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.keychain(status)
        }
    }
    func store() throws {
        // Never overwrite an existing library secret as a side effect of setup or backup import.
        if let prior = try Self.saved() {
            guard prior.bytes == bytes else { throw VaultError.wrongKey }
            return
        }
        var query = Self.query
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecValueData as String] = bytes
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
}

final class VaultSession: @unchecked Sendable {
    static let shared = VaultSession()
    private let lock = NSLock()
    private var active: LibraryKey?
    func unlock(_ key: LibraryKey) { lock.withLock { active = key } }
    func lockSession() { lock.withLock { active = nil } }
    func key() throws -> LibraryKey {
        try lock.withLock { guard let active else { throw VaultError.locked }; return active }
    }
}

enum VaultPreferences {
    static let dataKeys = ["businessProfile", "dayRateLibrary", "pricingCatalog", "businessMonthlyGoals", "automaticBackupBookmark"]
    static let textKeys = ["xrechnungJavaPath", "xrechnungValidatorPath", "xrechnungRulesPath", "automaticBackupFolder",
                           "lastLibraryBackupFile", "lastLibraryBackupError", "selectedProject", "documentSender", "letterContact", "letterBank"]

    static func migrate(_ defaults: UserDefaults = .standard, key: LibraryKey, validateOnly: Bool = false) throws {
        var changes: [String: Data] = [:]
        for name in dataKeys + textKeys {
            guard let value = defaults.object(forKey: name) else { continue }
            if let data = value as? Data, LibraryKey.isSealed(data) {
                _ = try key.open(data, purpose: "preference/" + name)
            } else {
                let plain: Data
                if let data = value as? Data { plain = data }
                else if let text = value as? String { plain = Data(text.utf8) }
                else { throw CocoaError(.coderReadCorrupt) }
                changes[name] = try key.seal(plain, purpose: "preference/" + name)
            }
        }
        guard !validateOnly else { return }
        for (name, sealed) in changes { defaults.set(sealed, forKey: name) }
    }

    static func data(_ name: String, in defaults: UserDefaults = .standard) throws -> Data? {
        guard let stored = defaults.data(forKey: name) else { return nil }
        return try VaultSession.shared.key().open(stored, purpose: "preference/" + name)
    }
    static func set(_ data: Data, for name: String, in defaults: UserDefaults = .standard) throws {
        defaults.set(try VaultSession.shared.key().seal(data, purpose: "preference/" + name), forKey: name)
    }
    static func text(_ name: String, in defaults: UserDefaults = .standard) -> String? {
        (try? data(name, in: defaults)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// A kernel-owned lease lets the CLI verify that its own bundled GUI currently holds the unlocked library.
final class UnlockedLibraryLease {
    private let fd: Int32

    private static func openFile(in directory: URL, creating: Bool) throws -> Int32 {
        if creating { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let flags = O_RDWR | O_NOFOLLOW | O_CLOEXEC | (creating ? O_CREAT : 0)
        let fd = Darwin.open(directory.appendingPathComponent(".unlocked").path, flags, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        return fd
    }

    private static func exclusiveLock() -> Darwin.flock {
        var lock = Darwin.flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        return lock
    }

    init(directory: URL? = nil) throws {
        let location = try directory ?? ProjectDatabase.libraryURL().deletingLastPathComponent()
        fd = try Self.openFile(in: location, creating: true)
        var lock = Self.exclusiveLock()
        guard fcntl(fd, F_SETLK, &lock) == 0 else {
            close(fd)
            throw LibraryError(description: "Close the other running copy of Coool PM and try again.")
        }
    }
    deinit { close(fd) }

    static func isUnlocked() -> Bool {
        guard let helper = Bundle.main.executableURL, let directory = try? ProjectDatabase.libraryURL().deletingLastPathComponent() else { return false }
        return isHeld(in: directory, by: helper.deletingLastPathComponent().appendingPathComponent("CooolPM"))
    }

    /// Probe from the helper process. A stale file or a different process holding the lock is insufficient.
    static func isHeld(in directory: URL, by executable: URL) -> Bool {
        guard let fd = try? openFile(in: directory, creating: false) else { return false }
        defer { close(fd) }
        var lock = exclusiveLock()
        guard fcntl(fd, F_GETLK, &lock) == 0, lock.l_type == Int16(F_WRLCK), lock.l_pid > 0 else { return false }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(lock.l_pid, &path, UInt32(path.count))
        guard length > 0 else { return false }
        let holder = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().standardizedFileURL
        return holder == executable.resolvingSymlinksInPath().standardizedFileURL
    }
}
