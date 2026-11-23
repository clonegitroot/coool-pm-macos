import Foundation

func check(_ label: String, _ condition: @autoclosure () throws -> Bool) throws {
    let result = try condition()
    precondition(result, label)
}
func rejects(_ body: () throws -> Void) {
    do { try body(); preconditionFailure("Invalid draft accepted") } catch { }
}
let response = #"{"introduction":"Dear client, please find our proposal.","assumptions":["One filming day"],"questions":["Are subtitles required?"],"findings":[],"phases":[{"name":"Preparation","scope":"Planning","deliverables":"Shot list","lines":[{"role":"Producer","pricing":"producer","quantity":1.5,"rate":99999}]}]}"#
let result = try AIDraft.decode(response, teamPlanning: false)
let quotedQuantity = response.replacingOccurrences(of: "1.5", with: #""1.5""#)
try check("A quoted numeric quantity preserves decimal days",
          try AIDraft.decode(quotedQuantity, teamPlanning: false).phases[0].lines[0].quantity == 1.5)
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "1.5", with: #""1.5 hours""#), teamPlanning: false) }
let listDeliverables = response.replacingOccurrences(of: "\"deliverables\":\"Shot list\"", with: "\"deliverables\":[\"Shot list\",\"Interview notes\"]")
try check("Equivalent deliverable lists are accepted", try AIDraft.decode(listDeliverables, teamPlanning: false).phases[0].deliverables == "Shot list\nInterview notes")
try check("Progressive token abbreviation resolves to the same method", AIPricing.basis("own_progress") == .producer)
try check("Model-supplied prices ignored", result.phases[0].lines[0].rate == 0)
try check("Pricing names normalize casing", try AIDraft.decode(response.replacingOccurrences(of: "producer", with: "Producer"), teamPlanning: false).phases[0].lines[0].basis == .producer)
try check("Fenced JSON supported", try AIDraft.decode("```json\n" + response + "\n```", teamPlanning: false).phases.count == 1)
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "1.5", with: "-1"), teamPlanning: false) }
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "producer", with: "crew"), teamPlanning: false) }
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "producer", with: "unsupported"), teamPlanning: true) }
rejects { _ = try AIDraft.decode(String(response.dropLast()), teamPlanning: true) }
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "1.5", with: "1.555"), teamPlanning: true) }

var estimate = Estimate()
estimate.customTiers = [RateTier(lastDay: nil, rate: 700)]
estimate.phases = []
var edit = try AIDraftEdit(estimate: estimate, language: "en")
try edit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: true, to: &estimate, teamPlanning: false)
try check("Own rates stay deterministic", estimate.calculate().totals.sales == 1050)
try check("Proposal introduction uses the normal draft field", estimate.documentDrafts?["proposal-en"]?.letter == result.introduction)
estimate.purchaseOrder = "SAFE-PO"
try edit.undo(in: &estimate)
try check("Undo preserves unrelated edits", estimate.phases.isEmpty && estimate.purchaseOrder == "SAFE-PO")

var stale = try AIDraftEdit(estimate: estimate, language: "en")
estimate.projectRebatePercent = 10
rejects { try stale.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &estimate, teamPlanning: false) }
var locked = estimate
locked.acceptedProposalID = UUID()
var lockedEdit = try AIDraftEdit(estimate: locked, language: "en")
rejects { try lockedEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: true, to: &locked, teamPlanning: false) }

var linkedEdit = try AIDraftEdit(estimate: estimate, language: "en")
try linkedEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &estimate, teamPlanning: false)
estimate.timeRecords = [TimeRecord(lineID: estimate.phases[0].entries[0].id, days: 1, rate: 200)]
rejects { try linkedEdit.undo(in: &estimate) }

