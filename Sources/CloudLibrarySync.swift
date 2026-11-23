import CloudKit
import CryptoKit
import Foundation
import Security

/// Mirrors a library into a single record in the user's private CloudKit database.
/// Each write uses the exact CloudKit version it was compared against.
@MainActor
final class CloudLibrarySync {
    enum Outcome {
        case upToDate
        case uploaded
        case download(Download)
        case conflict(Conflict)
    }

    enum ConflictChoice { case keepLocal, useCloud }

    struct Download {
        let backup: LibraryBackup
        fileprivate let accountKey: String
        fileprivate let localDigest: String
        fileprivate let state: State
    }

    struct Conflict {
        fileprivate let accountKey: String
        fileprivate let localDigest: String
        fileprivate let cloudTag: String?
        let cloudModifiedAt: Date?
        var cloudAvailable: Bool { cloudTag != nil }
    }

    fileprivate struct State: Codable {
        let changeTag: String
        let digest: String
    }

    private struct CloudHead {
        let record: CKRecord
        let state: State
    }

    private struct Session {
        let container: CKContainer
        let user: CKRecord.ID
        let accountKey: String
    }

    private static let configurationKey = "CooolCloudKitContainer"
    private static let associatedAccountKey = "cooolCloudAssociatedAccount"
    private static let recordType = "CooolLibrary"
    private static let recordID = CKRecord.ID(recordName: "CooolPM-Library")
    private let defaults: UserDefaults
    private var busy = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static var containerIdentifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: configurationKey) as? String,
              identifier.hasPrefix("iCloud."), identifier.count > 7,
              let task = SecTaskCreateFromSelf(nil),
              let containers = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String],
              containers.contains(identifier),
              let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) as? [String],
              services.contains("CloudKit") else { return nil }
        return identifier
    }

    static var isConfigured: Bool { containerIdentifier != nil }

    func forgetLocalAssociation() {
        if let key = defaults.string(forKey: Self.associatedAccountKey) { defaults.removeObject(forKey: key) }
        defaults.removeObject(forKey: Self.associatedAccountKey)
    }

    func synchronize(local: LibraryBackup) async throws -> Outcome {
        try begin()
        defer { busy = false }

        let digest = try Self.digest(of: local)
        let session = try await session()
        let previous = state(for: session.accountKey)
        let head = try await cloudHead(in: session)

        if let head {
            if head.state.digest == "vault1:" + digest {
                remember(head.state, for: session.accountKey)
                return .upToDate
            }
            if head.state.digest == digest || previous?.changeTag == head.state.changeTag {
                return try await upload(local, digest: digest, replacing: head, in: session)
            }
            if previous?.digest == digest || previous?.digest == "vault1:" + digest {
                return try await download(head, localDigest: digest, in: session)
            }
        } else if previous == nil, defaults.string(forKey: Self.associatedAccountKey) == nil {
            return try await upload(local, digest: digest, replacing: nil, in: session)
        }

        return .conflict(conflict(head, localDigest: digest, in: session))
    }

    func resolve(_ conflict: Conflict, using choice: ConflictChoice, local: LibraryBackup) async throws -> Outcome {
        try begin()
        defer { busy = false }

        let digest = try Self.digest(of: local)
        let session = try await session()
        guard session.accountKey == conflict.accountKey else { throw accountChanged }
        let head = try await cloudHead(in: session)

        guard digest == conflict.localDigest, head?.state.changeTag == conflict.cloudTag else {
            return .conflict(self.conflict(head, localDigest: digest, in: session))
        }
        switch choice {
        case .keepLocal:
            return try await upload(local, digest: digest, replacing: head, in: session)
        case .useCloud:
            guard let head else {
                throw LibraryError(description: "The CloudKit library is unavailable.")
            }
            return try await download(head, localDigest: digest, in: session)
        }
    }

    /// Call immediately before replacing local storage, using a fresh snapshot.
    func checkLocal(_ local: LibraryBackup, for download: Download) throws {
        guard try Self.digest(of: local) == download.localDigest else {
            throw LibraryError(description: "The local library changed during sync. Sync again to compare both versions.")
        }
    }

    /// A downloaded library becomes the baseline only after the caller successfully installs it.
    func didApply(_ download: Download) {
        remember(download.state, for: download.accountKey)
    }

    private var accountChanged: LibraryError {
        LibraryError(description: "The iCloud account changed during sync. Sync again with the current account.")
    }

    private func begin() throws {
        guard !busy else { throw LibraryError(description: "A library sync is already running.") }
        busy = true
    }

    private func session() async throws -> Session {
        guard let identifier = Self.containerIdentifier else {
            throw LibraryError(description: "CloudKit sync requires a signed build with the iCloud container named in CooolCloudKitContainer.")
        }
        let container = CKContainer(identifier: identifier)
        guard try await container.accountStatus() == .available else {
            throw LibraryError(description: "Sign in to iCloud on this Mac to use private library sync.")
        }
        let user = try await container.userRecordID()
        let account = [identifier, user.zoneID.ownerName, user.zoneID.zoneName, user.recordName]
        let key = "cooolCloudState." + Self.hash(Data(account.joined(separator: "\u{1F}").utf8))
        return Session(container: container, user: user, accountKey: key)
    }

    private func requireCurrentAccount(_ session: Session) async throws {
        guard try await session.container.userRecordID() == session.user else { throw accountChanged }
    }

    private func cloudHead(in session: Session) async throws -> CloudHead? {
        let result = try await session.container.privateCloudDatabase.records(for: [Self.recordID], desiredKeys: ["digest"])
        guard let record = result[Self.recordID] else {
            throw LibraryError(description: "CloudKit did not return the library record.")
        }
        do {
            let head = try record.get()
            guard let changeTag = head.recordChangeTag, let digest = head["digest"] as? String else {
                throw LibraryError(description: "The CloudKit library metadata is incomplete.")
            }
            return CloudHead(record: head, state: State(changeTag: changeTag, digest: digest))
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func upload(_ local: LibraryBackup, digest: String, replacing head: CloudHead?, in session: Session) async throws -> Outcome {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("coool-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("library.cooolbackup")
        try local.write(to: file)

        let record = head?.record ?? CKRecord(recordType: Self.recordType, recordID: Self.recordID)
        record["archive"] = CKAsset(fileURL: file)
        record["digest"] = "vault1:" + digest
        try Task.checkCancellation()
        try await requireCurrentAccount(session)
        do {
            let response = try await session.container.privateCloudDatabase.modifyRecords(
                saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged
            )
            guard let item = response.saveResults[Self.recordID], let changeTag = try item.get().recordChangeTag else {
                throw LibraryError(description: "CloudKit did not confirm the library upload.")
            }
            try await requireCurrentAccount(session)
            remember(State(changeTag: changeTag, digest: "vault1:" + digest), for: session.accountKey)
            return .uploaded
        } catch {
            guard Self.isVersionConflict(error) else { throw error }
            try await requireCurrentAccount(session)
            return .conflict(conflict(try await cloudHead(in: session), localDigest: digest, in: session))
        }
    }

    private func download(_ head: CloudHead, localDigest: String, in session: Session) async throws -> Outcome {
        try Task.checkCancellation()
        do {
            let record = try await session.container.privateCloudDatabase.record(for: Self.recordID)
            try await requireCurrentAccount(session)
            guard record.recordChangeTag == head.state.changeTag else {
                return .conflict(conflict(try await cloudHead(in: session), localDigest: localDigest, in: session))
            }
            guard let file = (record["archive"] as? CKAsset)?.fileURL else {
                throw LibraryError(description: "The CloudKit library archive is missing.")
            }
            let bytes = try Data(contentsOf: file)
            if head.state.digest.hasPrefix("vault1:"), !LibraryKey.isSealed(bytes) { throw VaultError.wrongKey }
            let backup = try readBackupForRestore(bytes)
            let actual = try Self.digest(of: backup)
            let matches: Bool
            if head.state.digest.hasPrefix("vault1:") { matches = "vault1:" + actual == head.state.digest }
            else {
                matches = try actual == head.state.digest || Self.digest(of: backup, legacySchedules: true) == head.state.digest
            }
            guard matches else {
                throw LibraryError(description: "The CloudKit library archive does not match its recorded content.")
            }
            return .download(Download(backup: backup, accountKey: session.accountKey, localDigest: localDigest, state: head.state))
        } catch {
            guard Self.isVersionConflict(error) else { throw error }
            try await requireCurrentAccount(session)
            return .conflict(conflict(try await cloudHead(in: session), localDigest: localDigest, in: session))
        }
    }

    private func conflict(_ head: CloudHead?, localDigest: String, in session: Session) -> Conflict {
        Conflict(accountKey: session.accountKey, localDigest: localDigest, cloudTag: head?.state.changeTag,
                 cloudModifiedAt: head?.record.modificationDate)
    }

    private func state(for accountKey: String) -> State? {
        guard let data = defaults.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    private func remember(_ state: State, for accountKey: String) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: accountKey)
            defaults.set(accountKey, forKey: Self.associatedAccountKey)
        }
    }

    private static func isVersionConflict(_ error: Error) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == .serverRecordChanged || cloudError.code == .unknownItem { return true }
        return cloudError.partialErrorsByItemID?.values.contains(where: isVersionConflict) == true
    }

    /// A capture timestamp or unordered Codable collection must not count as a library edit.
    nonisolated static func digest(of backup: LibraryBackup, legacySchedules: Bool = false) throws -> String {
        struct Content: Encodable {
            struct StableProject: Encodable {
                let project: Project
                let commitments: [String: Decimal]?
                let completedCostLines: [String]?

                init(_ input: Project) {
                    var project = input
                    self.commitments = input.estimate.commitments.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.uuidString, $0.value) }) }
                    self.completedCostLines = input.estimate.completedCostLines?.map(\.uuidString).sorted()
                    project.estimate.commitments = nil
                    project.estimate.completedCostLines = nil
                    self.project = project
                }
            }
            let projects: [StableProject]
            let clients: [Client]
            let reservedInvoiceNumbers: [String]
            let directoryNumbers: [NumberReservation]?
            let freelancers: [Freelancer]?
            let settings: LibraryBackup.Settings?
        }
        let projects = backup.library.projects.sorted { $0.id.uuidString < $1.id.uuidString }.map(Content.StableProject.init)
        let clients = (backup.library.clients ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.userInfo[Schedule.legacyDigestKey] = legacySchedules
        let reserved = Set((backup.library.reservedInvoiceNumbers ?? []).map { $0.uppercased() }).sorted()
        return try hash(encoder.encode(Content(projects: projects, clients: clients,
                                               reservedInvoiceNumbers: reserved,
                                               directoryNumbers: backup.library.numberReservations?.sorted {
                                                   ($0.kind.rawValue, $0.number, $0.owner.uuidString) < ($1.kind.rawValue, $1.number, $1.owner.uuidString)
                                               }, freelancers: backup.library.freelancers?.sorted { $0.id.uuidString < $1.id.uuidString },
                                               settings: backup.settings)))
    }

    private nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
