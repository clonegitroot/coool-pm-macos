import Foundation
import CooolSQLCipher

struct Project: Identifiable, Codable {
    let id: UUID
    var estimate: Estimate
}

struct ClientContact: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var role = ""
    var email = ""
    var phone = ""
    var archivedAt: Date?

    var displayName: String { name.isEmpty ? email : name }

    mutating func trimFields() {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DirectoryFile: Codable, Equatable {
    var name: String
    var data: Data
}

struct Freelancer: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var role = ""
    var email = ""
    var phone = ""
    var website: String?
    var dayRate: Decimal = 0
    var nda: DirectoryFile?
    var archivedAt: Date?
}

struct NumberReservation: Codable {
    enum Kind: String, Codable { case client, project }
    var kind: Kind
    var number: String
    var owner: UUID
}

struct NumberingPreferences: Codable, Equatable {
    var prefix = "KD"
    var digits = 4
    var randomize = true

    func nextClientNumber(used: Set<String>) throws -> String {
        let width = min(8, max(2, digits))
        let limit = Int(pow(10.0, Double(width))) - 1
        let prefix = self.prefix.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var index = randomize ? Int.random(in: 1...limit) : 1
        let upper = Set(used.map { $0.uppercased() })
        for _ in 0..<limit {
            let candidate = prefix + String(format: "%0*ld", Int32(width), index)
            if !upper.contains(candidate) { return candidate }
            index = index == limit ? 1 : index + 1
        }
        throw LibraryError(description: "All client numbers in this format have been used. Increase the digit count in Settings.")
    }
}

struct Client: Identifiable, Codable {
    var id = UUID()
    var number: String
    var name: String
    var contact = ""
    var email = ""
    var address = ""
    var terms = "30 days"
    var website: String?

    var contacts: [ClientContact]?
    var primaryContactID: UUID?
    var projectFolders: [ProjectFolder]?
    var archivedAt: Date?
    var rebatePercent: Decimal?
    var electronicInvoice: ElectronicRecipientDefaults?
    var projectAcronym: String?
    var nda: DirectoryFile?
    var contract: DirectoryFile?

    var contactPeople: [ClientContact] {
        if let contacts { return contacts }
        if contact.isEmpty && email.isEmpty { return [] }
        return [ClientContact(id: id, name: contact, email: email)]
    }

    var primaryContact: ClientContact? {
        activeContacts.first { $0.id == primaryContactID } ?? activeContacts.first
    }

    var activeContacts: [ClientContact] { contactPeople.filter { $0.archivedAt == nil } }

    func recipient(attentionTo id: UUID?) -> Client {
        var recipient = self
        let person = activeContacts.first { $0.id == id } ?? primaryContact
        recipient.contact = person?.name ?? ""
        recipient.email = person?.email ?? ""
        return recipient
    }

    mutating func normalizeContacts() throws {
        guard var contacts else { return }
        for index in contacts.indices { contacts[index].trimFields() }
        guard contacts.allSatisfy({ !$0.displayName.isEmpty }), Set(contacts.map(\.id)).count == contacts.count else {
            throw LibraryError(description: "Enter a name or email for every contact.")
        }
        self.contacts = contacts
        let primary = primaryContact
        primaryContactID = primary?.id
        contact = primary?.name ?? ""
        email = primary?.email ?? ""
    }


}

struct LibraryArchive: Codable {
    var version = 2
    var projects: [Project]
    var clients: [Client]?
    var reservedInvoiceNumbers: [String]?
    var numberReservations: [NumberReservation]?
    var freelancers: [Freelancer]?
}

struct LibraryError: LocalizedError {
    let description: String
    var errorDescription: String? {
        let language = UserDefaults.standard.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .system
        return AppLanguage.text(description, fallback: description, locale: language.locale)
    }
}

