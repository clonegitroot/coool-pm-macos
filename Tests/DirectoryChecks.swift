import Foundation
import CooolSQLCipher

func runDirectoryChecks(in folder: URL) throws {
    let key = LibraryKey.generate()
    let path = folder.appendingPathComponent("Directory.sqlite")
    let database = try ProjectDatabase(url: path, vaultKey: key)
    var profile = BusinessProfile()
    profile.numbering = NumberingPreferences(prefix: "C", digits: 2, randomize: false)
    profile.defaultPaymentDays = 21

    var client = try database.insertClient(name: "Example Studio", profile: profile)
    precondition(client.number == "C01" && client.terms == "21 days")
    precondition(client.website == nil)
    client.website = "example.org"
    client.projectAcronym = "EX"
    let nda = DirectoryFile(name: "demo.txt", data: Data("Fictional NDA".utf8))
    client.nda = nda
    client.contract = nda
    try database.updateClient(client)

    let proposal = ExportedDocument(filename: "Proposal.pdf", data: Data("Proposal".utf8),
                                    date: .now, proposal: true, net: 100, phaseFees: [])
    let alternate = Client(number: "ZZ", name: "Alternate Studio")
    try database.saveClient(alternate)
    var manualEstimate = Estimate()
    manualEstimate.clientID = alternate.id
    var manual = try database.insert(Project(id: UUID(), estimate: manualEstimate))
    manual = try database.assignProjectNumber(to: manual.id)
    precondition(manual.estimate.projectNumber == "ZZ-001")
    let assignedAgain = try database.assignProjectNumber(to: manual.id)
    precondition(assignedAgain.estimate.projectNumber == manual.estimate.projectNumber)
    manual.estimate.clientID = client.id
    manual.estimate.documents = [proposal]
    manual = try database.save(manual)
    precondition(manual.estimate.projectNumber == "ZZ-001")
    try database.deleteProject(id: manual.id)

    var draft = try database.insert(Project(id: UUID(), estimate: Estimate()))
    precondition(draft.estimate.projectNumber == nil)
    draft.estimate.clientID = alternate.id
    draft = try database.save(draft)
    precondition(draft.estimate.projectNumber == nil)
    draft.estimate.clientID = client.id
    draft = try database.save(draft)
    draft.estimate.documents = [ExportedDocument(filename: "Invoice draft.pdf", data: Data("Draft".utf8),
                                                date: .now, proposal: false, net: 100, phaseFees: [])]
    draft = try database.save(draft)
    let draftReservations = try database.numberReservations(kind: .project)
    precondition(draft.estimate.projectNumber == nil && draftReservations.map(\.number) == ["ZZ-001"])
    draft.estimate.documents = [proposal]
    draft = try database.save(draft)
    precondition(draft.estimate.projectNumber == "EX-001")
    draft.estimate.clientID = alternate.id
    draft.estimate.documents = nil
    draft = try database.save(draft)
    precondition(draft.estimate.projectNumber == "EX-001")
    try database.deleteProject(id: draft.id)

    var estimate = Estimate()
    estimate.clientID = client.id
    var next = try database.insert(Project(id: UUID(), estimate: estimate))
    precondition(next.estimate.projectNumber == nil)
    next.estimate.files = [ProjectFile(kind: .proposal, name: "Sent proposal.pdf", data: Data("Sent proposal".utf8))]
    next = try database.save(next)
    precondition(next.estimate.projectNumber == "EX-002")

    let person = Freelancer(name: "Demo Freelancer", website: "https://example.org", dayRate: 620, nda: nda)
    try database.saveFreelancer(person)
    let snapshot = try database.archive()
    try database.deleteClient(id: client.id)
    let third = try database.insertClient(name: "Second Studio", profile: profile)
    precondition(third.number == "C02")
    do {
        try database.saveClient(Client(number: "c01", name: "Conflicting client"))
        preconditionFailure("Reused a deleted client number")
    } catch is LibraryError {}
    try database.replaceLibrary(try JSONDecoder().decode(LibraryArchive.self, from: JSONEncoder().encode(snapshot)))
    let restored = try database.clients().first!
    precondition(restored.nda == nda && restored.contract == nda && restored.website == "example.org")
    let restoredFreelancers = try database.freelancers()
    precondition(restoredFreelancers == [person])
    let afterRestore = try database.insertClient(name: "Third Studio", profile: profile)
    precondition(afterRestore.number == "C03")
    var afterProjectRestore = try database.insert(Project(id: UUID(), estimate: estimate))
    precondition(afterProjectRestore.estimate.projectNumber == nil)
    afterProjectRestore.estimate.documents = [proposal]
    afterProjectRestore = try database.save(afterProjectRestore)
    precondition(afterProjectRestore.estimate.projectNumber == "EX-003")

    // A previously saved numeric client ID remains valid across migration.
    let legacyPath = folder.appendingPathComponent("LegacyDirectory.sqlite")
    let legacy = Client(number: "0007", name: "Old Example Studio")
    var oldProject = Project(id: UUID(), estimate: Estimate())
    oldProject.estimate.clientID = legacy.id
    var handle: OpaquePointer?
    precondition(sqlite3_open(legacyPath.path, &handle) == SQLITE_OK)
    let encoder = JSONEncoder()
    let clientJSON = String(decoding: try encoder.encode(legacy), as: UTF8.self)
    let projectJSON = String(decoding: try encoder.encode(oldProject.estimate), as: UTF8.self)
    let schema = """
    CREATE TABLE projects(id TEXT PRIMARY KEY NOT NULL, data TEXT NOT NULL);
    CREATE TABLE clients(id TEXT PRIMARY KEY, number TEXT NOT NULL UNIQUE COLLATE NOCASE, data TEXT NOT NULL);
    INSERT INTO clients VALUES ('\(legacy.id.uuidString)','0007','\(clientJSON)');
    INSERT INTO projects VALUES ('\(oldProject.id.uuidString)','\(projectJSON)');
    """
    precondition(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(handle)
    let migrated = try ProjectDatabase(url: legacyPath, vaultKey: key)
    let migratedClient = try migrated.clients().first
    precondition(migratedClient?.website == nil)
    let migratedProject = try migrated.project(id: oldProject.id)
    precondition(migratedClient?.number == "0007" && migratedProject?.estimate.projectNumber == nil)
    try migrated.deleteClient(id: legacy.id)
    do {
        try migrated.saveClient(Client(number: "0007", name: "Duplicate"))
        preconditionFailure("Reused migrated client number")
    } catch is LibraryError {}

    // Independent database connections allocate from the same series.
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "directory-checks", attributes: .concurrent)
    let failures = DirectoryFailures()
    let config = profile
    estimate.documents = [proposal]
    let projectTemplate = estimate
    for worker in 0..<5 {
        queue.async(group: group) {
            do {
                let db = try ProjectDatabase(url: path, vaultKey: key)
                _ = try db.insertClient(name: "Parallel Studio", profile: config)
                if worker.isMultiple(of: 2) {
                    var draft = projectTemplate
                    draft.documents = nil
                    let project = try db.insert(Project(id: UUID(), estimate: draft))
                    _ = try db.assignProjectNumber(to: project.id)
                } else {
                    _ = try db.insert(Project(id: UUID(), estimate: projectTemplate))
                }
            } catch { failures.record(error) }
        }
    }
    group.wait()
    precondition(failures.messages.isEmpty, failures.messages.joined(separator: ", "))
    let parallelClients = try database.clients().filter { $0.name == "Parallel Studio" }
    let projectNumbers = try database.all().compactMap(\.estimate.projectNumber)
    precondition(parallelClients.count == 5 && Set(parallelClients.map(\.number)).count == 5)
    precondition(projectNumbers.count == 7 && Set(projectNumbers).count == 7)
    print("Directory, legacy migration, reservation, restore and concurrent allocation checks passed.")
}

private final class DirectoryFailures: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var messages = [String]()
    func record(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(error.localizedDescription)
    }
}
