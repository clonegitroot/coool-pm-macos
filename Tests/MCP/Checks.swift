private let testKey = LibraryKey.generate()
private var testEnabled = true
private var testPermissions: Set<String> = ["mcpAllowWrite", "mcpAllowFinancials"]
private var requestID = 0
private func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    precondition(condition(), label)
    print("PASS: \(label)")
}
private func send(_ server: MCPServer, _ method: String, _ params: JSONObject = [:]) -> JSONObject {
    requestID += 1
    let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0", "id": requestID, "method":method, "params":params])
    let response = server.receive(String(decoding:data,as:UTF8.self))!
    let wire = String(decoding: try! JSONSerialization.data(withJSONObject:response),as:UTF8.self)
    for secret in ["SECRET-CLIENT", "SECRET-PROJECT", "SECRET-PHASE", "SECRET-ENTRY", "SECRET-ADDRESS", "SECRET-TERMS"] {
        precondition(!wire.contains(secret), "Sensitive text leaked in MCP response")
    }
    return response
}
private func connect(_ flags: [String], _ path: String) throws -> MCPServer {
    let server = MCPServer(configuration: try Configuration(arguments: ["--library",path]+flags),
                           permissionEnabled: { testPermissions.contains($0) })
    let initialized = send(server,"initialize",["protocolVersion":"2025-06-18","capabilities":[:],"clientInfo":["name":"fixture","version":"1"]])
    check(initialized["result"] != nil,"Initialize \(flags)")
    _ = server.receive("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
    return server
}
private func call(_ server:MCPServer,_ name:String,_ args:JSONObject = [:]) -> JSONObject {
    send(server,"tools/call",["name":name,"arguments":args])
}
private func payload(_ response:JSONObject) -> JSONObject {
    let result=response["result"] as! JSONObject
    check(result["isError"] as? Bool != true,"Successful tool result")
    return result["structuredContent"] as! JSONObject
}
private func failed(_ response:JSONObject) -> Bool {
    response["error"] != nil || (response["result"] as? JSONObject)?["isError"] as? Bool == true
}
private let path=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("fixture.sqlite")
VaultSession.shared.unlock(testKey)
private let fixture=try ProjectDatabase(url:path,vaultKey:testKey)
private let writer=try connect(["--allow-write","--allow-financials"],path.path)
private let tools=(send(writer,"tools/list")["result"] as! JSONObject)["tools"] as! [JSONObject]
check(tools.count == 8,"Eight advertised tools")
private let client=payload(call(writer,"create_client",["name":"SECRET-CLIENT", "address":"SECRET-ADDRESS", "payment_terms":"SECRET-TERMS"]))["client"] as! JSONObject
private let project=payload(call(writer,"create_draft_project",["title":"SECRET-PROJECT","client_id":client["id"]!,"standard_phases":true]))["project"] as! JSONObject
check(client["name"] as? String == "Client " + (client["id"] as! String) && client["number"] == nil,"Client responses use aliases and omit client numbers")
check(project["title"] as? String == "Project " + (project["id"] as! String) && project["number"] == nil,"Project responses use aliases and omit project numbers")
_ = payload(call(writer,"list_clients"))
_ = payload(call(writer,"list_projects"))
private let id=project["id"] as! String
private let phase:JSONObject=["name":"SECRET-PHASE","entries":[["name":"SECRET-ENTRY","pricing":"own_fixed","quantity":2,"selling_rate":800,"unit_cost":100],["name":"Crew","pricing":"internal_crew","quantity":1,"selling_rate":600,"unit_cost":400]]]
check(failed(call(writer,"set_project_calculation",["project_id":id,"phases":[phase],"confirm_replace":false])),"Replacement requires explicit confirmation")
_ = payload(call(writer,"set_project_calculation",["project_id":id,"phases":[phase],"confirm_replace":true]))
_ = payload(call(writer,"append_project_phases",["project_id":id,"phases":[["name":"Delivery","entries":[]]]]))
private let details=payload(call(writer,"get_project",["project_id":id,"include_financials":true]))["project"] as! JSONObject
check((details["phases"] as! [JSONObject])[0]["name"] as? String == "Phase 1","Custom phase labels withheld")
check((((details["phases"] as! [JSONObject])[0]["entries"] as! [JSONObject])[0]["name"] as? String) == "Entry 1","Custom entry labels withheld")
check((details["phases"] as! [JSONObject]).count == 2,"Append preserves existing calculation")
check((details["financials"] as! JSONObject)["billable_net"] as? String == "2200","Calculation totals round-trip")
_ = payload(call(writer,"get_business_overview",["year":2026]))
private let reader=try connect([],path.path)
check(((send(reader,"tools/list")["result"] as! JSONObject)["tools"] as! [JSONObject]).count == 3,"Read-only mode hides financial and write tools")
check(failed(call(reader,"create_client",["name":"Forbidden"])),"Read-only mode rejects writes")
check(failed(call(reader,"get_project",["project_id":id,"include_financials":true])),"Financial access denied without permission")
private let publicDetails=payload(call(reader,"get_project",["project_id":id]))["project"] as! JSONObject
check(publicDetails["financials"] == nil && !(publicDetails["phases"] as! [JSONObject]).contains(where:{$0["entries"] != nil}),"Nonfinancial response omits costs and rates")
check(failed(call(reader,"list_clients",["limit":true])),"Boolean rejected as pagination integer")
check(failed(call(reader,"list_projects",["unexpected":1])),"Unknown fields rejected")
check(writer.receive("broken")?["error"] != nil,"Malformed JSON rejected")
for token in CalculationDraft.PricingToken.allCases {
    let parsed = try CalculationDraft.phases([["name":"Mode check","entries":[["name":"Specialist","pricing":token.rawValue]]]])
    check(parsed[0].entries[0].pricing == token.pricing,"Pricing mode \(token.rawValue)")
}
private var locked=try fixture.project(id:UUID(uuidString:id)!)!
locked.estimate.acceptedProposalID = UUID()
_ = try fixture.save(locked)
check(failed(call(writer,"append_project_phases",["project_id":id,"phases":[phase]])),"Approved calculations protected")
locked.estimate.archivedAt = .now
_ = try fixture.save(locked)
check(failed(call(writer,"append_project_phases",["project_id":id,"phases":[phase]])),"Archived calculations protected")
testPermissions.remove("mcpAllowFinancials")
check(failed(call(writer,"get_project",["project_id":id,"include_financials":true])), "Financial access can be revoked during a session")
check(failed(call(writer,"get_business_overview",["year":2026])), "Revoking financial access blocks business reports")
testPermissions.remove("mcpAllowWrite")
private let revokedTools = (send(writer, "tools/list")["result"] as! JSONObject)["tools"] as! [JSONObject]
check(Set(revokedTools.compactMap { $0["name"] as? String }) == ["list_projects", "get_project", "list_clients"], "Revoked permissions disappear from the tool catalog")
check(failed(call(writer,"create_client",["name":"Forbidden"])), "Write access can be revoked during a session")
_ = payload(call(writer,"list_projects"))
testPermissions.insert("mcpAllowWrite")
_ = payload(call(writer,"create_client",["name":"Fixture after reauthorization"]))
testEnabled=false
check(failed(call(writer,"list_projects")),"Disabling connection stops existing session")
private let diskBytes = try Data(contentsOf:path)
check(!diskBytes.starts(with:Data("SQLite format 3".utf8)),"Fixture library encrypted on disk")
print("MCP protocol and encrypted-library operation checks passed. Authentication is substituted only in this generated test executable.")
