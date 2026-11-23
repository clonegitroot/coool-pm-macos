import SwiftUI

struct PricingCategorySettings: View {
    @Environment(\.locale) private var locale
    @ProtectedSetting(PricingCatalog.storageKey) private var catalogData = Data()
    @State private var editor: Editor?
    @State private var error: String?

    private struct Editor: Identifiable {
        var id = UUID()
        var builtIn: Pricing?
        var preset: PricingPreset?
    }

    private var catalog: PricingCatalog { PricingCatalog(data: catalogData) }

    var body: some View {
        Group {
            Section("Built-in categories") {
                ForEach(Pricing.allCases, id: \.self) { pricing in
                    HStack {
                        category(catalog.name(for: pricing, locale: locale), basis: pricing,
                                 showBasis: catalog.overridesName(for: pricing))
                        Button("Rename…") { editor = Editor(builtIn: pricing) }
                        if catalog.overridesName(for: pricing) {
                            Button("Use default name") { reset(pricing) }
                        }
                    }
                }
            }
            Section("Custom categories") {
                ForEach(catalog.presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { preset in
                    HStack {
                        category(preset.name, basis: preset.basis)
                        Button("Rename…") { editor = Editor(preset: preset) }
                    }
                }
                Button("New pricing category…", systemImage: "plus") { editor = Editor() }
                    .help("Use an existing calculation method with your own category name.")
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editor) { editor in
            let name = editor.builtIn.map { catalog.name(for: $0, locale: locale) } ?? editor.preset?.name ?? ""
            PricingCategoryEditor(name: name, fixedBasis: editor.builtIn ?? editor.preset?.basis) { name, basis in
                var updated = catalog
                if let pricing = editor.builtIn {
                    try updated.setName(name, for: pricing, locale: locale)
                } else {
                    var preset = editor.preset ?? PricingPreset(name: name, basis: basis)
                    preset.name = name
                    try updated.save(preset, locale: locale)
                }
                catalogData = updated.data
                error = nil
            }
        }
    }

    private func category(_ name: String, basis: Pricing, showBasis: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
            if showBasis {
                Text(LocalizedStringKey(basis.titleKey))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reset(_ pricing: Pricing) {
        var updated = catalog
        do {
            try updated.setName(nil, for: pricing, locale: locale)
            catalogData = updated.data
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct PricingCategoryEditor: View {
    @State var name: String
    let fixedBasis: Pricing?
    let save: (String, Pricing) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var basis = Pricing.fee
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(fixedBasis == nil ? "New pricing category" : "Rename pricing category").font(.title2.bold())
            TextField("Category name", text: $name).focused($nameFocused)
            if let fixedBasis {
                LabeledContent("Calculation method") { Text(LocalizedStringKey(fixedBasis.titleKey)) }
            } else {
                Picker("Calculation method", selection: $basis) {
                    ForEach(Pricing.allCases, id: \.self) { pricing in
                        Text(LocalizedStringKey(pricing.titleKey)).tag(pricing)
                    }
                }
                .help("The calculation method stays fixed after you save the category.")
            }
            if let error {
                Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: submit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onAppear { nameFocused = true }
    }

    private func submit() {
        do {
            try save(name, fixedBasis ?? basis)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