var promptProject = Estimate()
promptProject.title = "Synthetic launch"
promptProject.client = "PRIVATE CLIENT SHOULD BE OMITTED"
promptProject.clientNumber = "SECRET NUMBER"
promptProject.purchaseOrder = "PRIVATE PO"
promptProject.files = [ProjectFile(kind: .supplier, name: "PRIVATE ATTACHMENT", data: Data("PRIVATE CONTENT".utf8))]
let prompt = try AIPrompt.make(estimate: promptProject, brief: "A film", language: "en", review: false, features: UsageProfile.solo.features)
try check("Prompt excludes unrelated private fields", !prompt.contains("PRIVATE") && !prompt.contains("SECRET NUMBER"))
func contextJSON(_ prompt: String) throws -> [String: Any] {
    let body = prompt.components(separatedBy: "PROJECT CONTEXT:\n").last!.components(separatedBy: "\nUSER BRIEF:").first!
    return try JSONSerialization.jsonObject(with: Data(body.utf8)) as! [String: Any]
}
let soloCategories = try contextJSON(prompt)["pricingCategories"] as! [[String: Any]]
try check("Solo pricing restrictions", !soloCategories.contains { ["external_crew", "internal_crew"].contains($0["method"] as! String) })
try check("No example assumption text", !prompt.contains("An uncertain estimate") && !prompt.contains("An unanswered question"))
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "One filming day", with: "An uncertain estimate"), teamPlanning: false) }
rejects { _ = try AIDraft.decode(response.replacingOccurrences(of: "Producer", with: "Own work"), teamPlanning: false) }

rejects { _ = try AIDraft.decode(response, teamPlanning: true, review: true) }
let reviewOutput = #"{"introduction":"","assumptions":[],"questions":["What should be delivered?"],"findings":[],"phases":[]}"#
try check("Review-only output accepted", try AIDraft.decode(reviewOutput, teamPlanning: true, review: true).phases.isEmpty)
for basis in Pricing.allCases {
    let token = AIPricing.token(basis)
    let value = try AIDraft.decode(response.replacingOccurrences(of: "\"producer\"", with: "\"" + token + "\""), teamPlanning: true)
    try check("All calculation methods round-trip", value.phases[0].lines[0].basis == basis)
}
var catalog = PricingCatalog()
let custom = PricingPreset(name: "Integrated camera team", basis: .team)
try catalog.save(custom, locale: Locale(identifier: "en"))
let customResponse = response.replacingOccurrences(of: "\"producer\"", with: "\"preset:" + custom.id.uuidString.lowercased() + "\"")
let customDraft = try AIDraft.decode(customResponse, teamPlanning: true, catalog: catalog)
let customEntry = customDraft.selectedPhases(Set(customDraft.phases.map(\.id)), language: "en")[0].entries[0]
try check("Custom category keeps its method and identity", customEntry.pricing == .team && customEntry.pricingPresetID == custom.id && customEntry.pricingLabel == custom.name)
rejects { _ = try AIDraft.decode(customResponse, teamPlanning: false, catalog: catalog) }
rejects { _ = try AIDraft.decode(customResponse, teamPlanning: true) }

var mixed = Estimate()
mixed.customTiers = [RateTier(lastDay: nil, rate: 700)]
mixed.projectRebatePercent = 10
mixed.phases = [Phase(name: "Mixed methods", entries: [
    Entry(name: "Producer", pricing: .producer, quantity: 1, cost: 200),
    Entry(name: "Director", pricing: .override, quantity: 2, rate: 600, cost: 200),
    Entry(name: "Camera operator", pricing: .team, quantity: 2, rate: 500, cost: 350),
    Entry(name: "Sound supplier", pricing: .crew, quantity: 1, rate: 400, cost: 300),
    Entry(name: "Design package", pricing: .fee, quantity: 1, rate: 900, cost: 100),
    Entry(name: "Music licence", pricing: .expense, quantity: 2, rate: 100, cost: 80),
    Entry(name: "Camera kit", pricing: .equipment, quantity: 1, rate: 200, cost: 50)
])]
let totals = mixed.calculate().totals
try check("Mixed pricing uses engine rebates and DB stages", totals.sales == 4200 && totals.db1 == 3740 && totals.db2 == 2290)
var fixedDaysEdit = try AIDraftEdit(estimate: mixed, language: "en")
mixed.countOverrides = true
rejects { try fixedDaysEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &mixed, teamPlanning: true) }

