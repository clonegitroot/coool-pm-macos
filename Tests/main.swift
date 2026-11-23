import Foundation
func check(_ value: Bool) { precondition(value) }
var estimate = Estimate()
estimate.customTiers = [RateTier(lastDay: nil, rate: 900)]
estimate.phases = [Phase(name: "Demo production", entries: [Entry(quantity: 2)])]
check(estimate.calculate().totals.sales == 1800)
estimate.projectRebatePercent = 10
check(estimate.calculate().totals.sales == 1620)
estimate.phases[0].entries.append(Entry(name: "External crew", pricing: .crew, quantity: 1, rate: 500, cost: 300))
check(estimate.calculate().totals.sales == 2120)
let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: folder) }
VaultSession.shared.unlock(.generate())
let database = try ProjectDatabase(url: folder.appendingPathComponent("Demo.sqlite"), vaultKey: .generate())
let client = try database.insertClient(name: "Demo Studio")
check(client.number.range(of: "^KD[0-9]{4}$", options: .regularExpression) != nil)
let project = Project(id: UUID(), estimate: estimate)
try database.insert(project)
let restored = try database.all()
check(restored.count == 1)
print("Synthetic calculation and database checks passed.")

try runDirectoryChecks(in: folder)

try runProfileChecks()
