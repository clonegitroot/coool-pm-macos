import SwiftUI

struct DayRateSettings: View {
    @Environment(\.locale) private var locale
    @ProtectedSetting(DayRateLibrary.storageKey) private var libraryData = Data()
    @State private var draft: DayRateSchedule?
    @State private var removing: DayRateSchedule?
    @State private var error: String?

    private var library: DayRateLibrary { DayRateLibrary(data: libraryData) }

    var body: some View {
        Group {
            Section {
                Picker("Default for new projects", selection: defaultSelection) {
                    Text("Set rates per project").tag(UUID?.none)
                    ForEach(library.sortedSchedules) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("Saved rate schedules") {
                if library.schedules.isEmpty {
                    Text("No saved rate schedules").foregroundStyle(.secondary)
                }
                ForEach(library.sortedSchedules) { saved in
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(saved.name).font(.body.weight(.medium))
                            RateTierSummary(tiers: saved.tiers)
                        }
                        Spacer(minLength: 0)
                        Button("Edit…") { draft = saved }
                        Menu {
                            Button("Duplicate…") { draft = DayRateSchedule(tiers: saved.tiers) }
                            Button("Remove schedule…", role: .destructive) { removing = saved }
                        } label: { Label("Schedule actions", systemImage: "ellipsis.circle") }
                            .labelStyle(.iconOnly).menuIndicator(.hidden).fixedSize()
                    }.padding(.vertical, 4)
                }
                Button("New rate schedule…", systemImage: "plus") { draft = DayRateSchedule() }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $draft) { schedule in
            RateTierEditor(name: schedule.name, tiers: schedule.tiers, saveNamed: { name, tiers in
                var updated = library
                var saved = schedule
                saved.name = name
                saved.tiers = tiers
                try updated.save(saved)
                libraryData = try updated.encoded()
            }).environment(\.locale, locale)
        }
        .confirmationDialog("Remove this rate schedule?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        )) {
            Button("Remove schedule", role: .destructive) {
                if let removing { update { $0.remove(removing.id) } }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }

    private var defaultSelection: Binding<UUID?> {
        Binding(get: { library.defaultSchedule?.id }, set: { id in update { $0.defaultID = id } })
    }

    private func update(_ change: (inout DayRateLibrary) -> Void) {
        do {
            var updated = library
            change(&updated)
            libraryData = try updated.encoded()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
