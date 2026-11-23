import Foundation

struct PricingPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    let basis: Pricing
}

struct PricingCatalog: Codable {
    static let storageKey = "pricingCatalog"

    private var builtInLabels: [String: String] = [:]
    private(set) var presets: [PricingPreset] = []

    init(data: Data = Data()) {
        if let saved = try? JSONDecoder().decode(Self.self, from: data) { self = saved }
    }

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }

    func defaultName(for pricing: Pricing, locale: Locale) -> String {
        AppLanguage.text(pricing.titleKey, fallback: pricing.titleKey, locale: locale)
    }

    func name(for pricing: Pricing, locale: Locale) -> String {
        builtInLabels[pricing.rawValue] ?? defaultName(for: pricing, locale: locale)
    }

    func overridesName(for pricing: Pricing) -> Bool {
        builtInLabels[pricing.rawValue] != nil
    }

    mutating func setName(_ name: String?, for pricing: Pricing, locale: Locale) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.isEmpty { throw LibraryError(description: "Enter a category name.") }
        let defaultName = defaultName(for: pricing, locale: locale)
        let label = trimmed ?? defaultName
        let names = Pricing.allCases.filter { $0 != pricing }.map { self.name(for: $0, locale: locale) } + presets.map(\.name)
        try validateUnique(label, among: names)
        builtInLabels[pricing.rawValue] = label == defaultName ? nil : trimmed
    }

    mutating func save(_ preset: PricingPreset, locale: Locale) throws {
        var updated = preset
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty else { throw LibraryError(description: "Enter a category name.") }
        let names = Pricing.allCases.map { name(for: $0, locale: locale) }
            + presets.filter { $0.id != updated.id }.map(\.name)
        try validateUnique(updated.name, among: names)
        if let index = presets.firstIndex(where: { $0.id == updated.id }) {
            guard presets[index].basis == updated.basis else {
                throw LibraryError(description: "A saved category keeps its original calculation method.")
            }
            presets[index] = updated
        } else {
            presets.append(updated)
        }
    }

    private func validateUnique(_ name: String, among existing: [String]) throws {
        guard !existing.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            throw LibraryError(description: "That category name is already in use.")
        }
    }
}
