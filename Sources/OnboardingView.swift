import SwiftUI

struct OnboardingView: View {
    let onFinish: (Bool) -> Void

    @State private var features: UsageFeatures
    @State private var originalFeatures: UsageFeatures
    @State private var showingDemo = false
    @State private var step = Step.language
    @State private var appLanguage: AppLanguage
    @State private var documentLanguage: AppLanguage
    @State private var profile: BusinessProfile
    @State private var originalAppLanguage: AppLanguage
    @State private var originalDocumentLanguage: AppLanguage
    @State private var originalProfile: BusinessProfile
    @State private var library = DayRateLibrary(data: (try? VaultPreferences.data(DayRateLibrary.storageKey)) ?? Data())
    @State private var newSchedule: DayRateSchedule?
    @State private var editingSchedule: DayRateSchedule?
    @State private var useNewScheduleByDefault = false
    @State private var error: String?

    init(onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
        let defaults = UserDefaults.standard
        let appLanguage = defaults.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .system
        let documentLanguage = defaults.string(forKey: "documentLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .german
        let profile = BusinessProfile.load(defaults)
        _appLanguage = State(initialValue: appLanguage)
        _documentLanguage = State(initialValue: documentLanguage)
        let features = profile.usageFeatures ?? (defaults.bool(forKey: "hasCompletedOnboarding") ? .full : UsageProfile.solo.features)
        _features = State(initialValue: features)
        _originalFeatures = State(initialValue: features)
        _profile = State(initialValue: profile)
        _originalAppLanguage = State(initialValue: appLanguage)
        _originalDocumentLanguage = State(initialValue: documentLanguage)
        _originalProfile = State(initialValue: profile)
    }

    private enum Step: String, CaseIterable {
        case language = "Language"
        case usage = "Usage profile"
        case business = "Your business"
        case numbering = "Client defaults"
        case rates = "Day rates"

        var icon: String {
            switch self {
            case .language: "globe"
            case .usage: "slider.horizontal.3"
            case .business: "building.2"
            case .numbering: "number"
            case .rates: "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(alignment: .leading, spacing: 20) {
                    switch step {
                    case .language: languageStep
                    case .usage:
                        heading("How will you mainly use Coool PM?", "Choose a starting point. You can change profiles and individual features later in Settings.")
                        UsageProfilePicker(features: $features)
                    case .business: businessStep
                    case .numbering:
                        heading("Client defaults", "Choose a format for new client numbers and a payment deadline for new clients.")
                        Form { ClientDefaultsFields(profile: $profile) }
                    case .rates: ratesStep
                    }
                    Spacer(minLength: 0)
                    if let error {
                        Text(LocalizedStringKey(error))
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 560)
        .sheet(isPresented: $showingDemo) { DemoLibraryView(startTour: true).environment(\.locale, appLanguage.locale) }
        .sheet(item: $editingSchedule) { draft in
            RateTierEditor(name: draft.name, tiers: draft.tiers, saveNamed: { name, tiers in
                var staged = library
                var schedule = draft
                schedule.name = name
                schedule.tiers = tiers
                try staged.save(schedule)
                if newSchedule == nil {
                    useNewScheduleByDefault = library.schedules.isEmpty
                }
                newSchedule = schedule
                error = nil
            })
            .environment(\.locale, appLanguage.locale)
        }
        .environment(\.locale, appLanguage.locale)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            Label {
                Text(verbatim: "Coool PM").font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: "square.stack.3d.up")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Step.allCases, id: \.self) { item in
                    Label(LocalizedStringKey(item.rawValue), systemImage: item.icon)
                        .font(.callout.weight(step == item ? .semibold : .regular))
                        .foregroundStyle(step == item ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 9)
                        .background(step == item ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .accessibilityAddTraits(step == item ? .isSelected : [])
                }
            }
        }
        .padding(18)
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }

    private var languageStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Welcome to Coool PM", "Choose the language for the app and the default for proposals and invoices.")
            Form {
                Picker("App language", selection: $appLanguage) {
                    Text("System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Deutsch").tag(AppLanguage.german)
                }
                Picker("Default document language", selection: $documentLanguage) {
                    Text(verbatim: "Deutsch").tag(AppLanguage.german)
                    Text(verbatim: "English").tag(AppLanguage.english)
                }
            }
            .frame(maxWidth: 405)
            VStack(alignment: .leading, spacing: 8) {
                Button("Explore demo library…", systemImage: "sparkles") { showingDemo = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Try a sample project with a guided tour you can skip at any time.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Your business", "Add the details you want on client documents. You can fill these in later in Settings.")
            Form {
                TextField("Business name", text: $profile.name)
                TextField("City on letters", text: $profile.city)
                RichField("Address and contact", text: $profile.contact, height: 62)
                TextField("Tax number", text: $profile.taxNumber)
                TextField("VAT ID", text: $profile.vatID)
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 405)
            Text("You can add electronic invoice details later in Settings → XRechnung.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var ratesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Your day rates", "Set a flat or progressive rate for your own work. You can update rates any time in Settings.")
            if let saved = library.defaultSchedule {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current default").font(.caption).foregroundStyle(.secondary)
                    Text(saved.name).font(.body.weight(.medium))
                    RateTierSummary(tiers: saved.tiers)
                }
            }
            if let newSchedule {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(newSchedule.name).font(.body.weight(.medium))
                        Spacer()
                        Button("Edit…") { editingSchedule = newSchedule }
                        Button("Remove from setup") {
                            self.newSchedule = nil
                            error = nil
                        }
                    }
                    RateTierSummary(tiers: newSchedule.tiers)
                    Toggle("Use for new projects", isOn: $useNewScheduleByDefault)
                        .help("Apply a copy of this rate schedule whenever you create a project.")
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Button("Add a rate schedule…", systemImage: "plus") {
                    editingSchedule = DayRateSchedule()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip setup") { finish(startProject: false) }
            Spacer()
            if step != .language {
                Button("Back") {
                    step = Step.allCases[Step.allCases.firstIndex(of: step)! - 1]
                    error = nil
                }
            }
            if step == .rates {
                Button("Open library") { finish(startProject: false) }
                Button("Start project") { finish(startProject: true) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") { step = Step.allCases[Step.allCases.firstIndex(of: step)! + 1] }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func heading(_ title: LocalizedStringKey, _ description: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func finish(startProject: Bool) {
        do {
            let defaults = UserDefaults.standard
            var ratesData: Data?
            if let newSchedule {
                var updated = DayRateLibrary(data: try VaultPreferences.data(DayRateLibrary.storageKey, in: defaults) ?? Data())
                try updated.save(newSchedule)
                if useNewScheduleByDefault { updated.defaultID = newSchedule.id }
                ratesData = try updated.encoded()
            }
            if profile != originalProfile || features != originalFeatures || profile.usageFeatures == nil {
                var updated = BusinessProfile.load(defaults)
                for field in [\BusinessProfile.name, \.city, \.contact, \.taxNumber, \.vatID] {
                    if profile[keyPath: field] != originalProfile[keyPath: field] {
                        updated[keyPath: field] = profile[keyPath: field]
                    }
                }
                if profile.numbering != originalProfile.numbering { updated.numbering = profile.numbering }
                if profile.defaultPaymentDays != originalProfile.defaultPaymentDays { updated.defaultPaymentDays = profile.defaultPaymentDays }
                updated.usageFeatures = features
                try updated.save(defaults)
            }
            if let ratesData { try VaultPreferences.set(ratesData, for: DayRateLibrary.storageKey, in: defaults) }
            if appLanguage != originalAppLanguage { defaults.set(appLanguage.rawValue, forKey: "appLanguage") }
            if documentLanguage != originalDocumentLanguage {
                defaults.set(documentLanguage.rawValue, forKey: "documentLanguage")
            }
            if !features.integrations { defaults.set(false, forKey: "mcpEnabled") }
            onFinish(startProject)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
