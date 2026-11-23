import Foundation

struct DayRateSchedule: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var tiers: [RateTier] = [RateTier(lastDay: nil, rate: 0)]
}

struct DayRateLibrary: Codable, Equatable {
    static let storageKey = "dayRateLibrary"
    var schedules: [DayRateSchedule] = []
    var defaultID: UUID?

    init() {}

    init(data: Data) {
        self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self()
    }

    var defaultSchedule: DayRateSchedule? {
        schedules.first { $0.id == defaultID }
    }

    var sortedSchedules: [DayRateSchedule] {
        schedules.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    mutating func save(_ schedule: DayRateSchedule) throws {
        var saved = schedule
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saved.name.isEmpty, RateTier.valid(saved.tiers) else {
            throw LibraryError(description: "Enter a schedule name and valid day rates.")
        }
        guard !schedules.contains(where: { $0.id != saved.id && $0.name.caseInsensitiveCompare(saved.name) == .orderedSame }) else {
            throw LibraryError(description: "A rate schedule with that name already exists.")
        }
        if let index = schedules.firstIndex(where: { $0.id == saved.id }) { schedules[index] = saved }
        else { schedules.append(saved) }
    }

    mutating func remove(_ id: UUID) {
        schedules.removeAll { $0.id == id }
        if defaultID == id { defaultID = nil }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

extension Estimate {
    mutating func applyDayRates(_ saved: DayRateSchedule) {
        guard RateTier.valid(saved.tiers) else { return }
        customTiers = saved.tiers
        appliedDayRateName = saved.name
    }
}