final class ProjectDatabase {
    static func libraryURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: false)
        return support.appendingPathComponent("Coool PM/Projects.sqlite")
    }

    private var handle: OpaquePointer?
    init(url: URL, readOnly: Bool = false, vaultKey: LibraryKey? = nil, allowMigration: Bool = true) throws {
        let key = try vaultKey ?? VaultSession.shared.key()
        if try EncryptedSQLite.isPlain(at: url) {
            guard !readOnly, allowMigration else { throw VaultError.legacyOpen }
            try EncryptedSQLite.migratePlaintext(at: url, key: key)
        }
        if !readOnly {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        sqlite3_busy_timeout(handle, 2000)
        do {
            try EncryptedSQLite.apply(key, to: handle)
            if !readOnly { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        } catch {
            sqlite3_close(handle)
            handle = nil
            throw error
        }
        guard !readOnly else { return }
        try execute("CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, number TEXT NOT NULL UNIQUE COLLATE NOCASE, data TEXT NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS reserved_invoice_numbers (number TEXT PRIMARY KEY COLLATE NOCASE)")
        try execute("CREATE TABLE IF NOT EXISTS directory_numbers (kind TEXT NOT NULL, number TEXT NOT NULL COLLATE NOCASE, owner TEXT NOT NULL, PRIMARY KEY(kind,number))")
        try execute("CREATE TABLE IF NOT EXISTS freelancers (id TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL)")
        try addMissing([])
    }
    deinit { sqlite3_close(handle) }

    private func failure() -> LibraryError {
        LibraryError(description: String(cString: sqlite3_errmsg(handle)))
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    var localChangeCount: Int64 { sqlite3_total_changes64(handle) }

    func changeVersion() throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA data_version", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return sqlite3_column_int64(statement, 0)
    }

    func all() throws -> [Project] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT id,data FROM projects ORDER BY rowid", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var projects = [Project]()
        var step = sqlite3_step(stmt)
        while step == SQLITE_ROW {
            guard let id = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) else { throw CocoaError(.fileReadCorruptFile) }
            let data = Data(String(cString: sqlite3_column_text(stmt, 1)).utf8)
            projects.append(Project(id: id, estimate: try JSONDecoder().decode(Estimate.self, from: data)))
            step = sqlite3_step(stmt)
        }
        guard step == SQLITE_DONE else { throw failure() }
        return projects
    }

    func project(id: UUID) throws -> Project? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT data FROM projects WHERE id = ?", -1, &statement, nil) == SQLITE_OK else {
            throw failure()
        }
        defer { sqlite3_finalize(statement) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, id.uuidString, -1, copy) == SQLITE_OK else { throw failure() }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            let data = Data(String(cString: sqlite3_column_text(statement, 0)).utf8)
            return Project(id: id, estimate: try JSONDecoder().decode(Estimate.self, from: data))
        case SQLITE_DONE:
            return nil
        default:
            throw failure()
        }
    }

    @discardableResult
    func save(_ project: Project) throws -> Project {
        try numberedWrite(project, sql: "INSERT INTO projects VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data")
    }

    @discardableResult
    func save(_ project: Project, ifVersionIs version: Int64?) throws -> Project {
        try execute("BEGIN IMMEDIATE")
        do {
            guard try changeVersion() == version else {
                throw LibraryError(description: "The library changed while you were editing. Review the refreshed project and try again.")
            }
            let stored = try save(project)
            try execute("COMMIT")
            return stored
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    @discardableResult
    func insert(_ project: Project) throws -> Project {
        try numberedWrite(project, sql: "INSERT INTO projects VALUES (?,?)")
    }

    private func directoryTransaction<T>(_ body: () throws -> T) throws -> T {
        let outer = sqlite3_get_autocommit(handle) != 0
        try execute(outer ? "BEGIN IMMEDIATE" : "SAVEPOINT directory_write")
        do {
            let result = try body()
            try execute(outer ? "COMMIT" : "RELEASE directory_write")
            return result
        } catch {
            try? execute(outer ? "ROLLBACK" : "ROLLBACK TO directory_write")
            if !outer { try? execute("RELEASE directory_write") }
            throw error
        }
    }

    private func directoryStatement(_ sql: String, _ arguments: [String] = []) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in arguments.enumerated() {
            if sqlite3_bind_text(statement, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) != SQLITE_OK {
                sqlite3_finalize(statement)
                throw failure()
            }
        }
        return statement
    }

    func numberReservations(kind: NumberReservation.Kind? = nil) throws -> [NumberReservation] {
        let query = "SELECT kind, number, owner FROM directory_numbers"
        let statement = try directoryStatement(query + (kind == nil ? "" : " WHERE kind=?") + " ORDER BY kind,number",
                                               kind.map { [$0.rawValue] } ?? [])
        defer { sqlite3_finalize(statement) }
        var results: [NumberReservation] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return results
            case SQLITE_ROW:
                guard let kind = NumberReservation.Kind(rawValue: String(cString: sqlite3_column_text(statement, 0))),
                      let owner = UUID(uuidString: String(cString: sqlite3_column_text(statement, 2))) else { throw CocoaError(.fileReadCorruptFile) }
                results.append(NumberReservation(kind: kind, number: String(cString: sqlite3_column_text(statement, 1)), owner: owner))
            default: throw failure()
            }
        }
    }

    private func reserve(_ number: String, for owner: UUID, kind: NumberReservation.Kind) throws {
        let identifier = number.uppercased()
        let statement = try directoryStatement("INSERT INTO directory_numbers VALUES (?,?,?) ON CONFLICT(kind,number) DO NOTHING",
                                               [kind.rawValue, identifier, owner.uuidString])
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
        guard sqlite3_changes(handle) == 0 else { return }
        let check = try directoryStatement("SELECT owner FROM directory_numbers WHERE kind=? AND number=?", [kind.rawValue, identifier])
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, String(cString: sqlite3_column_text(check, 0)) == owner.uuidString else {
            throw LibraryError(description: kind == .client ? "That client number has already been assigned." : "That project number has already been assigned.")
        }
    }

    func nextClientNumber(preferences: NumberingPreferences? = nil, additionallyReserved: Set<String> = []) throws -> String {
        let used = Set(try numberReservations(kind: .client).map(\.number)).union(additionallyReserved)
        return try (preferences ?? BusinessProfile.load().numbering ?? NumberingPreferences()).nextClientNumber(used: used)
    }

    func assignProjectNumber(to id: UUID, ifVersionIs expectedVersion: Int64? = nil) throws -> Project {
        try directoryTransaction {
            if let expectedVersion, try changeVersion() != expectedVersion {
                throw LibraryError(description: "The library changed while you were editing. Review the refreshed project and try again.")
            }
            guard var project = try project(id: id) else {
                throw LibraryError(description: "The project is unavailable.")
            }
            guard project.estimate.projectNumber == nil else { return project }
            project.estimate.projectNumber = try nextProjectNumber(clientID: project.estimate.clientID)
            project.estimate.provisionalProjectNumber = nil
            return try save(project)
        }
    }

    private func nextProjectNumber(clientID: UUID?) throws -> String {
        let client = try clientID.flatMap { id in try clients().first { $0.id == id } }
        let acronym = client?.projectAcronym?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let prefix = (acronym.isEmpty ? (client?.number.uppercased() ?? "PRJ") : acronym) + "-"
        let highest = try numberReservations(kind: .project).compactMap { record -> Int? in
            guard record.number.hasPrefix(prefix) else { return nil }
            return Int(record.number.dropFirst(prefix.count))
        }.max() ?? 0
        guard highest < Int.max else { throw LibraryError(description: "Project number series is exhausted.") }
        return prefix + String(format: "%03ld", highest + 1)
    }

    private func numberedWrite(_ input: Project, sql: String) throws -> Project {
        try directoryTransaction {
            var project = input
            if let number = try self.project(id: input.id)?.estimate.projectNumber {
                project.estimate.projectNumber = number
            }
            let hasProposal = project.estimate.documents?.contains(where: \.proposal) == true ||
                project.estimate.files?.contains(where: { $0.kind == .proposal }) == true
            if project.estimate.projectNumber == nil && hasProposal {
                project.estimate.projectNumber = try nextProjectNumber(clientID: project.estimate.clientID)
                project.estimate.provisionalProjectNumber = nil
            }
            if let number = project.estimate.projectNumber { try reserve(number, for: project.id, kind: .project) }
            try write(project, sql: sql)
            return project
        }
    }

    func freelancers() throws -> [Freelancer] {
        let statement = try directoryStatement("SELECT data FROM freelancers ORDER BY id")
        defer { sqlite3_finalize(statement) }
        var result: [Freelancer] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return result
            case SQLITE_ROW:
                let data = Data(String(cString: sqlite3_column_text(statement, 0)).utf8)
                result.append(try JSONDecoder().decode(Freelancer.self, from: data))
            default: throw failure()
            }
        }
    }

    func saveFreelancer(_ person: Freelancer) throws {
        guard !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, person.dayRate >= 0 else {
            throw LibraryError(description: "Enter a freelancer name and a nonnegative day rate.")
        }
        let data = String(decoding: try JSONEncoder().encode(person), as: UTF8.self)
        let statement = try directoryStatement("INSERT INTO freelancers VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data", [person.id.uuidString, data])
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func deleteFreelancer(id: UUID) throws { try delete(id, sql: "DELETE FROM freelancers WHERE id=?") }

    private func write(_ project: Project, sql: String) throws {
        let json = String(decoding: try JSONEncoder().encode(project.estimate), as: UTF8.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(stmt, 1, project.id.uuidString, -1, copy) == SQLITE_OK,
              sqlite3_bind_text(stmt, 2, json, -1, copy) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func clients() throws -> [Client] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT data FROM clients ORDER BY number", -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        var records = [Client]()
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_DONE: return records
            case SQLITE_ROW:
                let data = Data(String(cString: sqlite3_column_text(stmt, 0)).utf8)
                records.append(try JSONDecoder().decode(Client.self, from: data))
            default: throw failure()
            }
        }
    }

    func saveClient(_ record: Client) throws {
        try directoryTransaction { try writeClient(record) }
    }

    private func writeClient(_ record: Client) throws {
        var client = record
        client.number = client.number.trimmingCharacters(in: .whitespacesAndNewlines)
        client.projectAcronym = client.projectAcronym?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try client.normalizeContacts()
        guard !client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !client.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError(description: "Enter a company name and client number.")
        }
        if let percent = client.rebatePercent, !(0...100).contains(percent) || cents(percent) != percent {
            throw LibraryError(description: "Enter a rebate between 0 and 100 percent, with up to two decimal places.")
        }
        try reserve(client.number, for: client.id, kind: .client)
        let sql = "INSERT INTO clients VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET number=excluded.number,data=excluded.data"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(stmt) }
        let values = [client.id.uuidString, client.number, String(decoding: try JSONEncoder().encode(client), as: UTF8.self)]
        for (index, value) in values.enumerated() {
            guard sqlite3_bind_text(stmt, Int32(index + 1), value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw failure() }
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            if sqlite3_errcode(handle) == SQLITE_CONSTRAINT { throw LibraryError(description: "That client number is already in use.") }
            throw failure()
        }
    }

    func updateClient(_ client: Client) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            let old = try clients().first { $0.id == client.id }
            try saveClient(client)
            if old?.rebatePercent != client.rebatePercent {
                for var project in try all() where project.estimate.clientID == client.id && !project.estimate.calculationLocked {
                    project.estimate.clientRebatePercent = client.rebatePercent
                    try save(project)
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func insertClient(name: String, address: String = "", terms: String? = nil, profile: BusinessProfile = BusinessProfile.load()) throws -> Client {
        try execute("BEGIN IMMEDIATE")
        do {
            let client = Client(number: try nextClientNumber(preferences: profile.numbering), name: name, address: address, terms: terms ?? profile.newClientTerms)
            try saveClient(client)
            try execute("COMMIT")
            return client
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func editDraftCalculation(projectID: UUID, phases: [Phase], rebatePercent: Decimal? = nil, append: Bool = false) throws -> Project {
        try execute("BEGIN IMMEDIATE")
        do {
            guard var project = try project(id: projectID) else {
                throw LibraryError(description: "The project is unavailable.")
            }
            let estimate = project.estimate
            guard !estimate.calculationLocked, estimate.archivedAt == nil,
                  [.inquiry, .offered].contains(estimate.currentStatus), estimate.issuedInvoices?.isEmpty != false else {
                throw LibraryError(description: "Only active, unapproved drafts can be edited through MCP.")
            }
            if !append {
                let hasLinkedRecords = estimate.phases.contains { phase in
                    estimate.hasActivity(in: phase.id) || phase.entries.contains { estimate.hasActivity(on: $0.id) }
                }
                guard !hasLinkedRecords, estimate.changeOrders?.isEmpty != false else {
                    throw LibraryError(description: "This calculation has linked controlling records or change orders. Add new phases to preserve them.")
                }
            }
            guard !phases.isEmpty, phases.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  phases.flatMap(\.entries).allSatisfy({ $0.quantity >= 0 && $0.rate >= 0 && $0.cost >= 0 &&
                      (Decimal(0.25)...Decimal(24)).contains($0.effectiveHoursPerDay) }) else {
                throw LibraryError(description: "Enter named phases, nonnegative amounts and supported hours per day.")
            }
            if let rebatePercent {
                guard (0...100).contains(rebatePercent), cents(rebatePercent) == rebatePercent else {
                    throw LibraryError(description: "Enter a rebate between 0 and 100 percent, with up to two decimal places.")
                }
                project.estimate.projectRebatePercent = rebatePercent
            }
            project.estimate.phases = append ? estimate.phases + phases : phases
            try save(project)
            try execute("COMMIT")
            return project
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteClient(id: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for var project in try all() {
                var changed = false
                if project.estimate.clientID == id {
                    project.estimate.clientID = nil
                    project.estimate.client = ""
                    project.estimate.clientNumber = ""
                    project.estimate.folderID = nil
                    project.estimate.proposalContactID = nil
                    if project.estimate.invoiceClientID == nil { project.estimate.invoiceContactID = nil }
                    if !project.estimate.calculationLocked { project.estimate.clientRebatePercent = nil }
                    changed = true
                }
                if project.estimate.endClientID == id {
                    project.estimate.endClientID = nil
                    changed = true
                }
                if project.estimate.invoiceClientID == id {
                    project.estimate.invoiceClientID = nil
                    project.estimate.invoiceContactID = nil
                    changed = true
                }
                if changed { try save(project) }
            }
            try delete(id, sql: "DELETE FROM clients WHERE id = ?")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func deleteProject(id: UUID) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for invoice in try project(id: id)?.estimate.issuedInvoices ?? [] { try reserve(invoice.number) }
            try delete(id, sql: "DELETE FROM projects WHERE id = ?")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func delete(_ id: UUID, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, id.uuidString, -1, copy) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func resetLibrary(ifVersionIs version: Int64? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if let version, try changeVersion() != version {
                throw LibraryError(description: "The library changed during the recovery backup. Open Reset options and try again.")
            }
            try execute("DELETE FROM projects")
            try execute("DELETE FROM clients")
            try execute("DELETE FROM reserved_invoice_numbers")
            try execute("DELETE FROM freelancers")
            try execute("DELETE FROM directory_numbers")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    static func pendingResetURL(for library: URL) -> URL {
        library.deletingLastPathComponent().appendingPathComponent(".reset-pending.sqlite")
    }

    /// Keep the encrypted database recoverable until the reset has cleared its Keychain entry.
    func detachForFreshSetup(at url: URL, ifVersionIs version: Int64, complete: () throws -> Void) throws {
        let fm = FileManager.default
        let staged = Self.pendingResetURL(for: url)
        try execute("PRAGMA journal_mode=DELETE")
        try execute("BEGIN EXCLUSIVE")
        do {
            guard try changeVersion() == version else {
                throw LibraryError(description: "The library changed during the recovery backup. Open Reset options and try again.")
            }
            guard ["-wal", "-shm", "-journal"].allSatisfy({ !fm.fileExists(atPath: url.path + $0) }) else {
                throw LibraryError(description: "Close other copies of Coool PM before resetting the library.")
            }
            try fm.moveItem(at: url, to: staged)
            do {
                try execute("COMMIT")
                try complete()
            } catch {
                try fm.moveItem(at: staged, to: url)
                throw error
            }
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        try? fm.removeItem(at: staged)
    }

    func reservedInvoiceNumbers() throws -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT number FROM reserved_invoice_numbers ORDER BY number", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var numbers: [String] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            numbers.append(String(cString: sqlite3_column_text(statement, 0)))
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure() }
        return numbers
    }

    private func reserve(_ number: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "INSERT OR IGNORE INTO reserved_invoice_numbers VALUES (?)", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, number.uppercased(), -1, copy) == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func archive() throws -> LibraryArchive {
        try execute("BEGIN DEFERRED")
        do {
            let archive = LibraryArchive(projects: try all(), clients: try clients(),
                                         reservedInvoiceNumbers: try reservedInvoiceNumbers(),
                                         numberReservations: try numberReservations(), freelancers: try freelancers())
            try execute("COMMIT")
            return archive
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func replaceLibrary(_ archive: LibraryArchive, ifVersionIs version: Int64? = nil) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            if let version, try changeVersion() != version {
                throw LibraryError(description: "The library changed during the recovery backup. Try restoring again.")
            }
            for project in try all() { for invoice in project.estimate.issuedInvoices ?? [] { try reserve(invoice.number) } }
            for item in archive.numberReservations ?? [] { try reserve(item.number, for: item.owner, kind: item.kind) }
            try execute("DELETE FROM freelancers")
            for person in archive.freelancers ?? [] { try saveFreelancer(person) }
            for number in archive.reservedInvoiceNumbers ?? [] { try reserve(number) }
            try execute("DELETE FROM projects")
            try execute("DELETE FROM clients")
            for client in archive.clients ?? [] { try saveClient(client) }
            for project in archive.projects {
                if let number = project.estimate.projectNumber { try reserve(number, for: project.id, kind: .project) }
            }
            var numbers = Set<String>()
            for project in archive.projects {
                for invoice in project.estimate.issuedInvoices ?? [] {
                    guard numbers.insert(invoice.number.uppercased()).inserted else {
                        throw LibraryError(description: "The backup contains duplicate invoice numbers.")
                    }
                    try reserve(invoice.number)
                }
                try save(project)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func issueInvoice(projectID: UUID, preferredNumber: String?, ifVersionIs version: Int64? = nil,
                      make: (String, Estimate) throws -> IssuedInvoice) throws -> Project {
        try execute("BEGIN IMMEDIATE")
        do {
            if let version, try changeVersion() != version {
                throw LibraryError(description: "The library changed while you were editing. Review the refreshed project and try again.")
            }
            let projects = try all()
            guard var project = projects.first(where: { $0.id == projectID }) else {
                throw LibraryError(description: "The project is unavailable.")
            }
            let used = Set(projects.flatMap { $0.estimate.issuedInvoices ?? [] }.map { $0.number.uppercased() }).union(try reservedInvoiceNumbers())
            let number: String
            if let preferred = preferredNumber?.trimmingCharacters(in: .whitespacesAndNewlines), !preferred.isEmpty {
                number = preferred
            } else {
                let prefix = "RE-\(Calendar(identifier: .gregorian).component(.year, from: Date()))-"
                let latest = used.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil }.max() ?? 0
                guard latest < Int.max else { throw LibraryError(description: "Invoice number series is exhausted.") }
                number = prefix + String(format: "%04ld", latest + 1)
            }
            guard !used.contains(number.uppercased()) else {
                throw LibraryError(description: "That invoice number is already recorded in this library.")
            }
            let invoice = try make(number, project.estimate)
            guard invoice.number == number else { throw LibraryError(description: "The assigned invoice number changed.") }
            try project.estimate.validateInvoice(invoice)
            try reserve(number)
            project.estimate.issuedInvoices = (project.estimate.issuedInvoices ?? []) + [invoice]
            try save(project)
            try execute("COMMIT")
            return project
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func addMissing(_ projects: [Project], clients incomingClients: [Client] = [], reservedNumbers: [String] = []) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("INSERT OR IGNORE INTO directory_numbers SELECT 'client', UPPER(number), id FROM clients")
            let existingProjects = try all()
            var known = Set(existingProjects.map(\.id))
            let incomingProjects = projects.filter { known.insert($0.id).inserted }
            for project in existingProjects + incomingProjects {
                if let number = project.estimate.projectNumber { try reserve(number, for: project.id, kind: .project) }
            }
            var directory = try clients()
            for client in incomingClients where !directory.contains(where: { $0.id == client.id }) {
                try saveClient(client)
                directory.append(client)
            }
            var invoiceNumbers = Set(existingProjects.flatMap { $0.estimate.issuedInvoices ?? [] }.map { $0.number.uppercased() })
            for project in incomingProjects {
                for invoice in project.estimate.issuedInvoices ?? [] {
                    guard invoiceNumbers.insert(invoice.number.uppercased()).inserted else {
                        throw LibraryError(description: "The imported project contains an invoice number already recorded in this library.")
                    }
                    try reserve(invoice.number)
                }
                try save(project)
            }
            for number in reservedNumbers { try reserve(number) }
            // Older estimates stored company and number directly on each project.
            let legacy = try all().filter { $0.estimate.clientID == nil }
            let reserved = Set(legacy.map { $0.estimate.clientNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
            for var project in legacy.sorted(by: { !$0.estimate.clientNumber.isEmpty && $1.estimate.clientNumber.isEmpty }) {
                let name = project.estimate.client.trimmingCharacters(in: .whitespacesAndNewlines)
                let number = project.estimate.clientNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty || !number.isEmpty else { continue }
                let existing = directory.first {
                    if !number.isEmpty { return $0.number.caseInsensitiveCompare(number) == .orderedSame }
                    return $0.name.caseInsensitiveCompare(name) == .orderedSame
                }
                let client = try existing ?? Client(number: number.isEmpty ? try nextClientNumber(additionallyReserved: reserved) : number,
                                                name: name.isEmpty ? number : name)
                if existing == nil {
                    try saveClient(client)
                    directory.append(client)
                }
                project.estimate.clientID = client.id
                if !project.estimate.calculationLocked { project.estimate.clientRebatePercent = client.rebatePercent }
                try save(project)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