var historical = mixed
historical.title = "REFERENCE STUDIO FILM"
historical.client = "OMIT HISTORICAL CLIENT"
historical.purchaseOrder = "OMIT HISTORICAL PO"
historical.files = [ProjectFile(kind: .supplier, name: "OMIT HISTORICAL FILE", data: Data("OMIT HISTORICAL CONTENT".utf8))]
historical.phases[0].scopes = ["en": "Reference filming scope"]
let reference = Project(id: UUID(), estimate: historical)
let withReference = try AIPrompt.make(estimate: promptProject, brief: "Use the selected studio film as a reference", language: "en", review: false, features: .full, catalog: catalog, references: [reference])
try check("Only explicitly selected history is included", withReference.contains("REFERENCE STUDIO FILM") && !prompt.contains("REFERENCE STUDIO FILM"))
try check("Historical private fields remain excluded", !withReference.contains("OMIT HISTORICAL"))
try check("References include actual role and scope", withReference.contains("Reference filming scope") && withReference.contains("Camera operator"))
let referenceContexts = try contextJSON(withReference)["referenceProjects"] as! [[String: Any]]
try check("Partial reference summary is disclosed", referenceContexts[0]["summaryIsPartial"] as? Bool == true)
rejects { _ = try AIPrompt.make(estimate: promptProject, brief: "Film", language: "en", review: false, features: .full, references: [reference, reference]) }
let compactResponse = #"{"findings":["Production has no priced sound recording."],"questions":[]}"#
let compactReview = try AIDraft.decode(compactResponse, teamPlanning: true, review: true)
try check("Compact reviews decode without draft fields", compactReview.findings.count == 1 && compactReview.phases.isEmpty)
rejects { _ = try AIDraft.decode(#"{"findings":[],"introduction":"Unrequested draft text"}"#, teamPlanning: true, review: true) }

promptProject.phases = [Phase(name: "Shoot", entries: [Entry(name: "Camera", pricing: .crew, quantity: 2, rate: 600, cost: 350)], startDate: .now)]
promptProject.clientID = UUID()
promptProject.invoiceClientID = UUID()
promptProject.folderID = UUID()
promptProject.projectNumber = "FIXTURE-001"
promptProject.status = .active
promptProject.clientRebatePercent = 10
let copy = promptProject.duplicateCalculation(titled: "Synthetic copy")
try check("Duplicate is a fresh inquiry with no client or document references",
          copy.currentStatus == .inquiry && copy.clientID == nil && copy.invoiceClientID == nil && copy.client.isEmpty &&
          copy.folderID == nil && copy.projectNumber == nil && copy.purchaseOrder == nil && copy.files == nil &&
          copy.documents == nil && copy.clientRebatePercent == nil)
try check("Duplicate keeps line pricing and creates new identifiers", copy.phases[0].id != promptProject.phases[0].id &&
          copy.phases[0].startDate == nil && copy.phases[0].entries[0].id != promptProject.phases[0].entries[0].id &&
          copy.calculate().totals.sales == 1200)
let reviewPrompt = try AIPrompt.make(estimate: promptProject, brief: "", language: "en", review: true,
                                     features: UsageProfile.solo.features, references: [reference])
let reviewData = try contextJSON(reviewPrompt)
try check("Review receives computed revenue without hidden costs or references",
          reviewData["net"] as? Int == 1200 && reviewData["db1"] == nil && reviewData["db2"] == nil &&
          !reviewPrompt.contains("REFERENCE STUDIO FILM") && !reviewPrompt.contains("PRIVATE"))
promptProject.phases = (0...12).map { _ in Phase() }
rejects { _ = try AIPrompt.make(estimate: promptProject, brief: "A film", language: "en", review: true, features: .full) }
print("AI draft validation, deterministic pricing, locked-state guards, safe undo and scoped prompts passed.")

// Reused amounts must come from the selected record, never from model monetary fields.
var rateSource = Estimate()
rateSource.title = "Synthetic rate reference"
rateSource.customTiers = [RateTier(lastDay: 2, rate: 900), RateTier(lastDay: nil, rate: 750)]
rateSource.phases = [Phase(name: "Production", entries: [Entry(name: "Camera operator", pricing: .team, quantity: 2, hoursPerDay: 10, rate: 650, cost: 400)])]
let pricedReference = Project(id: UUID(), estimate: rateSource)
let sourceID = AIReferencePricing.id(project: pricedReference.id, line: rateSource.phases[0].entries[0].id)
let crewOutput = response.replacingOccurrences(of: "Producer", with: "Camera operator").replacingOccurrences(of: "\"producer\"", with: "\"internal_crew\"")
let reused = try AIDraft.decode(crewOutput, teamPlanning: true, references: [pricedReference])
try check("Exact role/method uses reference prices", reused.phases[0].lines[0].rate == 650 && reused.phases[0].lines[0].cost == 400 && reused.phases[0].lines[0].hoursPerDay == 10)
let translated = crewOutput.replacingOccurrences(of: "Camera operator", with: "Kameraperson").replacingOccurrences(of: "\"quantity\":1.5", with: "\"referenceLineID\":\"" + sourceID + "\",\"quantity\":1.5")
try check("Reference IDs support translated roles", try AIDraft.decode(translated, teamPlanning: true, references: [pricedReference]).phases[0].lines[0].rate == 650)
try check("Unselected records cannot supply prices", try AIDraft.decode(translated, teamPlanning: true).phases[0].lines[0].rate == 0)
try check("Pricing methods never silently change", try AIDraft.decode(translated.replacingOccurrences(of: "internal_crew", with: "external_crew"), teamPlanning: true, references: [pricedReference]).phases[0].lines[0].rate == 0)
try check("Hidden costs stay excluded", try AIDraft.decode(translated, teamPlanning: true, references: [pricedReference], includeCosts: false).phases[0].lines[0].cost == 0)
var conflicting = rateSource
conflicting.phases[0].entries[0].rate = 700
let conflictReference = Project(id: UUID(), estimate: conflicting)
try check("Ambiguous matches stay unpriced", try AIDraft.decode(crewOutput, teamPlanning: true, references: [pricedReference, conflictReference]).phases[0].lines[0].rate == 0)

var unfinished = Estimate()
unfinished.phases = []
unfinished.customTiers = [RateTier(lastDay: nil, rate: 0)]
let originalUnpriced = unfinished
var unpricedEdit = try AIDraftEdit(estimate: unfinished, language: "en")
try unpricedEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &unfinished, teamPlanning: true)
try check("Zero-price drafts can be applied", unfinished.phases.count == 1 && unfinished.calculate().totals.sales == 0)
try unpricedEdit.undo(in: &unfinished)
var ownRateEdit = try AIDraftEdit(estimate: unfinished, language: "en")
try ownRateEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &unfinished, teamPlanning: true, rateReference: rateSource)
try check("Reference own schedule applies to the calculation", unfinished.rateTiers == rateSource.rateTiers && unfinished.calculate().totals.sales == 1350)
try ownRateEdit.undo(in: &unfinished)
try check("Undo restores prior own schedule", unfinished.customTiers == originalUnpriced.customTiers && unfinished.appliedDayRateName == originalUnpriced.appliedDayRateName && unfinished.phases.isEmpty)
print("Reference line rates, source IDs, hidden costs, ambiguous matches, unpriced drafts and schedule undo passed.")

var emptyScheduleReference = rateSource
emptyScheduleReference.customTiers = []
var emptyScheduleEdit = try AIDraftEdit(estimate: unfinished, language: "en")
try emptyScheduleEdit.apply(result, selected: Set(result.phases.map(\.id)), includeLetter: false, to: &unfinished, teamPlanning: true, rateReference: emptyScheduleReference)
try check("Empty reference schedules stay editable and unpriced", unfinished.calculate().totals.sales == 0 && unfinished.phases.count == 1)
