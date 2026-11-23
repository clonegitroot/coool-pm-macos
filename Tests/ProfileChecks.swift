import Foundation

func runProfileChecks() throws {
    let old = try JSONDecoder().decode(BusinessProfile.self, from: JSONEncoder().encode(BusinessProfile()))
    precondition(old.features == .full)
    precondition(UsageProfile.solo.features.costControlling == false)
    precondition(UsageProfile.manager.features.personalGoals == false)
    precondition(UsageProfile.allCases.allSatisfy { !$0.features.integrations })

    var overrides = UsageFeatureOverrides()
    overrides.set(.teamPlanning, enabled: true)
    overrides.set(.costControlling, enabled: false)
    precondition(UsageProfile.solo.features.resolving(overrides).teamPlanning)
    precondition(!UsageFeatures.full.resolving(overrides).costControlling)
    overrides.set(.teamPlanning, enabled: nil)
    precondition(!UsageProfile.solo.features.resolving(overrides).teamPlanning)

    var estimate = Estimate()
    estimate.phases = [Phase(entries: [Entry(pricing: .team, quantity: 2, rate: 500, cost: 300),
                                      Entry(pricing: .crew, quantity: 1, rate: 400, cost: 250)])]
    estimate.projectRebatePercent = 10
    let before = estimate.calculate()
    estimate.featureOverrides = overrides
    let restored = try JSONDecoder().decode(Estimate.self, from: JSONEncoder().encode(estimate))
    let after = restored.calculate()
    precondition(before.totals.sales == after.totals.sales && before.totals.db2 == after.totals.db2)
    precondition(restored.featureOverrides == overrides)
    for profile in UsageProfile.allCases {
        var business = BusinessProfile()
        business.usageFeatures = profile.features
        let decoded = try JSONDecoder().decode(BusinessProfile.self, from: JSONEncoder().encode(business))
        precondition(decoded.features == profile.features)
    }
    print("Usage profile defaults, per-project inheritance, persistence and financial preservation passed.")
}
