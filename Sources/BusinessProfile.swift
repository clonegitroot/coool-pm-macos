import AppKit

struct LetterFont: RawRepresentable, Codable, Hashable {
    let rawValue: String
    static let arial = Self(rawValue: "Arial")
    static var allCases: [Self] {
        NSFontManager.shared.availableFontFamilies.sorted().map(Self.init(rawValue:))
    }
    func face(bold: Bool) -> String {
        NSFontManager.shared.font(withFamily: rawValue, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: 12)?.fontName ?? rawValue
    }
}

struct DocumentStyle: Codable, Equatable {
    var header = "Brand and contact"
    var headerText = ""
    var customFooter = false
    var leftFooter = ""
    var middleFooter = ""
    var rightFooter = ""
    var pageNumbers = true
    var phase = "Shaded band"
    var uppercase = true
    var bodySize = 11
    var phaseSize = 11
    var termsSize = 10
    var twoColumns = false
    var headerFont: LetterFont?
    var footerFont: LetterFont?
    var phaseFont: LetterFont?
    var termsFont: LetterFont?
}

struct BusinessProfile: Codable, Equatable {
    var usageFeatures: UsageFeatures?
    var features: UsageFeatures { usageFeatures ?? .full }
    var numbering: NumberingPreferences?
    var defaultPaymentDays: Int?
    var newClientTerms: String { "\(defaultPaymentDays ?? 30) days" }
    var name = ""
    var city = ""
    var contact = ""
    var bank = ""
    var taxNumber = ""
    var vatID = ""
    var vat = 19
    var defaultExemptionReason: String?
    var termsDE = ""
    var termsEN = ""
    var proposalFont = LetterFont.arial
    var invoiceFont = LetterFont.arial
    var styling: DocumentStyle?
    var detailed = false
    var logo: Data?
    var electronicInvoice: ElectronicInvoiceDefaults?

    static func load(_ defaults: UserDefaults = .standard) -> Self {
        (try? read(defaults)) ?? Self()
    }

    /// Backup capture uses the throwing form so a damaged profile cannot silently become an empty one.
    static func read(_ defaults: UserDefaults = .standard) throws -> Self {
        if let data = try VaultPreferences.data("businessProfile", in: defaults) {
            return try JSONDecoder().decode(Self.self, from: data)
        }
        var profile = Self()
        profile.name = VaultPreferences.text("documentSender", in: defaults) ?? ""
        profile.contact = VaultPreferences.text("letterContact", in: defaults) ?? ""
        profile.bank = VaultPreferences.text("letterBank", in: defaults) ?? ""
        return profile
    }
    func save(_ defaults: UserDefaults = .standard) throws {
        try VaultPreferences.set(JSONEncoder().encode(self), for: "businessProfile", in: defaults)
    }
    func apply(to document: inout ClientDocument) {
        document.style = styling ?? DocumentStyle()
        document.sender = name
        document.city = city
        document.contactDetails = contact
        document.bankDetails = bank
        document.taxNumber = taxNumber
        document.vatID = vatID
        document.font = document.invoice ? invoiceFont : proposalFont
        document.logo = logo
        let terms = document.german ? termsDE : termsEN
        document.termsText = [terms, document.termsText].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

enum UsageFeature: String, Codable, CaseIterable {
    case teamPlanning, costControlling, advancedBilling, businessReporting, integrations, personalGoals

    var title: String {
        switch self {
        case .teamPlanning: "Team planning"
        case .costControlling: "Cost controlling"
        case .advancedBilling: "Advanced billing"
        case .businessReporting: "Detailed business reports"
        case .integrations: "Integrations"
        case .personalGoals: "Monthly earnings goals"
        }
    }
    var detail: String {
        switch self {
        case .teamPlanning: "Freelancer directory and internal or external crew in calculations."
        case .costControlling: "Internal cost rates, commitments, time tracking, forecasts and DB1/DB2."
        case .advancedBilling: "Split billing schedules, instalments and electronic invoice tools."
        case .businessReporting: "Project breakdowns, contribution margins and financial CSV exports."
        case .integrations: "Show the optional MCP connection controls. Enabling a profile never grants AI access."
        case .personalGoals: "Set personal monthly invoicing targets and compare progress."
        }
    }
}

struct UsageFeatures: Codable, Equatable {
    var teamPlanning = true
    var costControlling = true
    var advancedBilling = true
    var businessReporting = true
    var integrations = true
    var personalGoals = true
    static let full = Self()

    func enabled(_ feature: UsageFeature) -> Bool {
        switch feature {
        case .teamPlanning: teamPlanning
        case .costControlling: costControlling
        case .advancedBilling: advancedBilling
        case .businessReporting: businessReporting
        case .integrations: integrations
        case .personalGoals: personalGoals
        }
    }
    mutating func set(_ feature: UsageFeature, enabled: Bool) {
        switch feature {
        case .teamPlanning: teamPlanning = enabled
        case .costControlling: costControlling = enabled
        case .advancedBilling: advancedBilling = enabled
        case .businessReporting: businessReporting = enabled
        case .integrations: integrations = enabled
        case .personalGoals: personalGoals = enabled
        }
    }
    func resolving(_ overrides: UsageFeatureOverrides?) -> Self {
        guard let overrides else { return self }
        var resolved = self
        for feature in UsageFeature.allCases {
            if let value = overrides.value(feature) { resolved.set(feature, enabled: value) }
        }
        return resolved
    }
    var profileTitle: String {
        self == .full ? "All features" : UsageProfile.allCases.first { $0.features == self }?.title ?? "Custom"
    }
}

enum UsageProfile: String, CaseIterable {
    case solo, producer, manager
    var title: String {
        switch self {
        case .solo: "Solo creative"
        case .producer: "Creative producer"
        case .manager: "Project manager"
        }
    }
    var detail: String {
        switch self {
        case .solo: "Clients, estimates, proposals, invoices and payments. A simple income, expenses and profit overview."
        case .producer: "Production phases, crew, external costs, change orders and detailed project margins."
        case .manager: "Clients, teams, budgets, forecasts, staged billing and detailed business reports."
        }
    }
    var features: UsageFeatures {
        switch self {
        case .solo: UsageFeatures(teamPlanning: false, costControlling: false, advancedBilling: false,
                                  businessReporting: false, integrations: false)
        case .producer: UsageFeatures(businessReporting: false, integrations: false)
        case .manager: UsageFeatures(integrations: false, personalGoals: false)
        }
    }
}

struct UsageFeatureOverrides: Codable, Equatable {
    private var values: [String: Bool] = [:]
    func value(_ feature: UsageFeature) -> Bool? { values[feature.rawValue] }
    mutating func set(_ feature: UsageFeature, enabled: Bool?) { values[feature.rawValue] = enabled }
    var isEmpty: Bool { values.isEmpty }
}
